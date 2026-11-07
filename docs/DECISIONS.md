# Decisiones técnicas

Formato: contexto → decisión → motivo → consecuencias. Las decisiones nuevas se añaden al final.

## D-001 — Godot 4.7.2 estable, GDScript

- **Decisión:** Godot 4.7.2-stable (última estable publicada a 2026-11-07; 4.7.3 y 4.8 no existen aún).
  `config/features` declara 4.7. El código evita APIs posteriores a 4.5 para no atarse a la última versión.
- **Motivo:** el brief lo prefiere; GDScript es suficiente para un TD 2D; build de Android integrado.
- **Consecuencia:** todo el equipo debe usar exactamente la misma versión de editor y export templates.

## D-002 — Renderizador GL Compatibility

- **Decisión:** `gl_compatibility` en escritorio y móvil.
- **Motivo:** juego 2D sin iluminación 3D; OpenGL ES 3.0 tiene la mayor cobertura en Android de gama media
  y menor coste de arranque que Vulkan (renderizador *Mobile*). Godot lo recomienda para 2D en móvil.
- **Revisar si:** necesitamos efectos 2D que solo funcionen bien en Vulkan (poco probable).

## D-003 — Resolución lógica 1920×1080, stretch `canvas_items` + aspect `expand`

- **Decisión:** viewport lógico 1920×1080; `canvas_items` (UI y texto nítidos a la resolución nativa);
  `expand` para usar todo el ancho en pantallas 19.5:9/20:9 sin bandas negras.
- **Coste:** en un móvil 1440p se renderiza a 1440p. Alternativa medible si el rendimiento lo exige:
  stretch mode `viewport` (renderiza a 1080p y escala) o bajar a 1600×900 lógicos. Se decidirá con datos en el Hito 5.
- **Mapa:** se escala para encajar en el área libre que deja el HUD (`Battle._layout`). No hay cámara móvil todavía.
- **Orientación:** `sensor_landscape` (ambas horizontales).

## D-004 — Navegación: AStarGrid2D, una capa por clase de movimiento — **sustituida por D-011**

- **Decisión:** `NavGrid` mantiene un `AStarGrid2D` por clase de movimiento (infantería, ruedas, orugas),
  solo movimiento ortogonal, heurística Manhattan.
- **Motivo:** el mapa es una cuadrícula pura; `AStarGrid2D` es nativo (C++), no requiere construir grafos
  a mano como `AStar2D`, y `NavigationServer2D`/`NavigationRegion2D` están pensados para navmesh de
  geometría libre: rebakes caros y difíciles de validar exactamente por celdas.
- **Por capas:** las estructuras bloquean clases distintas (D-006). Tres grids de 24×16 = 1152 nodos: coste despreciable.
- **Sin diagonales:** comportamiento clásico de maze TD, sin atravesar esquinas de muros.
- **Validación "¿bloquea?":** se marca temporalmente la huella como sólida, se consulta un camino por spawn y clase,
  y se restaura el estado previo. Sin copias del grid. Coste: (spawns × clases) A* por evaluación.
- **Recalcular:** solo cuando cambia la topología (`NavGrid.topology_changed` + `version`), nunca por frame.
- **Plan B (Hito 2) si hay muchos enemigos:** campo de distancias (BFS desde la base) por clase, recalculado
  por cambio de topología: O(celdas) una vez y O(1) por enemigo. Se adoptará solo si las mediciones lo justifican.

## D-005 — Niveles en JSON (ASCII), estructuras en `.tres`

- **Niveles:** JSON con `layout` en texto ASCII (`.` `#` `~` `S` `B`). Legibles en un diff, fáciles de
  escribir para 40 misiones y validables con mensajes precisos (`LevelLoader`).
- **Estructuras/unidades:** `Resource` (`StructureData`) editables en el inspector con tipos y rangos.
- **Registro explícito** (`StructureCatalog.PATHS`) en vez de listar carpetas: en builds exportados los
  recursos pueden convertirse/remapearse y `DirAccess` no es fiable.
- **Exportación:** los `.json` no son recursos importados; el preset de exportación debe incluir el filtro
  `*.json` en *Resources → Filters to export non-resource files*. (Pendiente de verificar en el Hito 5.)

