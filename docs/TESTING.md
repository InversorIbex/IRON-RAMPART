# Pruebas

## Cómo ejecutar

```bash
godot --headless --path . --import                         # obligatorio la 1ª vez: registra class_name
godot --headless --path . --script res://tests/run_tests.gd  # exit 0 = todo OK
```

Los errores de script dentro de `_ready()` no lanzan excepción en Godot: imprimen `SCRIPT ERROR` y siguen.
En CI hay que fallar también si la salida contiene `SCRIPT ERROR` o `Parse Error`:

```bash
godot --headless --path . --script res://tests/run_tests.gd 2>&1 | tee test.log
! grep -E "SCRIPT ERROR|Parse Error" test.log
```

Arranque del juego sin ventana (smoke de la escena principal, 300 frames):

```bash
godot --headless --path . --quit-after 300
```

Recorrido de juego con renderizado real (menú → batalla → construir, rechazo, rutas, retirar, pausa,
reiniciar) mediante la cadena de input real (`Viewport.push_input`), con capturas:

```bash
# Linux sin pantalla (Xvfb + Mesa). En escritorio basta con quitar "xvfb-run ...".
IR_SHOTS_DIR=/tmp/shots xvfb-run -a -s "-screen 0 1920x1080x24" \
  godot --path . --resolution 1920x1080 --rendering-driver opengl3 --script res://tests/visual/drive_battle.gd
```

Recorrido del Hito 2 (asalto, construir en combate, pellizco real, toque con zoom, derrota):
`... --script res://tests/visual/drive_enemies.gd` (mismos parámetros que el anterior).

Benchmark de enemigos (10/25/50/100, población constante, cambios de laberinto periódicos):

```bash
godot --headless --path . --script res://tests/perf/bench_enemies.gd               # lógica
xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --resolution 1920x1080 \
  --rendering-driver opengl3 --script res://tests/perf/bench_enemies.gd -- --render  # escena con render
```

Análisis estático (opcional, no requiere Godot): `pip install "gdtoolkit==4.*"` y luego
`gdparse <archivos>` (sintaxis) y `gdlint <archivos>` (estilo, usa `gdlintrc`).

## Estructura

- `tests/run_tests.gd` — runner (`extends SceneTree`). Lista explícita de suites.
- `tests/framework/test_case.gd` — base: `before_each`, `after_each`, `assert_*`.
- `tests/unit/test_helpers.gd` — niveles ASCII de prueba y estructuras sintéticas.
- `tests/unit/test_*.gd` — suites.
- `tests/visual/drive_battle.gd` — recorrido E2E del Hito 1 con render y capturas (no forma parte de `run_tests.gd`).
- `tests/visual/drive_enemies.gd` — recorrido E2E del Hito 2.
- `tests/perf/bench_enemies.gd` — benchmark (no es una prueba pass/fail).
- Las pruebas pueden ser corrutinas (`await tree.process_frame`): el runner las espera.

## Matriz de casos obligatorios

