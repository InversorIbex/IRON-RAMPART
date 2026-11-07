# Roadmap

Leyenda: ✅ hecho y verificado · 🧪 implementado, pendiente de ejecutar en Godot · ⬜ pendiente

## Hito 0 — Preparación 🧪

- ✅ Inspección del entorno (ver TESTING.md §Entorno)
- ✅ Elección de versión (Godot 4.7.2) y renderizador (D-001, D-002)
- 🧪 Proyecto Godot: `project.godot`, 1920×1080 lógico, landscape, GL Compatibility, back de Android
- ✅ Repositorio Git, `.gitignore`, `.gitattributes`, `.editorconfig`, `gdlintrc`
- ✅ Documentación inicial
- 🧪 Menú principal + escena de batalla
- ⬜ **Verificación de arranque en Godot** ← bloqueante para cerrar el hito

Criterio: el proyecto se abre sin errores y se ejecuta una escena básica.

## Hito 1 — Grid y construcción 🧪

- 🧪 Mapa de 24×16 desde JSON con validación
- 🧪 Cuadrícula, ocupación, huellas multicelda
- 🧪 Construcción con previsualización verde/roja y motivo
- 🧪 Validación de rutas por spawn y por clase de movimiento
- 🧪 Retirada con confirmación en dos toques y reembolso
- 🧪 Rutas visibles por clase, recalculadas solo al cambiar la topología
- 🧪 40 pruebas (casos 1–7, 13 parcial, 14 + reglas por clase, wallet, smoke de escenas)
- ⬜ Ejecutar pruebas en Godot y prueba manual del flujo táctil

Criterio: el jugador puede construir obstáculos y modificar caminos sin bloquear ilegalmente la base.

## Hito 2 — Enemigos y navegación ⬜ (no empezar hasta cerrar Hito 1 en motor)

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
| R-2 | Código no ejecutado aún en Godot | Primera tarea de la próxima sesión: importar, pruebas, smoke manual |
| R-3 | Enemigos atrapados si se permite construir en combate | Hoy se prohíbe; diseñar regla en Hito 2 |
| R-4 | `.json` no incluidos en el export | Filtro `*.json` en el preset (D-005) |
| R-5 | Rendimiento con muchas unidades | Medir en Hito 2; plan B campo de flujo (D-004) |

## Tareas pendientes inmediatas

1. Instalar Godot 4.7.2 y ejecutar `--import`, pruebas y smoke (TESTING.md).
2. Corregir lo que aparezca y marcar Hito 0/1 como ✅ con la salida real.
3. Prueba manual: construir un laberinto completo en la misión 1, intentar cerrar ambos spawns, probar retirada.
4. Revisar en el editor el aspecto del HUD a 16:9 y 20:9.