## D-006 — Tres barreras con roles distintos (bloqueo por clase de movimiento)

| Estructura | Bloquea | Deja pasar |
|---|---|---|
| Sandbags | infantería, ruedas | orugas (los tanques las aplastan) |
| Concrete Wall | todo | — |
| Anti-Tank Barrier | ruedas, orugas | infantería |

- **Motivo:** evitar "tres muros con distinta vida". Permite separar rutas de infantería y blindados y crear
  laberintos distintos por tipo de enemigo. La regla de validación pasa a ser: **cada spawn debe conservar ruta
  para cada clase presente en la misión**.
- **Pendiente:** que los tanques destruyan los sacos al pasar (Hito 2/3, requiere obstáculos destruibles).

## D-007 — Exportación Android (revisado en el Hito 2)

**Binario usado en desarrollo:** Godot `4.7.2.stable.official.ed1daf0bf`, descargado del release oficial
`github.com/godotengine/godot/releases/tag/4.7.2-stable` (`Godot_v4.7.2-stable_linux.x86_64.zip`), SHA-512
`9aa00f7a…ed54c65` verificado contra el `SHA512-SUMS.txt` del mismo release. Portable, en un directorio temporal
de la sesión; no instalado en el sistema.

**Requisitos Android para 4.7.x**, contrastados en dos fuentes oficiales que **no coinciden del todo**:

| Elemento | Docs `godot-docs` rama 4.7 (`exporting_for_android.rst`) | Código fuente `4.7.2-stable` (`platform/android/java/app/config.gradle`) |
|---|---|---|
| JDK | OpenJDK 17 (superiores soportados) | `javaVersion = 17` |
| Platform / target | Android SDK Platform 35 | `compileSdk 36`, `targetSdk 36`, `minSdk 24` |
| Build-Tools | 35.0.1 | — |
| Platform-Tools | ≥ 35.0.0 | — |
| NDK | r28b (28.1.13356709) | `ndkVersion 29.0.14206865` |
| CMake | 3.10.2.4988404 | — |

Conclusión práctica: para **APK de depuración con plantillas precompiladas** basta JDK 17 + SDK (platform-tools,
build-tools, cmdline-tools) + export templates 4.7.2. Para **Gradle build / AAB** manda el `config.gradle` del motor
(API 36, NDK 29): instalar esas versiones si Gradle las pide. Dispositivos soportados: Android 7.0+ (`minSdk 24`).
El renderizador elegido (GL Compatibility, D-002) usa OpenGL ES 3.0, disponible en prácticamente todo Android ≥ 7.
**Nada de esto se ha probado aún** (sin SDK ni dispositivo en el entorno): Hito 5.

- **AAB (Google Play):** "Use Gradle Build", plantilla Android instalada en `android/` (ignorada en git) y keystore de
  release fuera del repositorio.

## D-008 — Sin autoloads por ahora

- **Decisión:** el estado de una partida vive en `GameSession` (RefCounted), creado por la escena `Battle`.
  Reiniciar = nueva sesión → imposible arrastrar estado residual.
- **Cuándo habrá autoloads:** persistencia (`SaveService`) y ajustes de audio, que sí son globales.

## D-009 — UI construida en código (temporal)

- HUD y menú se construyen en `_ready()` con un `Theme` generado desde la paleta (`UiTheme`).
- **Motivo:** permitir validar su sintaxis sin editor y sin escribir `.tscn` complejos a mano.
- **Cuándo cambiar:** en el pase de UI (Hito 5) se pasan a escenas `.tscn` + `Theme.tres`, manteniendo la API de señales.

## D-010 — Pruebas sin dependencias externas

- Runner propio (`tests/run_tests.gd`, ~50 líneas) ejecutado con `godot --headless --script`.
- **Motivo:** GUT/gdUnit4 son buenas opciones pero son dependencias externas importantes (requieren autorización
  según el brief). El runner cubre lo necesario para la lógica actual; se puede migrar si crece.
- Convención: idioma de código, comentarios y UI en inglés; documentación en español.

## D-011 — Campos de flujo en lugar de A* (Hito 2)

