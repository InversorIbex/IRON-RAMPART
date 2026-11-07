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

Recorrido del Hito 3 (partida simulada: laberinto + torretas, consulta de torreta, asalto, construcción en combate con
recargo, bajas, recompensas, limpieza): `... --script res://tests/visual/drive_combat.gd`.

Benchmark de combate (25/50/100 enemigos × 0/10/20 torretas): `tests/perf/bench_combat.gd` (mismos modos que
`bench_enemies.gd`).

Hito 4: recorrido completo menú → victoria → reinicio → derrota → menú: `tests/visual/drive_mission.gd`.
Benchmark de una partida completa: `tests/perf/bench_mission.gd` (`-- --render` con Xvfb).
Simulación de equilibrio: `godot --headless --path . --script res://tests/sim/sim_mission.gd [-- --maps --verbose]`.
Los drivers tienen un watchdog (600 s reales): si mueren por un error de script salen con código 2.

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
| 9 | Destrucción de enemigos | `test_hmg_destroys_infantry_and_pays_reward`, `test_splash_kills_reward_each_victim_once`, `drive_combat` (10/10) | ✅ |
| 10 | Aplicación de daño | `test_damage_table_specialisation`, `test_roster_damage_uses_type_and_armor`, `test_each_projectile_damages_exactly_once`, `test_splash_hits_each_unit_once_with_falloff` | ✅ |
| 11 | Fin de oleada | `test_waves::test_wave_ends_only_when_all_spawned_and_none_alive`, `test_units_reaching_the_hq_also_resolve_the_wave` | ✅ |
| 12 | Victoria y derrota | `test_game_state::test_victory_after_last_wave`, `test_defeat_stops_waves_and_projectiles`, `test_mission_flow`, `drive_mission` | ✅ |
| 13 | Reinicio sin estado residual | `test_mission_flow::test_restart_after_victory_is_clean` / `_after_defeat_is_clean`, `drive_mission` (weakref: sesión anterior liberada) | ✅ |
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

### Sesión 4 — 2026-11-07 (Hito 3, Godot 4.7.2, mismo contenedor)

Línea base antes de tocar nada: 60/60.

**Auditoría de integración**

| Id | Hallazgo | Acción |
|---|---|---|
| A1 | Blindaje = una fracción escalar: no permite especializar armas | Tabla tipo × clase (D-016); `GENERIC` conserva los valores previos (ninguna prueba anterior cambió de resultado) |
| A2 | `StructureData` ya tenía `Category.TURRET` | Torretas = estructuras con `TurretData`; construcción/rutas/navegación reutilizadas sin cambios |
| A3 | `GridModel` emite altas/bajas | `CombatSystem` las escucha (sin acoplarse a construcción) |
| A4 | El coste se leía de `data.cost` en dos sitios | `price_of()` único; preview y cobro usan el mismo `Check.cost` |
| A5 | No había "progreso hacia la base" | `Targeting.remaining_cells` desde el campo de flujo (ruta real) |
| A6 | Torretas giran cada frame; `GridView` redibuja todo | Nodos `TurretView` aparte |
| B1 | **Bug encontrado por prueba:** en el tick en que caía el HQ, el combate aún se actualizaba y una torreta disparaba tras la derrota | `tick()` comprueba `is_over()` entre enemigos y combate |
| B2 | Regla CLAUDE.md "colores solo desde Palette" incumplida en código nuevo y en `EnemyView` previo | Colores de efectos/materiales movidos a `Palette` |
| B3 | Panel lateral con 6 botones: 1334 px de 1004 (detectado por la prueba de regresión) | Rejilla de 2 columnas agrupada; peor caso verificado |
| B4 | Error de inferencia de tipos en `CombatLayer` (`fx[5]` es Variant) | Tipo explícito; lo detectaron el driver y la prueba de humo |

**Resultados**

| Verificación | Resultado |
|---|---|
| `run_tests.gd` | ✅ **96/96** (60 anteriores + 36 nuevas: `test_combat_construction` 11, `test_combat` 11, `test_combat_projectiles` 14), sin `SCRIPT ERROR` ni fugas |
| `drive_battle.gd` | ✅ 14/14 |
| `drive_enemies.gd` | ✅ 15/15 (con presupuesto de prueba +400 CR por el recargo; la comprobación es de rutas, no de economía) |
| `drive_combat.gd` | ✅ 20/20 — presupuesto de demo 300 + 600 CR; 7 muros + HMG×2 + misiles + AA; HMG a 100 CR en BUILD y **125 CR (+25)** en combate (HUD `125 CR*`, nota de recargo, etiqueta del fantasma); 154 disparos de HMG, 8 misiles, **0 del AA** (sin aéreos); **10/10 bajas, 106 CR de recompensa, HQ 20 → 20**; vuelta a BUILD, 0 proyectiles/vistas residuales, precios de nuevo base |
| Arranque menú / batalla | ✅ sin errores |
| `gdlint` | ✅ |

