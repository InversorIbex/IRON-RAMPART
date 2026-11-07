# Arquitectura

Principio rector: **la lógica de juego es datos + servicios puros (RefCounted), testeables sin escena;
las escenas solo renderizan y traducen input.**

## Mapa de carpetas

```
project.godot            Configuración (1920x1080 lógico, GL Compatibility, landscape)
assets/                  Arte y audio finales (vacío: aún solo placeholders procedurales)
data/
  levels/*.json          Misiones (layout + identidad + reglas + oleadas) -> LevelLoader
  structures/*.tres      StructureData                                  -> StructureCatalog
  enemies/*.tres         EnemyData                                      -> EnemyCatalog
  turrets/*.tres         TurretData (arma), referenciada por data/structures/turret_*.tres
scenes/
  menus/main_menu.tscn   Escena principal (run/main_scene)
  gameplay/battle.tscn   Misión jugable
  enemies/enemy_view.tscn  Vista reutilizable de un enemigo (instanciada por EnemyLayer)
  turrets/turret_view.tscn Arma giratoria de una torreta (instanciada por CombatLayer)
scripts/
  core/                  Palette, GameSession (estado + máquina de estados), MissionStats, MissionScore
  grid/                  Terrain, GridModel, Placement
  navigation/            MovementClass, NavGrid (campos de flujo por clase)
  construction/          StructureData, StructureCatalog, ConstructionService
  enemies/               EnemyData, EnemyCatalog, Enemy, EnemyRoster, EnemyView
  combat/                Damage, Targeting, TurretData, TurretState, Projectile, CombatSystem, TurretView
  economy/               Wallet
  levels/                LevelData, LevelLoader
  waves/                 WaveData (oleada + grupos, calendario), WaveManager
  gameplay/              Battle, GridView, EnemyLayer, CombatLayer, BattleCamera
  ui/                    UiTheme, BattleHud, Sfx (sonido sintetizado provisional)
  menus/                 MainMenu
tests/
  run_tests.gd           Runner headless (admite pruebas con await)
  unit/                  Suites unitarias + smoke de escenas
  visual/                Recorridos E2E con render y capturas (drive_battle, drive_enemies, drive_combat)
  perf/                  bench_enemies.gd, bench_combat.gd, bench_mission.gd (lógica headless o con render)
  sim/                   strategy_bot.gd (jugador scripted), sim_mission.gd (comparación de estrategias)
docs/                    Documentación (.gdignore: Godot no la importa)
```

## Sistemas y dependencias

```
LevelLoader ──crea──> LevelData
                          │
GameSession ──posee──> GridModel ──señales placement_added/removed──> NavGrid (campos de flujo)
     │                                                                   │ topology_changed
     ├──posee──> Wallet                                                  ▼
     ├──posee──> EnemyRoster ──lee next_step()──────────────────────── NavGrid
     │               ▲ occupied_cells / route_requirements   ▲ damage() (única puerta de daño)
     ├──posee──> ConstructionService ──valida con──> NavGrid.find_broken_routes
     │                               ──consulta──> EnemyRoster (opcional); price_of() (recargo)
     ├──posee──> CombatSystem ──escucha placement_added/removed──> GridModel
     │                        ──Targeting.select (NavGrid.distance)──> EnemyRoster.damage()
     ├──posee──> WaveManager ──calendario de LevelData.waves──> EnemyRoster.spawn()
     └──posee──> MissionStats (bajas, créditos, fugas) ──> MissionScore

Battle (Node2D) ──posee──> GameSession; Sfx
   ├── GridView (Node2D)  ─ terreno, estructuras, rutas (de NavGrid), fantasma
   │     ├── EnemyLayer (Node2D) ─ crea/libera EnemyView según señales de EnemyRoster
   │     └── CombatLayer (Node2D) ─ TurretView por torreta + proyectiles/efectos en un _draw
   ├── BattleCamera (Camera2D) ─ zoom/pan
   └── CanvasLayer/BattleHud (Control) ─ intenciones: tool_changed, assault_requested, restart, menu
```

**Sin dependencias circulares** (auditado en los Hitos 2 y 3): `GridModel` no conoce a nadie; `NavGrid` → `GridModel`;
`EnemyRoster` → `GridModel`, `NavGrid`; `ConstructionService` → `GridModel`, `NavGrid`, `Wallet`, `EnemyRoster`;
`CombatSystem` → `GridModel`, `EnemyRoster`, `NavGrid`; `GameSession` → todos. Ningún servicio conoce nodos;
construcción no conoce combate y combate no conoce construcción.

**Una sola fuente de verdad:** `GridModel` es la única verdad de bloqueo; `NavGrid` se sincroniza solo
escuchando sus señales (antes dependía de llamadas manuales: hallazgo H1 de la auditoría).

