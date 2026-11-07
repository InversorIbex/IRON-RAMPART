# CLAUDE.md — IRON RAMPART

Instrucciones permanentes para sesiones de Claude Code. Léelo entero antes de tocar código.

## Visión

Military Maze Tower Defense para Android (Godot 4, GDScript, 2D cenital, horizontal, offline).
Mecánica única: **el jugador construye el laberinto** que siguen los enemigos; nunca puede cerrar
todas las rutas. Detalle: `docs/GAME_DESIGN.md`.

## Estado del proyecto (actualiza esta sección al cerrar cada sesión)

- Hito 0 ✅ y Hito 1 ✅ verificados en Godot 4.7.2 (sesión 2): 40/40 pruebas, recorrido con render 14/14.
  Pendiente del Hito 1: prueba con dedo real en Android (se hará en el Hito 5).
- Siguiente: Hito 2 (enemigos y navegación). Ver `docs/ROADMAP.md`.
- Pendientes y riesgos: `docs/ROADMAP.md`.

## Comandos

```bash
godot --headless --path . --import                            # 1ª vez / tras añadir class_name
godot --headless --path . --script res://tests/run_tests.gd   # pruebas (exit 0 = OK)
godot --headless --path . --quit-after 300                    # smoke de arranque
godot --path .                                                # jugar
# Recorrido E2E con render + capturas (Linux sin pantalla: Xvfb)
IR_SHOTS_DIR=/tmp/shots xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
  --rendering-driver opengl3 --script res://tests/visual/drive_battle.gd
```

Verificados el 2026-11-07 con Godot 4.7.2-stable (todos exit 0). En un contenedor cloud Godot no está
instalado: hay que descargar el binario portable oficial (con autorización del usuario) y verificar su SHA-512.
Sin Godot: `gdparse`/`gdlint` (pip `gdtoolkit==4.*`) validan sintaxis y estilo, no semántica.

## Arquitectura (resumen; detalle en `docs/ARCHITECTURE.md`)

- Lógica = datos + servicios `RefCounted` sin nodos, testeables: `GridModel`, `NavGrid`, `ConstructionService`,
  `Wallet`, `LevelLoader`, agrupados en `GameSession` (una por intento de misión).
- Escenas (`Battle`, `GridView`, `BattleHud`, `MainMenu`) solo renderizan y traducen input. No guardan estado de juego.
- Navegación: `AStarGrid2D` por clase de movimiento (INFANTRY/WHEELED/TRACKED), ortogonal, recalculado solo en
  `NavGrid.topology_changed`.
- Toda construcción/retirada pasa por `ConstructionService` (`evaluate` es de solo lectura; un rechazo no cambia nada).
- Datos: niveles en `data/levels/*.json` (layout ASCII), estructuras en `data/structures/*.tres` registradas en
  `StructureCatalog.PATHS`.

## Convenciones

- GDScript con tipado estático en todo lo nuevo; indentación con tabuladores; líneas ≤ 130 (`gdlintrc`).
- `class_name` en PascalCase para tipos reutilizables; archivos en snake_case.
- Código, comentarios y textos de UI en **inglés**; documentación en **español**.
- Colores solo desde `Palette`. Nada de colores literales nuevos fuera de `Palette`/datos.
- Señales para eventos; llamadas directas para comandos. Sin autoloads salvo necesidad global real (D-008).
- Arrays empaquetados (`Packed*Array`) se copian al pasar/leer de propiedades: para acumular resultados usa
  `Array[T]` o construye local y asigna.
- Tras `if x is Tipo`, castea explícitamente (`x as Tipo`) antes de acceder a miembros del subtipo.
- UI creada por código: usa `set_anchors_and_offsets_preset()`, **nunca** `set_anchors_preset()` a secas
  (conserva el rect 0×0 inicial y deja el control fuera de pantalla). Lo vigila `test_scenes_smoke`.
- Tras cambiar UI, ejecuta `tests/visual/drive_battle.gd` y **mira las capturas**: las pruebas headless no ven el layout.
- Versiona los `*.uid` y `*.import` que genera Godot. `docs/` lleva `.gdignore` (no se importa al juego).

## Reglas para añadir sistemas

1. ¿Puede ser un dato (`Resource`/JSON) en vez de código? Hazlo dato.
2. Lógica nueva en un servicio `RefCounted` con pruebas en `tests/unit/`; el nodo solo la conecta.
3. Nueva suite → añádela a `SUITES` en `tests/run_tests.gd`.
4. Nueva estructura/nivel/clase de movimiento: sigue "Reglas para añadir contenido" en ARCHITECTURE.md.
5. Decisión técnica relevante → entrada nueva en `docs/DECISIONS.md`.
6. No crear managers/carpetas vacías "por si acaso".

## Restricciones

- Sin Firebase, servidores, cloud, APIs de pago, cuentas ni analítica.
- Rendimiento Android gama media: nada por frame que pueda ser por evento; nada de físicas para proyectiles de TD.
- Pedir confirmación antes de: instalar software global, añadir dependencias externas (p. ej. GUT), cambiar de
  motor, cambiar mecánicas centrales, operaciones destructivas de git, borrar archivos importantes.
- Keystores y credenciales nunca en el repositorio.

## Calidad y honestidad

- **Nunca** afirmes que algo funciona sin haberlo ejecutado. Distingue: implementado / probado automáticamente /
  probado manualmente / probado en Android.
- **Nunca** inventes resultados de pruebas ni salidas de comandos. Copia la salida real a TESTING.md.
- No marques ✅ en ROADMAP/TESTING sin evidencia. Placeholders son placeholders: no los llames arte final.
- No avances de hito sin cumplir el criterio de aceptación del anterior.

## Documentación

README.md · docs/GAME_DESIGN.md · docs/ARCHITECTURE.md · docs/DECISIONS.md · docs/ROADMAP.md ·
docs/ART_DIRECTION.md · docs/TESTING.md