**Pruebas de mutación** (todas detectadas, código restaurado): proyectiles nunca eliminados → 2 fallos; ignorar
alcance → 1; ignorar capas → 1; cobrar el coste base en vez del precio mostrado → 2; balas que "aciertan" objetivos
muertos → 1; sin caída de daño de área → 2; torretas que disparan tras la derrota → 1.

**Rendimiento — lógica headless** (Xeon 2,3 GHz; 600 ticks; población constante; 2 pasadas, rango):

| Enemigos × torretas | Movimiento | Combate | Simulación total/tick | Proyectiles pico |
|---|---|---|---|---|
| 100 × 0 | 80–83 µs | < 1 µs | 0,08 ms | 0 |
| 25 × 10 | 22–23 µs | 30–31 µs | 0,05 ms | 5 |
| 100 × 10 | 84–86 µs | 70–73 µs | 0,15–0,16 ms | 5 |
| 25 × 20 | 21–22 µs | 50 µs | 0,07 ms | 7 |
| 100 × 20 | 83–84 µs | 127–132 µs | 0,21 ms | 7 |

Antes de D-017 (búsqueda de objetivo cada frame) el combate 100 × 20 costaba 653–727 µs (pico 2,8 ms).

**Rendimiento — escena con render** (Xvfb + llvmpipe, **rasterizado por software**, 1920×1080, 4 s por caso):

| Enemigos × torretas | FPS | Frame medio | Nuestro CPU (sim + vistas + dibujo de efectos) | Efectos pico |
|---|---|---|---|---|
| 25 × 0 | 48 | 20,9 ms | 0,12 ms | 0 |
| 100 × 0 | 39 | 25,8 ms | 0,32 ms | 0 |
| 100 × 10 | 33 | 30,3 ms | 0,83 ms | 117 |
| 25 × 20 | 42 | 23,6 ms | 0,55 ms | 148 |
| 100 × 20 | 32–33 | 30,8 ms | 0,92 ms | 127 |

Interpretación: nuestro código cuesta < 1 ms/frame en el peor caso medido; el resto del frame es el rasterizador por
software del contenedor (línea base ~18–21 ms sin nada). **No hay medición en GPU ni CPU móvil**: no se puede afirmar
60 FPS en Android hasta medir en un dispositivo (Hito 5). No medido: memoria de vídeo, batería, temperatura.

Capturas: `docs/screenshots/` (`defences_ready`, `firefight`, `firefight_zoomed`, `combat_build_surcharge`,
`after_battle` + las de hitos anteriores, regeneradas con los nuevos enemigos).

### Sesión 5 — 2026-11-07 (Hito 4, Godot 4.7.2, mismo contenedor)

Línea base antes de tocar nada: 96/96 (Hito 3 verificado de nuevo, sin huecos críticos).

**Auditoría**

| Id | Hallazgo | Acción |
|---|---|---|
| G1 | Sin máquina de estados: `set_phase()` aceptaba cualquier transición; no existía la victoria | D-018: tabla `TRANSITIONS`, estados finales |
| G2 | Pausa solo en el `SceneTree` del HUD: la lógica no la conocía ni se podía probar | `pause()/resume()` en la sesión, recuerdan el estado previo |
| G3 | `TestAssault` y el paso combate→construcción vivían en el nodo `Battle` | `WaveManager` + estados en `GameSession`; `TestAssault` eliminado |
| G4 | Vida/velocidad leídas del `EnemyData` compartido: imposible modificar por oleada | `Enemy.max_hp/speed` por unidad |
| G5 | Sin estadísticas, puntuación ni datos de misión (oleadas, identidad) | `MissionStats`, `MissionScore`, formato de misión ampliado |
| T1 | **Bug del ejecutor de pruebas:** una suite con error de parseo se saltaba en silencio y el ejecutor devolvía 0 (82/82 en vez de fallar) | `can_instantiate()`: ahora cuenta como `[LOAD FAIL]` y sale con 1 (verificado) |
| T2 | Nueva lógica: en PREPARATION las balas en vuelo se congelaban; DEFEAT solo era posible desde WAVE_ACTIVE | Corregido antes de cerrar (detectado por pruebas existentes) |
| T3 | `drive_enemies` usaba el antiguo panel de derrota: `SCRIPT ERROR` y el driver se colgaba hasta el `timeout` | Referencia corregida + watchdog en los 4 drivers (verificado: error inyectado → salida 2 en 5,4 s) |
| T4 | Aviso "4 ObjectDB instances leaked at exit" en el benchmark con render | Investigado con `--verbose`: `AudioStreamPlaybackWAV`/`AudioStreamWAV` de `Sfx` cuando el proceso termina con un sonido en curso. **Sin fuga en ejecución:** 6 reinicios con sonido → 1750 objetos, 50 recursos, 0 huérfanos constantes. Benchmark vuelve al menú antes de salir. Un intento de arreglo en `Sfx._exit_tree` no tuvo efecto y se revirtió |
| T5 | Valores de datos escritos a mano en pruebas/drivers (créditos 300, vida 140) | Ahora se leen de `LevelData`/`Enemy` |

