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

## D-004 — Navegación: AStarGrid2D, una capa por clase de movimiento

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

## D-007 — Exportación Android

- Requisitos (según la documentación de Godot 4.x "Exporting for Android"; **verificar contra la página de la
  versión exacta** antes de instalar): JDK 17, Android SDK command-line tools, platform-tools, build-tools y
  plataforma de la API que pida esa versión de Godot (35 en 4.5), y para AAB/plugins *Gradle build* con NDK/CMake.
- **APK de depuración:** basta con export templates + SDK + JDK + keystore de depuración (Godot puede generarlo).
- **AAB (Google Play):** requiere "Use Gradle Build", plantilla de build Android instalada en el proyecto
  (`android/`, ignorada en git) y keystore de release (nunca en el repositorio).
- No se ha instalado nada de esto en el entorno de desarrollo inicial (ver TESTING.md).

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