## Componentes

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `LevelData` / `LevelLoader` | RefCounted / estático | Misión JSON validada; reglas `allow_build_during_combat`, `allow_remove_during_combat` |
| `Terrain`, `GridModel`, `Placement` | constantes / RefCounted | Terreno + ocupación, conversiones celda↔local, huellas multicelda |
| `MovementClass` | constantes | Bits INFANTRY=1, WHEELED=2, TRACKED=4 |
| `NavGrid` | RefCounted | Por clase: mapa transitable + **campo de flujo** (BFS desde la meta). `next_step`, `distance`, `path_to_goal`, `find_broken_routes` (simulación sin tocar los campos vivos) |
| `StructureData` / `StructureCatalog` | Resource / estático | Estructuras: coste, vida, huella, `blocks_mask` |
| `ConstructionService` | RefCounted | `evaluate` (solo lectura), `build`, `remove_at`. Requisitos de ruta = spawns × clases + **enemigos vivos** |
| `EnemyData` / `EnemyCatalog` | Resource / estático | Vida, velocidad (celdas/s), blindaje (fracción), clase de movilidad, daño a base, recompensa, silueta |
| `Enemy` | RefCounted | Estado de un enemigo: `cell → next_cell` + `progress`, estado (MOVING/BLOCKED/ARRIVED/DEAD) |
| `EnemyRoster` | RefCounted | Spawn, `update(delta)`, daño, muertes, llegadas; señales `enemy_spawned/killed/reached_base/removed` |
| `GameSession` | RefCounted | Agrega todo; fases; vida del HQ (`base_hp_changed`); recompensas; derrota; `tick(delta)` |
| `Battle` | Node2D | Orquesta escena, input táctil/ratón, cámara, asalto de prueba |
| `GridView` / `EnemyLayer` / `EnemyView` | Node2D | Render placeholder; `EnemyLayer.sync` actualiza todas las vistas en un bucle |
| `BattleCamera` | Camera2D | Zoom 1×–3× en torno a un punto, pan con límites |
| `BattleHud` | Control | Estado, panel de construcción, feedback, pausa, derrota, safe areas |
| `WaveData` | RefCounted | Oleada: grupos (enemigo, cantidad, inicio, intervalo, spawn), modificadores, bono, condición de fin; `schedule()` determinista |
| `WaveManager` | RefCounted | Inicia oleadas, consume el calendario con el reloj de la oleada, señala tipos nuevos (aviso de tanques); fin = todo generado y nadie vivo |
| `MissionStats` / `MissionScore` | RefCounted / estático | Libro de la partida y fórmula de puntuación/estrellas (D-020) |
| `Sfx` | Node | Señales de audio sintetizadas para eventos de misión (D-022) |
| `Damage` | estático | Tabla tipo de daño × clase de blindaje (D-016) |
| `Targeting` | estático | Capas GROUND/AIR, prioridades FIRST/CLOSEST/STRONGEST, `select()` determinista O(enemigos) |
| `TurretData` | Resource | Arma: daño, tipo, cadencia, alcance, proyectil, velocidad, área, capas, prioridad, giro, tolerancia, silueta |
| `TurretState` / `Projectile` | RefCounted | Estado de una torreta (puntería, enfriamiento, objetivo, estadísticas) y de un proyectil |
| `CombatSystem` | RefCounted | Sigue torretas vía señales del grid; `update(delta)`: objetivo, giro, disparo, proyectiles, impactos, área |
| `CombatLayer` / `TurretView` | Node2D | Efectos (trazadoras, misiles con humo, chispas, explosiones, restos, quemaduras) y armas; señal `heavy_impact` → sacudida de cámara |

## Navegación (D-011)

- **Campo de flujo por clase:** `dist[celda]` = pasos hasta la meta por celdas transitables (BFS, O(celdas)).
  Se recalcula **solo** cuando cambia la topología (construir/retirar). Coste medido: ~0,33 ms para las tres
  clases en 24×16 (TESTING.md).
- **Enemigos:** ninguno busca caminos. Al llegar al centro de una celda consultan `next_step` (O(1)): el vecino
  con `dist − 1` en orden fijo E, O, S, N (desempate determinista → rutas en L limpias).
- **Ruta dibujada = ruta real:** `GridView` usa `path_to_goal`, que recorre el mismo campo.
- **Validación de construcción:** se clona el mapa transitable de las clases afectadas, se marcan las celdas
  candidatas y un BFS por clase responde para **todos** los requisitos (spawns + enemigos) a la vez. Los campos vivos
  no se tocan.

## Movimiento enemigo