| # | Caso | Prueba | Estado |
|---|---|---|---|
| 1 | Construcción en celda libre | `test_construction::test_build_on_free_cell` | ✅ |
| 2 | Rechazo en celda ocupada | `test_reject_occupied_cell` | ✅ |
| 3 | Rechazo por créditos insuficientes | `test_reject_insufficient_credits` | ✅ |
| 4 | Rechazo si bloquea todas las rutas | `test_reject_build_that_blocks_every_route`, `test_validation_is_per_movement_class` | ✅ |
| 5 | Recursos y mapa intactos tras rechazo | `test_rejected_build_preserves_resources_and_map` | ✅ |
| 6 | Rutas actualizadas al construir | `test_routes_update_after_build` | ✅ |
| 7 | Rutas actualizadas al retirar | `test_routes_update_after_removal_with_refund` | ✅ |
| 8 | Enemigos llegan a la base | `test_enemies::test_reaches_base_and_damages_hq_once`, `test_many_enemies_all_arrive_without_crossing_walls`, `drive_enemies` | ✅ |
| 9 | Destrucción de enemigos | `test_damage_armor_death_and_reward` (vía API; sin torretas aún) | ✅ parcial |
| 10 | Aplicación de daño | `test_damage_armor_death_and_reward` (blindaje genérico; tipos de daño en Hito 3) | ✅ parcial |
| 11 | Fin de oleada | — Hito 4 | ⬜ |
| 12 | Victoria y derrota | Derrota: `test_defeat_when_hq_destroyed_and_simulation_freezes`, `drive_enemies`. Victoria: Hito 4 | ✅ parcial |
| 13 | Reinicio sin estado residual | `test_new_session_has_no_residual_state`, `test_new_session_has_no_enemy_residue`, RESTART en `drive_battle` | ✅ |
| 14 | Datos inválidos no fallan en silencio | `test_level_loader` (8 pruebas, ~25 variantes), `test_catalog` | ✅ |

Además: conversiones de coordenadas, límites, huellas multicelda, reglas por clase de movimiento
(barrera AT, sacos), bloqueo por fase, wallet, smoke de escenas, campos de flujo (`test_flow_field`, 6),
enemigos (`test_enemies`, 14): velocidad por clase, movimiento sin saltos, rutas diferenciadas, cruce de sacos por
tanques, re-ruta en mitad del recorrido, celdas bajo enemigos, no encerrar enemigos, ruta perdida → BLOCKED → reanuda,
30 enemigos mixtos sin pisar celdas bloqueadas; layout del HUD a 1080p (peor caso de alto y ancho).

## Entorno y resultados verificados

### Sesión 1 — 2026-11-07 (contenedor cloud)

**Entorno:** Ubuntu 24.04.5 LTS x86_64, 4 CPU, 15 GB RAM, sin pantalla. Git disponible.
OpenJDK 21 (`JAVA_HOME` definido). **Godot no instalado. Android SDK no instalado** (sin `ANDROID_HOME`,
`sdkmanager` ni `adb`). La descarga del binario portable de Godot 4.7.2 fue denegada por la política de
permisos del entorno, por lo que no se instaló nada.

| Verificación | Resultado |
|---|---|
| `gdparse` (gdtoolkit 4.5.0) sobre los 27 `.gd` | ✅ sin errores de sintaxis |
| `gdlint` con `gdlintrc` del proyecto | ✅ sin problemas |
| Mapa `mission_01.json`: 16 filas × 24 columnas | ✅ comprobado con script |
| Apertura del proyecto en Godot | ⬜ **no ejecutado** |
| Pruebas unitarias en Godot | ⬜ **no ejecutadas** |
| Smoke de escenas / arranque | ⬜ **no ejecutado** |
| Prueba manual táctil / Android | ⬜ **no ejecutada** |

`gdparse` solo valida sintaxis: **no** detecta errores de tipos, nombres de API inexistentes ni fallos de
ejecución. Los valores esperados de las pruebas se calcularon a mano. (Ejecutadas en la sesión 2, ver abajo.)

### Sesión 2 — 2026-11-07 (mismo contenedor, Godot 4.7.2 autorizado)

Godot 4.7.2-stable oficial (`4.7.2.stable.official.ed1daf0bf`), binario portable descargado de GitHub en un
directorio temporal, **SHA-512 verificado** contra `SHA512-SUMS.txt`. Render vía Xvfb + Mesa llvmpipe (OpenGL 4.5).

| Verificación | Comando | Resultado |
|---|---|---|
| Importación | `--headless --import` | ✅ sin errores ni avisos |
| Pruebas | `--headless --script res://tests/run_tests.gd` | ✅ **40/40**, exit 0, sin `SCRIPT ERROR` |
| Arranque menú | `--headless --quit-after 300` | ✅ exit 0, sin errores |
| Arranque batalla | `--headless --quit-after 300 res://scenes/gameplay/battle.tscn` | ✅ exit 0, sin errores |
| Recorrido con render | `tests/visual/drive_battle.gd` | ✅ **14/14** comprobaciones, exit 0 |
| Táctil en dispositivo Android | — | ⬜ no ejecutado (sin SDK ni dispositivo) |

