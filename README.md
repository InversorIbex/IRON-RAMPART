# IRON RAMPART

> **BUILD YOUR DEFENSE. SURVIVE THE ASSAULT.**

Military Maze Tower Defense para Android (2D cenital, horizontal, offline, single-player).
El jugador no defiende rutas fijas: **construye el laberinto** que siguen los enemigos.

**Estado:** Hitos 0–2 completados y verificados en escritorio con Godot 4.7.2: construcción de laberintos con
validación de rutas, y tres tipos de enemigo con navegación compartida que reaccionan al laberinto en pleno combate.
60/60 pruebas, recorridos de juego con render 14/14 y 15/15, benchmark hasta 100 enemigos. Falta probar en un
dispositivo Android. Aún no hay torretas (Hito 3). Gráficos: placeholders. Detalle en [docs/TESTING.md](docs/TESTING.md).

![Construcción rechazada con motivo](docs/screenshots/build_rejected.png)

## Requisitos

| Herramienta | Versión | Para qué |
|---|---|---|
| Godot Engine (estándar, no .NET) | **4.7.2-stable** (mínimo 4.5) | Editor, ejecución, pruebas headless |
| Git | cualquiera reciente | Control de versiones |
| JDK | 17 (recomendado por Godot) | Exportar a Android |
| Android SDK | ver [docs/DECISIONS.md](docs/DECISIONS.md#d-007) | Exportar APK/AAB |
| Export templates de Godot | misma versión exacta que el editor | Exportar |

No hace falta Mac: Android se exporta desde Windows o Linux. Mac solo sería necesario para iOS.

## Instalación

1. Descarga Godot 4.7.2 estándar desde <https://godotengine.org/download/archive/4.7.2-stable/>
   (es un ejecutable portable, no requiere instalador).
2. Clona el repositorio.
3. Primera apertura: abre el editor y usa *Import* sobre `project.godot`, o desde terminal:

```bash
godot --headless --path . --import      # genera .godot/ y registra las clases class_name
```

## Ejecutar

```bash
godot --path .                          # juego (menú principal)
godot --path . res://scenes/gameplay/battle.tscn   # directamente a la misión de prueba
godot -e --path .                       # editor
```

Controles (ratón equivale a toque):

- Selecciona una estructura en el panel derecho.
- Pulsa/arrastra sobre el mapa: la previsualización es **verde** (válida) o **roja** (con el motivo en el panel).
- Suelta para construir. Soltar fuera del mapa cancela.
- `REMOVE`: primer toque selecciona, segundo toque confirma (muestra el reembolso antes).
- Clic derecho / `Esc` / botón Atrás de Android: cancelar herramienta.
- Cámara: pellizco o rueda = zoom; dos dedos, botón central o arrastrar sin herramienta = desplazar.
- `TEST ASSAULT` (depuración): lanza una columna de 10 enemigos para ver el movimiento y la reacción al laberinto.
- Las líneas de colores muestran la ruta actual de cada clase de movimiento
  (arena = infantería, oro = ruedas, rojo = orugas).

## Pruebas

```bash
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Código de salida 0 = todo pasa. Detalles en [docs/TESTING.md](docs/TESTING.md).

## Documentación

| Documento | Contenido |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Instrucciones permanentes para sesiones de desarrollo con Claude Code |
| [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md) | Diseño: mecánicas, estructuras, enemigos, economía, formato de niveles |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Sistemas, escenas, datos, señales |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Decisiones técnicas y motivos |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Hitos, criterios de aceptación, tareas pendientes |
| [docs/ART_DIRECTION.md](docs/ART_DIRECTION.md) | Paleta, escalas, pipeline de arte |
| [docs/TESTING.md](docs/TESTING.md) | Estrategia de pruebas y resultados verificados |