- **Contexto:** con enemigos, `AStarGrid2D` obligaba a una búsqueda por enemigo (o por grupo) en cada cambio, la ruta
  dibujada (A*) podía diferir de la seguida por los enemigos en empates, y validar "no encerrar a nadie" requería
  N búsquedas por previsualización.
- **Decisión:** `NavGrid` mantiene, por clase de movimiento, un BFS desde la meta (`PackedInt32Array`). Se recalcula
  solo al cambiar la topología. Enemigos, previsualización de rutas y validación leen esos campos.
- **Coste medido (24×16, 3 clases, CPU Xeon 2,3 GHz):** recálculo ~0,33 ms; validación de una construcción con 100
  enemigos ~0,35–0,40 ms; consulta por enemigo O(1).
- **API:** se mantienen `is_walkable`, `find_broken_routes`, `topology_changed`, `version`; `find_path(bit, from, to)`
  pasa a `path_to_goal(bit, from)` (todas las rutas del juego van a la meta); `NavGrid` recibe la meta en su constructor.
- **Revisar si:** hay mapas mucho mayores (p. ej. > 100×100) o varias metas: entonces BFS incremental o en C++/GDExtension.

## D-012 — Construir durante el combate: permitido por defecto (configurable) — **confirmada por el usuario (Hito 3), ver D-015**

- **Contexto:** el Hito 2 exige que los enemigos reaccionen a cambios del laberinto. Con construcción solo en fase
  BUILD (decisión previa) y enemigos solo en COMBAT, esa reacción no podría ocurrir nunca en partida.
- **Decisión:** regla de nivel `allow_build_during_combat` (por defecto `true`; misión 1 `true`). Validación adicional:
  no construir bajo enemigos (`OCCUPIED_BY_UNIT`) ni dejar a ningún enemigo vivo sin ruta ("Would trap enemies…").
  Retirar en combate sigue desactivado (`allow_remove_during_combat: false`).
- **Confirmada** al inicio del Hito 3 con recargo de combate (D-015).

## D-013 — Enemigos: modelo puro + vista por escena, sin físicas

- `Enemy` (RefCounted) + `EnemyRoster` (RefCounted) contienen toda la lógica; `EnemyView` (escena reutilizable) solo
  dibuja. `EnemyLayer` sincroniza todas las vistas en un bucle en vez de 100 `_process`.
- Sin `CharacterBody2D` ni colisiones: el movimiento es determinista sobre la cuadrícula (TD clásico), testeable sin
  escena y barato (0,2 ms de simulación con 100 enemigos).
- Sin pooling de vistas por ahora: crear/liberar 100 nodos no aparece en las mediciones. Revisar con oleadas grandes.
- Blindaje = fracción de daño absorbida (genérica). Los tipos de daño (balas vs explosivo) llegan con las torretas (Hito 3).

## D-014 — Cámara táctil: zoom 1×–3× + pan, sin reducir el mapa

- **Problema:** con 16 filas en 1080 px lógicos, una celda mide ~61 px a zoom 1 (≈ 3,9 mm en un móvil de 6,5" con
  1080 px de alto físico), menos que un dedo (≈ 7–9 mm).
- **Opciones evaluadas:** (a) reducir el mapa: perjudica el diseño de laberintos (menos espacio de decisión) — descartado;
  (b) celdas mayores con scroll obligatorio: se pierde la vista global durante el combate; (c) **zoom bajo demanda**
  conservando la vista global a zoom 1 — elegido; (d) cursor desplazado sobre el dedo; (e) confirmación explícita.
- **Implementado:** pellizco (zoom en torno al punto medio) y arrastre con dos dedos; arrastre con un dedo sin herramienta;
  rueda y botón central en escritorio; un segundo dedo **cancela** la construcción en curso. A zoom 2,2 la celda mide
  135 px lógicos (≈ 8,6 mm en el móvil de referencia); máximo 3× ≈ 11,7 mm.
- **Pendiente de validar en dispositivo (Hito 5):** (d) y (e) como opciones de accesibilidad, y doble toque = zoom rápido.

## D-015 — Recargo de construcción en combate (confirmado por el usuario)

- Entre oleadas: coste normal. Durante el combate: `ceil(coste × (1 + combat_build_surcharge))`, regla de nivel,
  por defecto **0,25**, validada en `[0, 5]`. Solo afecta a construcciones nuevas; el reembolso se calcula siempre
  sobre el coste base (el recargo no se recupera).