Salida del recorrido: rechazo del 7º saco con `Blocks every route to the base for: INFANTRY, WHEELED.`;
ruta de infantería oeste 23 → 25 celdas tras los muros; reembolso de saco +7.
Único ruido en el log: ALSA sin tarjeta de sonido (propio del contenedor; Godot usa driver de audio dummy).

**Bugs encontrados y corregidos en esta sesión** (ninguno detectable sin ejecutar el motor):

1. Las pruebas de humo fallaban (38/40): en `SceneTree._initialize()` la raíz aún no está en el árbol y los
   nodos añadidos no reciben `_ready()`. El runner ahora ejecuta con `call_deferred`.
2. **HUD invisible/inutilizable:** `set_anchors_preset()` conserva el rectángulo actual (0×0 al crear por código);
   el panel de construcción quedaba en x = −400, fuera de pantalla, por lo que no se podía seleccionar ninguna
   estructura. Corregido con `set_anchors_and_offsets_preset()` y cubierto por una prueba de regresión
   (comprobado que falla con el código antiguo).
3. Leyenda de rutas más ancha que el panel → panel desbordado a la derecha. Leyenda en filas y
   `grow_horizontal = BEGIN` en el panel.

Capturas: `docs/screenshots/` (menú, rechazo explicado, laberinto con rutas por clase).

### Sesión 3 — 2026-11-07 (Hito 2, Godot 4.7.2, mismo contenedor)

**Auditoría de arquitectura** (hallazgos reales, por gravedad):

| Id | Gravedad | Hallazgo | Acción |
|---|---|---|---|
| C1 | Crítico | Construir solo en BUILD + enemigos solo en COMBAT ⇒ los enemigos nunca podrían reaccionar a cambios; la validación solo miraba spawns (se podría construir sobre/encerrar enemigos) | Corregido: D-012 + `OCCUPIED_BY_UNIT` + requisitos de ruta por enemigo |
| C2 | Crítico | Navegación solo punto a punto (A*): una búsqueda por enemigo | Corregido: campos de flujo compartidos (D-011) |
| H1 | Alto | Doble fuente de verdad: `NavGrid` solo se sincronizaba si alguien llamaba `refresh_cells`. **Demostrado**: tras `grid.add_placement` directo, el grid bloqueaba (4,2) y la navegación la daba por transitable | Corregido: `NavGrid` escucha `GridModel`; prueba `test_nav_follows_direct_grid_mutations` |
| H2 | Alto | `base_hp` sin señal: el HUD no podía reflejar daño | Corregido: `base_hp_changed` |
| H3 | Alto | Ruta dibujada (A*) podía diferir de la ruta real en empates | Corregido: ambas salen del mismo campo |
| M1 | Medio | `GridModel.add_placement` valida solo con `assert` (se elimina en release) | Aceptado: `ConstructionService` es la puerta; documentado |
| M2 | Medio | La meta se pasaba por 3 sitios | Corregido: la posee `NavGrid` |
| — | — | Dependencias circulares | Ninguna encontrada |
| — | — | Señales | Sin señales por enemigo y fotograma; conexiones a métodos (no lambdas que capturen sesiones) en código de juego |

**Resultados**

| Verificación | Resultado |
|---|---|
| Línea base antes de tocar nada | 40/40 |
| `run_tests.gd` | ✅ **60/60**, exit 0, sin `SCRIPT ERROR` ni fugas |
| `drive_battle.gd` (Hito 1, regresión) | ✅ 14/14 |
| `drive_enemies.gd` (Hito 2) | ✅ 15/15 — asalto, 11 muros en combate, rechazo "Enemy units in the way.", pellizco a 2,20× sin construir nada, toque con zoom en la celda exacta (9,9), HQ 20→3, vuelta a BUILD, 0 vistas residuales, pantalla de derrota |
| Arranque menú / batalla | ✅ sin errores |
| Fugas | ✅ ninguna en juego (asalto + reinicio: 0 enemigos residuales, sin "resources still in use") |
| `gdlint` | ✅ |