- Cada enemigo recorre el segmento `cell → next_cell` (centro a centro) a `speed` celdas/s; `progress ∈ [0,1)`.
- **Segmento comprometido:** construcción rechaza `cell` y `next_cell` de cualquier enemigo (`OCCUPIED_BY_UNIT`), así
  que un cambio de laberinto nunca invalida el tramo en curso. El cambio se aplica en el siguiente centro de celda:
  sin teletransportes, sin atravesar muros, sin recálculos por fotograma.
- **Encerrar enemigos está prohibido:** cada enemigo vivo es un requisito de ruta desde su `next_cell`.
- **Ruta perdida (defensivo):** si aun así una celda queda sin ruta (p. ej. mutación directa del grid), el enemigo
  pasa a `BLOCKED`, se detiene en el centro de la celda y se reevalúa en el siguiente `topology_changed`.
- **Llegada:** al entrar en cualquier celda `B`, `ARRIVED` → `GameSession` resta `base_damage` al HQ → si llega a 0, `DEFEAT`
  (la simulación se congela).
- **Muerte:** `EnemyRoster.damage()` aplica `amount × (1 − armor)`; a hp ≤ 0 → `DEAD`, recompensa al `Wallet`, vista con
  animación de salida. (Aún no hay fuente de daño en juego: llega con las torretas en el Hito 3.)

## Estados de misión (Hito 4, D-018)

```
            start_wave()                 oleada resuelta (no última)          debrief_seconds
PREPARATION ───────────► WAVE_ACTIVE ─────────────────────────► WAVE_COMPLETED ────────────► PREPARATION
     ▲                       │   │                                  │ start_wave() (salta el resumen)
     │                       │   └── última oleada resuelta ──► VICTORY (final)
     │                       └────── HQ = 0 ───────────────────► DEFEAT  (final; también desde PREPARATION/WAVE_COMPLETED)
 pause()/resume(): cualquier estado no final ⇄ PAUSED (vuelve exactamente al anterior)
```

| Estado | Simulación (`tick`) | Oleadas | Construir | Recargo | Retirar |
|---|---|---|---|---|---|
| PREPARATION | resuelve lo que quede (en juego normal, nada) | no | sí | no | sí |
| WAVE_ACTIVE | oleadas → enemigos → (si no terminó) combate → ¿oleada resuelta? | sí | sí (regla de misión) | sí | regla de misión |
| WAVE_COMPLETED | como PREPARATION + cuenta atrás del resumen | no | sí | no | sí |
| PAUSED | nada | no | no | — | no |
| VICTORY / DEFEAT | nada; proyectiles vaciados | no | no | — | no |

Toda transición pasa por `GameSession._transition()`, que valida contra `TRANSITIONS`. Señales: `phase_changed`,
`wave_started`, `wave_completed` (antes del cambio de estado), `enemy_type_arrived`, `hq_damaged`, `base_hp_changed`,
`mission_ended(victory)`. `Battle` traduce START WAVE/PAUSE del HUD en `start_wave()`/`pause()`/`resume()` y pausa
también el árbol para congelar efectos.

## Combate (Hito 3)

Orden por tick (`GameSession.tick`): `EnemyRoster.update` → si la partida sigue, `CombatSystem.update`.

1. **Torretas** (`_update_turret`): enfriamiento; descartar objetivo muerto/fuera de alcance/incompatible; buscar
   objetivo si no hay o si está lista para disparar (como máximo cada 0,1 s, D-017); girar a `turn_speed`; disparar si
   está lista y alineada dentro de `aim_tolerance`; `cooldown += fire_interval` (cadencia exacta, sin acumular ráfagas
   en reposo).
2. **Proyectiles** (`_update_projectiles`): guiados mientras el objetivo vive; al llegar → `_impact` una sola vez.
   Bala sin objetivo = fallo (sin daño). Misil/flak = explosión en el punto (daño de área con caída).
3. **Daño** siempre por `EnemyRoster.damage(enemy, amount, type)` → blindaje → muerte → `enemy_killed` →
   recompensa en `GameSession`. Estadísticas por torreta: disparos, bajas, daño.
4. **Fin de partida:** en derrota se vacían los proyectiles y el combate deja de actualizarse (ni un disparo más).

Visualización: `TurretView` (arma, retroceso, fogonazo) y `CombatLayer` (proyectiles y hasta 400 efectos, un `_draw`
por frame mientras hay actividad). `GridView` dibuja la base estática de la torreta, el anillo de alcance (fantasma y
torreta seleccionada) y el precio sobre el fantasma.

## Flujo de construcción

1. HUD emite `tool_changed` → `Battle` guarda la herramienta.
2. Puntero sobre el mapa → `ConstructionService.evaluate` → `GridView.set_ghost` (verde/rojo, celdas afectadas marcadas).
   Con enemigos en movimiento la previsualización se revalida cada 0,2 s.