- **Una sola fuente de precio:** `ConstructionService.price_of()`. La usan el HUD (precio con `*` + nota
  "COMBAT SURCHARGE +25%"), la etiqueta del fantasma ("125 CR (+25)") y `build()`; el `Check` de `evaluate` lleva
  `cost` y `surcharge`, y `build` cobra exactamente ese `cost`. `Placement.paid` registra lo pagado.
- **Atomicidad:** validación y cobro en la misma llamada con el mismo precio; cualquier rechazo (créditos, enemigos
  encima, encerrar enemigos, sellar la base, fase) retorna antes de tocar créditos, grid o navegación.
- **Confirmación de colocación:** previsualización verde/roja con precio y alcance → soltar confirma; soltar fuera
  del mapa o poner un segundo dedo cancela.

## D-016 — Modelo de combate: tipos de daño × clases de blindaje

- Daño final = `amount × MULTIPLIER[tipo][clase de blindaje]` (`scripts/combat/damage.gd`). Sustituye la fracción
  escalar `armor` del Hito 2 por `armor_class` (NONE/LIGHT/HEAVY). `GENERIC` reproduce los valores anteriores
  (1,0 / 0,75 / 0,40), así que no cambió ningún comportamiento previo.
- **Una sola puerta de daño:** `EnemyRoster.damage(enemy, amount, type)` aplica blindaje, mata, emite `enemy_killed`
  una vez y `GameSession` paga la recompensa. Las torretas no tocan vida ni créditos directamente.
- **Proyectiles deterministas, sin físicas:** guiados hacia el objetivo vivo (siempre conectan). Si el objetivo muere
  o llega a la base antes: las balas se pierden sin daño; misiles/flak detonan en la última posición (daño de área).
  `done` + eliminación tras el impacto ⇒ un proyectil no puede dañar dos veces.
- **Área:** objetivo directo 100 %, resto en el radio `splash_falloff` (50 %); víctimas recogidas antes de aplicar
  daño (las muertes modifican la lista del roster).
- **Torretas = estructuras:** `StructureData.turret → TurretData`. Bloquean como un muro (forman parte del laberinto)
  y reutilizan construcción, validación de rutas y navegación sin cambios. `CombatSystem` las descubre escuchando a
  `GridModel` (mismo patrón que `NavGrid`).
- **Capas de objetivo:** `Targeting.GROUND`/`AIR` en enemigos y armas; el AA está configurado solo para `AIR`.
- Tabla en código (no en datos) por ahora: es pequeña, central y está cubierta por pruebas; pasará a recurso si el
  equilibrado del Hito 6 lo pide.

## D-017 — Búsqueda de objetivos limitada a 10 Hz por torreta

- **Medido:** con 100 enemigos y 20 torretas el combate costaba 0,65–0,73 ms/tick, porque las torretas sin objetivo
  (p. ej. AA sin aviones) o alineándose reescaneaban todos los enemigos en cada frame (O(torretas × enemigos)).
- **Decisión:** escaneo como máximo cada 0,1 s por torreta (tiempo de reacción), con fases escalonadas por id para
  repartir picos. El seguimiento y el disparo al objetivo actual siguen siendo por frame.
- **Resultado medido:** 0,13 ms/tick (−80 %), pico 2,8 → 0,46 ms, mismas bajas en 10 s (92). Determinista.

## D-018 — Máquina de estados de misión en `GameSession` (Hito 4)

- **Estados:** `PREPARATION`, `WAVE_ACTIVE`, `WAVE_COMPLETED`, `VICTORY`, `DEFEAT`, `PAUSED`. Tabla `TRANSITIONS`
  explícita; `_transition()` rechaza todo lo demás (devuelve `false` y no cambia nada). `VICTORY`/`DEFEAT` son finales.
- **Por qué en `GameSession` y no un autoload/nodo:** el estado de misión es estado de partida; vive y muere con la
  sesión (reinicio = sesión nueva, D-008) y se prueba sin escena. Antes la pausa vivía solo en el `SceneTree` del HUD
  y el paso combate→construcción en el nodo `Battle` (lógica de juego en una escena).
