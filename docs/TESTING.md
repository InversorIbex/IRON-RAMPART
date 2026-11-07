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

Análisis estático (opcional, no requiere Godot): `pip install "gdtoolkit==4.*"` y luego
`gdparse <archivos>` (sintaxis) y `gdlint <archivos>` (estilo, usa `gdlintrc`).

## Estructura

- `tests/run_tests.gd` — runner (`extends SceneTree`). Lista explícita de suites.
- `tests/framework/test_case.gd` — base: `before_each`, `after_each`, `assert_*`.
- `tests/unit/test_helpers.gd` — niveles ASCII de prueba y estructuras sintéticas.
- `tests/unit/test_*.gd` — suites.

## Matriz de casos obligatorios

| # | Caso | Prueba | Estado |
|---|---|---|---|
| 1 | Construcción en celda libre | `test_construction::test_build_on_free_cell` | 🧪 |
| 2 | Rechazo en celda ocupada | `test_reject_occupied_cell` | 🧪 |
| 3 | Rechazo por créditos insuficientes | `test_reject_insufficient_credits` | 🧪 |
| 4 | Rechazo si bloquea todas las rutas | `test_reject_build_that_blocks_every_route`, `test_validation_is_per_movement_class` | 🧪 |
| 5 | Recursos y mapa intactos tras rechazo | `test_rejected_build_preserves_resources_and_map` | 🧪 |
| 6 | Rutas actualizadas al construir | `test_routes_update_after_build` | 🧪 |
| 7 | Rutas actualizadas al retirar | `test_routes_update_after_removal_with_refund` | 🧪 |
| 8 | Enemigos llegan a la base | — Hito 2 | ⬜ |
| 9 | Destrucción de enemigos | — Hito 3 | ⬜ |
| 10 | Aplicación de daño | — Hito 3 | ⬜ |
| 11 | Fin de oleada | — Hito 4 | ⬜ |
| 12 | Victoria y derrota | — Hito 2/4 | ⬜ |
| 13 | Reinicio sin estado residual | `test_new_session_has_no_residual_state` (parte de construcción) | 🧪 parcial |
| 14 | Datos inválidos no fallan en silencio | `test_level_loader` (8 pruebas, ~25 variantes), `test_catalog` | 🧪 |

Además: conversiones de coordenadas, límites, huellas multicelda, reglas por clase de movimiento
(barrera AT, sacos), bloqueo por fase, wallet, smoke de escenas.

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
ejecución. Los valores esperados de las pruebas se calcularon a mano. Hasta ejecutarlas en Godot, el estado es 🧪.