**Resultados**

| Verificación | Resultado |
|---|---|
| `run_tests.gd` | ✅ **126/126** (96 + 30 nuevas: `test_waves` 9, `test_mission_data` 5, `test_game_state` 11, `test_mission_flow` 5), sin errores ni fugas |
| Mutaciones (6, todas detectadas) | simular en pausa → 2 fallos; fin de oleada sin esperar al calendario → 1; bono pagado dos veces → 4; PREPARATION→VICTORY permitido → 1; recompensa por fugas → 3; reanudar siempre en PREPARATION → 2 |
| `gdlint` | ✅ |

**Simulación de equilibrio** (`sim_mission.gd`, paso fijo 1/60 s, determinista; datos finales):

| Estrategia | Resultado | HQ | Bajas | Ingresos (bajas + bonos) | Gastado | Nota |
|---|---|---|---|---|---|---|
| A: laberinto largo de sacos (~40 celdas) | Derrota en la 5 | 0 | 83 | 1020 | 1070 | Los sacos no desvían tanques: la oleada 5 rompe la defensa |
| A2: mismo laberinto con hormigón | Derrota en la 3 | 0 | 25 | 255 | 530 | Invertir antes en obstáculos caros que en fuego se castiga |
| B: potencia de fuego junto al HQ | **Victoria** | 9/20 | 85 | 1080 | 1020 | |
| C: embudo (sellar el norte) + mixto | **Victoria** | 9/20 | 85 | 1080 | 1060 | Única que no pierde HQ entre las oleadas 3 y 4 |
| D: una HMG y acumular | Derrota en la 3 | 0 | 18 | 220 | 100 | Con 470 CR sin usar |

Por oleada (C): 22 s / 22 s / 36 s / 47 s / 43 s de combate; daño al HQ 0 / 6 / 0 / 0 / 5. La oleada 2 cobra 6 HP a
todas las estrategias (3 ligeros por el norte) y la 5 es la que más exige a las que ganan.
Los créditos finales (370–410) se ganan durante la última oleada, no son un excedente acumulado.

Iteraciones de equilibrio realizadas (todas con la misma simulación): presupuesto 300 → 350; ligeros 140 → 110 HP,
recompensa 12 → 10; tanques recompensa 40 → 30; bonos 60/80/100/120 → 60/70/90/110; oleada 4 con tanques cada
7 s; oleada 5 con 18/9/6 y vida ×1,25. Con los datos iniciales B ganaba sin daño en las oleadas 4–5 y acababa con
469 CR sin gastar.

**Limitaciones de la simulación:** el jugador scripted construye solo entre oleadas, no retira ni reorganiza, no
reacciona dentro de la oleada, usa casillas fijas y lee la información de las dos próximas oleadas. Los resultados
dependen mucho del orden de compra (en las iteraciones, cambiar solo el modelo de compra hizo ganar o perder a B).
Es una referencia, no sustituye a jugadores reales. **Hallazgo de diseño:** en este mapa el laberinto puro no supera
a la potencia de fuego (riesgo R-8).

**Rendimiento — partida completa** (C_balanced; Xeon 2,3 GHz):

| Medida | Headless (paso fijo) | Con render (Xvfb + llvmpipe) |
|---|---|---|
| Resultado | Victoria, HQ 9 (determinista) | Victoria, HQ 9 y 14 en dos ejecuciones (paso variable) |
| Simulación por tick | 14,5–14,8 µs: oleadas 0,7 · movimiento 4,9 · torretas 6,6 · proyectiles 1,3 | 0,07 ms/frame |
| Vistas + dibujo de efectos | — | 0,03 + 0,07 ms/frame |
| Navegación | 15 recálculos en toda la partida, ~0,34 ms cada uno (solo al construir/retirar) | — |
| Frame | — | 23,7–24,7 ms de media (42 FPS), peor 43–84 ms: rasterizado **por software** |
| Picos | 20 enemigos, 5 proyectiles, 6 torretas | 90 nodos |
| Memoria | +139 KiB estáticos durante la partida | 41,4 MiB estáticos |

Cuellos de botella: ninguno en nuestro código para esta misión (< 0,2 ms/frame); el frame lo domina el render del
contenedor. **No medido en Android** (sin dispositivo): FPS, memoria de vídeo, batería, temperatura.