- **Pausa:** `pause()` guarda el estado anterior y `resume()` vuelve exactamente a él. `tick()` no hace nada en
  `PAUSED`; además `Battle` pausa el árbol para congelar tweens/efectos. La sesión es la autoridad.
- **`WAVE_COMPLETED`:** resumen de oleada (bono, banner) con construcción sin recargo; pasa sola a `PREPARATION`
  tras `debrief_seconds` (dato de misión), o directamente a `WAVE_ACTIVE` si el jugador pulsa START WAVE.
  `PREPARATION` no tiene límite de tiempo.
- **Derrota desde cualquier estado activo:** si el HQ llega a 0 la misión se pierde aunque no sea `WAVE_ACTIVE`
  (en juego normal solo ocurre en combate). Al terminar: proyectiles vaciados y nada más se simula.

## D-019 — Oleadas por datos con calendario determinista

- `WaveData` (grupos: enemigo, cantidad, inicio, intervalo, spawn por nombre/índice/`alternate`; modificadores de
  vida/velocidad; recompensa; condición de fin) en el JSON de misión, validado por `LevelLoader`.
- `WaveManager` genera un **calendario** ordenado (tiempo, grupo, unidad) al iniciar la oleada y lo consume con el
  reloj de la oleada: mismo dato ⇒ mismo orden y tiempos. No muta `WaveData` (la misión se puede rejugar).
- Fin de oleada = todo el calendario generado **y** ningún enemigo vivo (muertos o llegados al HQ).
- Modificadores por unidad (`Enemy.max_hp`, `Enemy.speed`); `EnemyData` compartido nunca se modifica.
- Sustituye a `TestAssault` (andamiaje del Hito 2, eliminado).

## D-020 — Economía y puntuación

- Ingresos: presupuesto inicial + recompensa por baja (una vez, en `GameSession._on_enemy_killed`) + bono por oleada
  completada (una vez, en `_complete_wave`). Llegar al HQ no paga nada. Gastos: precio de `price_of()` (recargo en
  combate). Reembolso al retirar: coste base × `refund_ratio`.
- `MissionStats` lleva el libro: bajas por tipo, créditos por bajas/oleadas, gastado, reembolsado, daño al HQ, fugas.
  Una prueba comprueba que el libro cuadra: `créditos = inicial + bajas + bonos − gastado + reembolsado`.
- **Puntuación** (`MissionScore`): `500 × oleadas completadas + 10 × bajas + 150 × HQ restante + 1 × créditos +
  1000 si victoria`. Estrellas: 3 = victoria sin daño, 2 = victoria con ≥ 50 % HQ, 1 = victoria, 0 = derrota.
  Simple y transparente; premia sobre todo proteger el HQ. Se revisará con la campaña.

## D-021 — Equilibrio por simulación con un jugador scripted

- `tests/sim/strategy_bot.gd` juega la misión real (mismas reglas, precios y oleadas) con estrategias A/A2/B/C/D;
  `tests/sim/sim_mission.gd` imprime la comparación; `test_mission_flow` fija como regresión que C y B ganan y D pierde.
- Iteraciones documentadas en TESTING.md (sesión 5). Cambios de datos resultantes: presupuesto 300 → **350**,
  vehículo ligero 140 → **110 HP** y recompensa 12 → **10**, tanque recompensa 40 → **30**, bonos 60/70/90/110,
  oleada 4 con tanques espaciados, oleada 5 con 6 tanques y +25 % de vida.
- **Limitación:** el bot no construye en combate, no retira, no reacciona dentro de la oleada y usa casillas fijas.
  Es una referencia mínima de "jugador competente", no un sustituto de pruebas con personas (Hito 6).

## D-022 — Sonido provisional sintetizado

- No hay recursos de audio: `Sfx` genera señales cortas (PCM 16 bit) para inicio de oleada, aviso de blindados, daño
  al HQ, baja (limitado a 12/s), oleada completada, victoria, derrota y construcción denegada.
- **No verificado de oído:** el contenedor no tiene tarjeta de sonido (driver de audio dummy). Verificado solo que se
  generan y reproducen sin errores. Sustituir por audio diseñado en el pase de arte.

