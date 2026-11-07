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

## Hito 2 — Enemigos y navegación ⬜ ← siguiente

- Datos `EnemyData` (Resource): vida, velocidad, clase de movimiento, blindaje, daño a base, recompensa
- Spawner de prueba; enemigos con movimiento interpolado entre centros de celda
- Re-path en `topology_changed` desde la siguiente celda (sin teletransportes)
- Llegada a la base → daño → derrota
- Pruebas: casos 8 y 12 (derrota)
- Medición: N enemigos simultáneos vs tiempo de frame (objetivo 150 en gama media a 60 FPS)

## Hito 3 — Torretas y combate ⬜

`TurretData`, adquisición de objetivos (primero/más avanzado al inicio), proyectiles deterministas
(sin física), daño directo/área, efectos básicos. Pruebas: casos 9 y 10.

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
| R-1 | **Precisión táctil**: 16 filas en un móvil de 6,5" ⇒ celda ≈ 4 mm, menor que un dedo | Gesto "arrastrar y soltar" (implementado); evaluar en dispositivo: zoom/pan de cámara, fantasma desplazado sobre el dedo, o botón de confirmar |
| R-2 | ~~Código no ejecutado en Godot~~ | Resuelto en sesión 2 |
| R-3 | Enemigos atrapados si se permite construir en combate | Hoy se prohíbe; diseñar regla en Hito 2 |
| R-4 | `.json` no incluidos en el export | Filtro `*.json` en el preset (D-005) |
| R-5 | Rendimiento con muchas unidades | Medir en Hito 2; plan B campo de flujo (D-004) |

## Tareas pendientes inmediatas

1. Revisión humana del Hito 1 en el editor (jugar la misión 1 con ratón): ¿se entiende la regla, se leen las rutas?
2. Hito 2: `EnemyData`, spawner de prueba, movimiento interpolado, re-path en `topology_changed`, daño a la base.
3. Añadir CI (GitHub Actions) que ejecute `run_tests.gd` con Godot 4.7.2 headless.
4. Cosmético: centrar la franja del menú bajo el título; la etiqueta "IN" del spawn queda tapada por las rutas.
