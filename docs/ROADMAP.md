# Roadmap

Leyenda: ✅ hecho y verificado · 🧪 implementado, pendiente de ejecutar en Godot · ⬜ pendiente

## Hito 0 — Preparación ✅

- ✅ Inspección del entorno (ver TESTING.md §Entorno)
- ✅ Elección de versión (Godot 4.7.2) y renderizador (D-001, D-002)
- ✅ Proyecto Godot: `project.godot`, 1920×1080 lógico, landscape, GL Compatibility, back de Android
- ✅ Repositorio Git, `.gitignore`, `.gitattributes`, `.editorconfig`, `gdlintrc`
- ✅ Documentación inicial
- ✅ Menú principal + escena de batalla
- ✅ Verificación de arranque en Godot 4.7.2 (TESTING.md, sesión 2)

Criterio: el proyecto se abre sin errores y se ejecuta una escena básica.

## Hito 1 — Grid y construcción ✅ (escritorio; táctil en dispositivo pendiente → Hito 5)

- ✅ Mapa de 24×16 desde JSON con validación
- ✅ Cuadrícula, ocupación, huellas multicelda
- ✅ Construcción con previsualización verde/roja y motivo
- ✅ Validación de rutas por spawn y por clase de movimiento
- ✅ Retirada con confirmación en dos toques y reembolso
- ✅ Rutas visibles por clase, recalculadas solo al cambiar la topología
- ✅ 40 pruebas (casos 1–7, 13 parcial, 14 + reglas por clase, wallet, smoke de escenas)
- ✅ Pruebas en Godot (40/40) y recorrido con render e input simulado (14/14)
- ⬜ Prueba con dedo real en dispositivo Android (Hito 5, riesgo R-1)

Criterio: el jugador puede construir obstáculos y modificar caminos sin bloquear ilegalmente la base.

## Hito 2 — Enemigos y navegación ✅ (escritorio; dispositivo pendiente → Hito 5)

- ✅ Auditoría de arquitectura (ARCHITECTURE.md / TESTING.md sesión 3); críticos y altos corregidos
- ✅ `EnemyData` + 3 tipos en datos; `EnemyCatalog`
- ✅ `Enemy` + `EnemyRoster`: spawn, movimiento interpolado, re-ruta en la siguiente celda, llegada, daño al HQ, muerte, recompensa
- ✅ Navegación compartida por campos de flujo (sin A* por enemigo, sin recálculo por frame)
- ✅ Construir en combate sin pisar ni encerrar enemigos (D-012, **pendiente de confirmación de diseño**)
- ✅ Vista reutilizable `EnemyView` (escena) + `EnemyLayer`; siluetas y animaciones provisionales
- ✅ Derrota (HQ a 0) con pantalla; reinicio limpio
- ✅ Cámara: pellizco, pan, rueda; cancelación por multitáctil (D-014)
- ✅ Benchmark 10/25/50/100 enemigos (lógica y render) — TESTING.md
- ✅ 60 pruebas unitarias/smoke + recorridos visuales 14/14 y 15/15
- ⬜ Rendimiento y gestos en dispositivo Android real (Hito 5)

Criterio: los enemigos recorren correctamente el laberinto construido por el jugador. **Cumplido en escritorio.**

## Hito 3 — Torretas y combate ✅ (escritorio; dispositivo pendiente → Hito 5)

- ✅ Auditoría de integración (TESTING.md sesión 4); bug "disparo tras la derrota" corregido
- ✅ Construcción en combate confirmada + recargo 25 % configurable, visible en HUD y fantasma (D-015)
- ✅ Modelo de daño tipo × blindaje con una sola puerta de daño (D-016)
- ✅ HMG, lanzamisiles y AA por datos; giro, cadencia, alcance, prioridades, capas GROUND/AIR
- ✅ Proyectiles deterministas guiados; impacto único; objetivos perdidos; daño de área con caída
- ✅ Recompensas, barras de vida, efectos de disparo/impacto/explosión/destrucción, sacudida de cámara
- ✅ Contraste de enemigos corregido
- ✅ Consultar una torreta colocada (toque sin herramienta: alcance + estadísticas)
- ✅ 96 pruebas (36 nuevas) + 3 recorridos visuales 49/49 + benchmark de combate
- ⬜ AA contra unidades aéreas reales (no existen hasta el mundo 3)
- ⬜ Mejoras de torretas y cambio de prioridad en partida
- ⬜ Rendimiento y "sensación" en dispositivo Android real (Hito 5)

Criterio: el jugador puede destruir enemigos colocando defensas estratégicamente. **Cumplido en escritorio**
(partida simulada: 10/10 enemigos destruidos con el HQ intacto; sin defensas el HQ pierde 17).

## Hito 4 — Oleadas y economía ⬜

`WaveData` + `WaveManager`, 5 oleadas, fases BUILD↔COMBAT, recompensas, victoria/derrota.
Herramienta de balance (tabla/CSV de parámetros). Pruebas: casos 11, 12, 13 completo.

## Hito 5 — Experiencia móvil ⬜

Exportación Android (APK debug → dispositivo real), escalado/safe areas en dispositivo, UI a escenas `.tscn`,
ajustes + persistencia (`SaveService` con `version`), sonidos básicos, perfilado.

## Hito 6 — Validación de jugabilidad ⬜

Sesiones de prueba, ajuste de dificultad/economía, claridad visual, lista de mejoras priorizada.

## Riesgos

| Id | Riesgo | Mitigación |
|---|---|---|
| R-1 | **Precisión táctil**: celda ≈ 3,9 mm a zoom 1 en un móvil de 6,5" | Zoom 1×–3× + pan implementados (≈ 8,6 mm a 2,2×). Validar en dispositivo; opcional: cursor desplazado / confirmación |
| R-2 | ~~Código no ejecutado en Godot~~ | Resuelto en sesión 2 |
| R-3 | ~~Enemigos atrapados al construir en combate~~ | Resuelto: validación incluye enemigos vivos + estado BLOCKED defensivo |
| R-4 | `.json` no incluidos en el export | Filtro `*.json` en el preset (D-005) |
| R-5 | Rendimiento con muchas unidades | Lógica medida: 0,4 ms/frame con 100. Render medido solo con rasterizador software: medir en GPU móvil (Hito 5) |
| R-6 | ~~Construir en combate (D-012)~~ | Confirmado por el usuario con recargo 25 % (D-015) |
| R-7 | Equilibrio: la columna de prueba muere entera con 4 torretas (presupuesto de demo 900 CR) | Hito 4/6: oleadas reales y economía con presupuesto 300 |

## Tareas pendientes inmediatas

1. Hito 4 (cuando se pida): `WaveData`/`WaveManager`, 5 oleadas, victoria, sustituir `TestAssault`.
2. Hito 5 (adelantable): APK de depuración para medir FPS real y probar gestos y legibilidad en un teléfono.
3. CI (GitHub Actions) con Godot 4.7.2 headless: `run_tests.gd` + lint.
4. Cosmético: franja del menú; etiqueta "IN" tapada por rutas.