**Pruebas de mutación** (se rompe el código a propósito; las pruebas deben fallar): ignorar enemigos en la validación
→ 1 fallo; enemigos que no detectan la base → 6 fallos; `NavGrid` sin escuchar al grid → 11 fallos. Código restaurado.

**Rendimiento — lógica headless** (CPU Intel Xeon 2,3 GHz, 4 hilos; 600 ticks a 60 Hz; laberinto de 2 muros largos;
10 cambios de laberinto por pasada; 2 pasadas, se muestra el rango):

| Enemigos | Tick medio | Tick máx | Recálculo campos (3 clases) | Cambio de laberinto completo | Validación de preview | Memoria estática |
|---|---|---|---|---|---|---|
| 10 | 10–14 µs | 53–85 µs | 0,32–0,44 ms | 0,54–0,74 ms | 0,32–0,42 ms | +22 KiB |
| 25 | 23–26 µs | 70–88 µs | 0,33 ms | 0,55–0,59 ms | 0,33–0,36 ms | +36 KiB |
| 50 | 46–57 µs | 120–265 µs | 0,33–0,37 ms | 0,57–0,67 ms | 0,35–0,41 ms | +73 KiB |
| 100 | 83–100 µs | 183–301 µs | 0,33–0,37 ms | 0,59–0,73 ms | 0,36–0,40 ms | +148 KiB |

**Rendimiento — escena completa con render** (Xvfb + Mesa **llvmpipe: rasterizado por software en CPU**,
1920×1080; 5 s por población; obstáculo alternado cada 30 frames):

| Enemigos | FPS | Frame medio | Frame peor | Nuestro CPU/frame (sim + sync vistas) | Nodos |
|---|---|---|---|---|---|
| 0 | 53–56 | 17,8–19,0 ms | 26–27 ms | 0,01 ms | 45 |
| 10 | 51–53 | 18,8–19,6 ms | 25–28 ms | 0,08 ms | 55 |
| 25 | 48 | 20,8–21,1 ms | 27–29 ms | 0,14 ms | 70 |
| 50 | 43–44 | 22,8–23,5 ms | 34–35 ms | 0,22 ms | 95 |
| 100 | 34–37 | 27,1–29,1 ms | 41–48 ms | 0,39 ms | 145 |

Interpretación honesta: nuestro código cuesta < 0,4 ms/frame con 100 enemigos (≈ 2,4 % de 16,6 ms) y escala
linealmente. El resto del tiempo de frame es el rasterizador **por software** de este contenedor (la línea base
sin enemigos ya está en ~18 ms y parece limitada a ~60 Hz por Xvfb). **No hay datos de GPU móvil**: los FPS de esta
tabla no predicen el rendimiento en Android. Memoria del proceso: ~35 MiB estáticos, sin crecimiento durante la
medición. No medido: memoria de vídeo, consumo de batería, temperatura.

**Bugs encontrados al ejecutar en esta sesión y corregidos:** leyenda de rutas cortada abajo (el panel no cabía en
1080 px con el texto más largo) y después 30 px más ancha que el panel — ambos con prueba de regresión que falla con
el código defectuoso (1030 > 1004 px; 430 > 400 px); benchmark que no alternaba obstáculos (retirar en combate está
prohibido por regla) y con un ciclo de referencias propio (lambda capturando la sesión); columna `TIME_PROCESS`
descartada porque no mide lo que su nombre sugiere en este entorno.

Capturas: `docs/screenshots/` (`enemies_assault.png`, `rerouted_during_combat.png`, `zoomed_in.png`, `defeat.png`).

