# Arquitectura

Principio rector: **la lógica de juego es datos + servicios puros (RefCounted), testeables sin escena;
las escenas solo renderizan y traducen input.**

## Mapa de carpetas

```
project.godot            Configuración (1920x1080 lógico, GL Compatibility, landscape)
assets/                  Arte y audio finales (vacío: aún solo placeholders procedurales)
data/
  levels/*.json          Misiones (layout ASCII + parámetros)       -> LevelLoader
  structures/*.tres      StructureData por estructura               -> StructureCatalog
scenes/
  menus/main_menu.tscn   Escena principal (run/main_scene)
  gameplay/battle.tscn   Misión jugable
scripts/
  core/                  Palette, GameSession (estado de una partida)
  grid/                  Terrain, GridModel, Placement
  navigation/            MovementClass, NavGrid (AStarGrid2D por clase)
  construction/          StructureData, StructureCatalog, ConstructionService
  economy/               Wallet
  levels/                LevelData, LevelLoader
  gameplay/              Battle (controlador de escena), GridView (render)
  ui/                    UiTheme, BattleHud
  menus/                 MainMenu
tests/                   Runner headless + suites unitarias y smoke
docs/                    Documentación
```

Carpetas futuras (se crean cuando haya código real): `scripts/combat`, `scripts/waves`, `scripts/enemies`,
`scripts/persistence`, `data/enemies`, `data/turrets`, `data/waves`.

## Sistemas y dependencias

```
LevelLoader ──crea──> LevelData
                          │
GameSession ──posee──> GridModel ◄── NavGrid (lee bloqueos; una AStarGrid2D por clase)
     │                    ▲              ▲
     ├──posee──> Wallet   │              │
     └──posee──> ConstructionService ────┘  (única puerta para construir/retirar)

Battle (Node2D) ──posee──> GameSession
   ├── GridView (Node2D)   lee GameSession, escucha NavGrid.topology_changed
   └── CanvasLayer/BattleHud (Control)  emite intenciones (tool_changed, restart, menu)
```

Sin dependencias circulares: los datos (`LevelData`, `StructureData`, `Placement`) no conocen servicios;
los servicios no conocen nodos; las escenas conocen servicios.

## Componentes

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `LevelData` | RefCounted | Misión parseada: dimensiones, terreno, spawns, base, `goal_cell`, clases de movimiento, créditos |
| `LevelLoader` | estático | JSON → `LevelData` con validación exhaustiva; errores acumulados y reportados con `push_error` |
| `Terrain` | constantes | Tipos de terreno, leyenda ASCII, reglas (construible, máscara de bloqueo) |
| `GridModel` | RefCounted | Terreno + ocupación (`Vector2i → Placement`), conversiones celda↔local, huellas multicelda |
| `Placement` | RefCounted | Instancia colocada: datos, origen, celdas, vida |
| `MovementClass` | constantes | Bits INFANTRY=1, WHEELED=2, TRACKED=4 |
| `NavGrid` | RefCounted | Un `AStarGrid2D` por clase; `find_path`, `find_broken_routes` (simulación con restauración) |
| `StructureData` | Resource | Coste, vida, huella, `blocks_mask`, reembolso, color placeholder, sprite opcional |
| `StructureCatalog` | estático | Registro id → `.tres`, carga + validación |
| `ConstructionService` | RefCounted | `evaluate` (solo lectura), `build`, `remove_at`; motivos de rechazo tipados |
| `Wallet` | RefCounted | Créditos, nunca negativos |
| `GameSession` | RefCounted | Agrega todo lo anterior + fase (BUILD/COMBAT/VICTORY/DEFEAT) y vida de la base |
| `Battle` | Node2D | Carga misión, crea sesión, layout, input → comandos |
| `GridView` | Node2D | Dibujo placeholder: terreno, estructuras, rutas por clase, fantasma de construcción |
| `BattleHud` | Control | Barra superior, panel de construcción, feedback, pausa, áreas seguras |

## Flujo de construcción

1. HUD emite `tool_changed(data, remove_mode)` → `Battle` guarda la herramienta.
2. Movimiento del puntero → `Battle._update_cursor` (solo si cambia la celda) → `ConstructionService.evaluate`
   → `GridView.set_ghost(check)` (verde/rojo, spawns afectados marcados).
3. Soltar sobre el mapa → `ConstructionService.build`:
   límites → terreno → ocupación → créditos → rutas (`NavGrid.find_broken_routes` simulado).
   Si algo falla: **no se toca nada** y se devuelve el motivo.
4. Si es válido: `Wallet.spend` → `GridModel.add_placement` → `NavGrid.refresh_cells` → `topology_changed`
   → `GridView` recalcula y redibuja rutas.

## Señales relevantes

| Emisor | Señal | Consumidores |
|---|---|---|
| `NavGrid` | `topology_changed(version)` | `GridView` (rutas); enemigos en Hito 2 (re-path) |
| `GridModel` | `placement_added/removed(placement)` | futuro: nodos visuales por estructura, audio |
| `ConstructionService` | `structure_built/removed` | futuro: efectos, estadísticas |
| `Wallet` | `credits_changed(credits, delta)` | `BattleHud` |
| `GameSession` | `phase_changed(phase)` | `BattleHud`; futuro `WaveManager` |
| `BattleHud` | `tool_changed`, `restart_requested`, `menu_requested` | `Battle` |

## Reglas para añadir contenido

- **Nueva estructura:** crear `data/structures/<id>.tres` (`StructureData`) + una línea en `StructureCatalog.PATHS`
  + añadir el id a `available_structures` de los niveles. Si su forma placeholder debe ser distinta, un caso en
  `GridView._draw_structure_shape`. Ningún otro sistema cambia.
- **Nuevo nivel:** nuevo `data/levels/*.json`. El loader valida conectividad inicial.
- **Nueva clase de movimiento:** añadir bit en `MovementClass` (y en `ALL`), el flag en `StructureData.blocks_mask`
  y su estilo en `GridView.ROUTE_STYLE`. `NavGrid` crea la capa automáticamente.

## Preparado para el Hito 2 (no implementado)

- Enemigos: seguirán `NavGrid.find_path(clase, celda_actual, goal)`; al recibir `topology_changed`
  recalculan desde la **siguiente celda** de su recorrido (sin teletransportes). Movimiento interpolado entre centros de celda.
- Construir durante combate: requerirá además rechazar celdas ocupadas por enemigos y comprobar que todo enemigo
  en el mapa conserva ruta. Por eso, hoy la construcción solo se permite en fase BUILD.
- Unidades multicelda: capa adicional por "tamaño" (mapa de holgura/clearance) en `NavGrid`.