3. Soltar → `build`: límites → terreno → ocupación → enemigos encima → créditos (precio con recargo si es combate) →
   rutas (spawns + enemigos). El precio cobrado es el `cost` del mismo `Check` que se mostró.
4. Si es válido: `Wallet.spend` → `GridModel.add_placement` → (señal) `NavGrid` recalcula → `topology_changed` →
   `GridView` redibuja rutas; los enemigos usan el nuevo campo en su próxima celda.

## Input y cámara (Fase D del Hito 2)

| Gesto | Sin herramienta | Con herramienta |
|---|---|---|
| 1 dedo: tocar/arrastrar/soltar | arrastrar = desplazar mapa | apuntar; soltar = construir |
| 2 dedos | pellizco = zoom, arrastre = desplazar; **cancela la construcción en curso** | igual |
| Ratón | rueda = zoom en cursor; botón central = desplazar; izq. arrastrando sin herramienta = desplazar | izq. = apuntar/soltar; der./Esc = cancelar |

Con `emulate_mouse_from_touch`, el dedo 0 también genera eventos de ratón: mientras hay gesto multitáctil se ignoran
(nunca construyen). Toques que empiezan sobre el HUD no inician gestos.

## Señales relevantes

| Emisor | Señal | Consumidores |
|---|---|---|
| `GridModel` | `placement_added/removed` | `NavGrid` (sincronización) |
| `NavGrid` | `topology_changed(version)` | `GridView` (rutas), `EnemyRoster` (reintento de bloqueados) |
| `EnemyRoster` | `enemy_spawned` | `EnemyLayer` |
| `EnemyRoster` | `enemy_killed` | `GameSession` (recompensa), `EnemyLayer`, `CombatLayer` (restos) |
| `EnemyRoster` | `enemy_reached_base` | `GameSession` (daño HQ), `EnemyLayer` |
| `ConstructionService` | `structure_built/removed` | futuro: efectos, audio |
| `GridModel` | `placement_added/removed` | `CombatSystem` (alta/baja de torretas) |
| `CombatSystem` | `turret_added/removed`, `shot_fired`, `projectile_impact`, `explosion` | `CombatLayer`, `Battle` |
| `CombatLayer` | `heavy_impact` | `BattleCamera.add_shake` |
| `Wallet` | `credits_changed` | `BattleHud` |
| `GameSession` | `phase_changed`, `base_hp_changed` | `BattleHud` |
| `BattleHud` | `tool_changed`, `start_wave_requested`, `pause_requested`, `restart_requested`, `menu_requested` | `Battle` |
| `GameSession` | `wave_started`, `wave_completed`, `enemy_type_arrived`, `hq_damaged`, `mission_ended` | `BattleHud` (banners, INTEL, resultados), `Battle` (sacudida, `Sfx`) |
| `WaveManager` | `wave_started`, `enemy_type_arrived`, `wave_spawning_finished` | `GameSession` |

Rendimiento de señales: ninguna se emite por enemigo y fotograma; solo en eventos (spawn, muerte, llegada, cambio de topología).

## Reglas para añadir contenido

- **Nuevo enemigo terrestre:** `data/enemies/<id>.tres` (`EnemyData`) + una línea en `EnemyCatalog.PATHS`. Si su silueta
  existe, no hace falta código. Si es de una clase de movimiento nueva, ver abajo.
- **Nueva estructura:** `data/structures/<id>.tres` + una línea en `StructureCatalog.PATHS` + id en `available_structures`.
- **Nueva torreta:** `data/turrets/<id>.tres` (`TurretData`) + `data/structures/turret_<id>.tres` (category TURRET,
  `turret = ExtResource`) + registro en el catálogo. Si su silueta existe, no hace falta código.
- **Nuevo tipo de daño / blindaje:** fila/columna en `Damage.MULTIPLIER` y su enum.
- **Nueva misión:** `data/levels/<id>.json` con mapa, identidad, reglas y oleadas; el loader lo valida todo (incluida la
  conectividad). Ningún cambio de código salvo un tema visual nuevo (`LevelLoader.THEMES`) o una condición de victoria
  nueva (`VICTORY_TYPES` + lógica en `GameSession`).
- **Nueva clase de movimiento:** bit en `MovementClass` (y en `ALL`), flag en `StructureData.blocks_mask`, opción en
  `EnemyData.movement`, estilo en `GridView.ROUTE_STYLE` y `BattleHud.LEGEND_SHORT`. `NavGrid` crea su campo automáticamente.

## Pendiente de diseño (no implementado)

- **Unidades aéreas:** ignoran el laberinto; movimiento directo o campo propio sin obstáculos de tierra.
- **Unidades multicelda:** campo de flujo por tamaño usando un mapa de holgura (clearance).
- **Obstáculos destruibles / tanques aplastando sacos:** el mismo flujo `placement_removed → recálculo` ya lo soporta.
