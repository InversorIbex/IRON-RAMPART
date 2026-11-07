# IRON RAMPART — Game Design Document

Estado: borrador vivo. Los valores numéricos son provisionales hasta las pruebas de equilibrio (Hito 6).
Marcadores: ✅ implementado · 🧪 implementado sin verificar en motor · 📐 diseñado, no implementado.

## 1. Pilares

1. **El jugador diseña el camino.** No hay rutas fijas; cada estructura cambia la ruta enemiga.
2. **Cada construcción es una decisión.** Presupuesto escaso, roles distintos, nada es "más de lo mismo".
3. **Fácil de leer, difícil de dominar.** La ruta actual de cada tipo de enemigo siempre es visible.
4. **Gana la planificación.** El mismo presupuesto bien colocado debe superar al mal colocado por mucho.

## 2. Bucle de juego

Fase de construcción → iniciar oleada → combate (ajustes limitados) → recompensa → fase de construcción …
→ victoria (todas las oleadas) o derrota (vida de la base a 0).

## 3. Cuadrícula y laberintos 🧪

- Mapa de celdas (misión 1: 24×16, celda 64 px lógicos). Dimensiones definidas por el nivel.
- Movimiento enemigo ortogonal (sin diagonales).
- **Regla de oro:** no se puede construir si deja a algún spawn sin ruta a la base **para alguna clase de
  movimiento presente en la misión**. El rechazo explica la clase afectada y marca el spawn en rojo.
- La ruta actual de cada clase se dibuja en el mapa (arena = infantería, oro = ruedas, rojo = orugas).
- Retirada: solo en fase de construcción (configurable por nivel), dos toques, reembolso `floor(coste × refund_ratio)`.
- **Construir en combate** ✅ (D-012, pendiente de tu confirmación): permitido por defecto. No se puede construir
  sobre un enemigo ni dejar a un enemigo vivo sin ruta ("Would trap enemies"). Los enemigos adoptan la nueva ruta al
  llegar a su siguiente celda.

## 4. Clases de movimiento

| Clase | Unidades | Notas |
|---|---|---|
| INFANTRY | Infantry, futuros ingenieros | Cruza barreras antitanque |
| WHEELED | Light Vehicle, futuros transportes | La clase más restringida |
| TRACKED | Heavy Tank | Aplasta sacos terreros |
| (AIR) 📐 | Helicópteros | Ignorará el laberinto; capa de navegación propia o vuelo directo |

## 5. Estructuras defensivas

| Estructura | Coste | Vida | Bloquea | Rol táctico |
|---|---|---|---|---|
| Sandbags | 10 | 60 | Inf + Ruedas | Laberinto barato temprano; inútil contra tanques: obliga a reforzar antes de las oleadas blindadas |
| Concrete Wall | 25 | 400 | Todo | Columna vertebral del laberinto |
| Anti-Tank Barrier | 35 | 300 | Ruedas + Orugas | Separa a la infantería de los blindados: alarga la ruta de vehículos hacia los lanzamisiles mientras la infantería va por el corto hacia las ametralladoras |

📐 Pendiente: los tanques destruyen los sacos que cruzan (cambio de topología en combate);
muros destruibles por unidades específicas (ingenieros, artillería enemiga).

## 6. Torretas 📐 (Hito 3)

| Torreta | Coste | Objetivos | Perfil |
|---|---|---|---|
| Heavy Machine Gun | 100 | Infantería, ruedas | Cadencia alta, daño bajo, alcance medio |
| Anti-Aircraft Defense | 150 | Aire (y ligeros, por decidir) | Cadencia y alcance configurables |
| Missile Launcher | 180 | Blindados | Cadencia lenta, daño alto, proyectil visible, explosión |

Parámetros en datos: coste, vida, daño, alcance, cadencia, velocidad de proyectil, objetivos permitidos,
prioridad (primero / más cercano / más vida / más avanzado), mejoras. Las torretas **también bloquean**
(huella 1×1 o 2×2 por decidir) y por tanto forman parte del laberinto.

## 7. Enemigos ✅ (Hito 2; valores provisionales en `data/enemies/*.tres`)

| Enemigo | Clase | Vida | Velocidad (celdas/s) | Blindaje | Daño a HQ | Recompensa |
|---|---|---|---|---|---|---|
| Infantry | INFANTRY | 60 | 1,5 | 0 % | 1 | 5 |
| Light Vehicle | WHEELED | 140 | 2,4 | 25 % | 2 | 12 |
| Heavy Tank | TRACKED | 600 | 0,8 | 60 % | 5 | 40 |

- Blindaje actual = fracción genérica de daño absorbida. En el Hito 3 se añadirá multiplicador por tipo de daño
  (balas vs explosivo), que es lo que hará que cada torreta tenga su objetivo natural.
- Todos los enemigos de una clase comparten la misma navegación; la ruta dibujada es exactamente la que siguen.
- Sin fuente de daño todavía (torretas: Hito 3). `TEST ASSAULT` (HUD) lanza una columna de depuración de 10 unidades
  (17 de daño al HQ, sobrevivible) para observar el ciclo BUILD → COMBAT → BUILD.

## 8. Economía

- Créditos militares. Misión 1: 300 iniciales (provisional).
- Ingresos 📐: recompensa por baja + bonus de oleada (+ bonus por terminar sin daño a la base, a evaluar).
- Reembolso de retirada: 75 % por defecto, por estructura.
- Objetivo: con el presupuesto inicial no se puede cerrar un laberinto completo y armarlo a la vez.

## 9. Oleadas 📐 (Hito 4)

Cinco oleadas en la misión 1: (1) infantería sola, aprendizaje; (2) infantería por los dos spawns;
(3) primeros vehículos ligeros: más rápidos, castigan laberintos cortos;
(4) primer tanque: los laberintos de sacos dejan de servir; (5) mezcla por ambos spawns con tanques en
cabeza. Presión por **composición, tiempos y entradas**, no solo por vida.

## 10. Formato de niveles

`data/levels/<id>.json`:

```json
{
  "format_version": 1,
  "id": "w1_m01",
  "name": "Dust Frontier - Outpost Kilo",
  "cell_size": 64,
  "starting_credits": 300,
  "base_max_hp": 20,
  "movement_classes": ["infantry", "wheeled", "tracked"],
  "available_structures": ["sandbags", "concrete_wall", "antitank_barrier"],
  "rules": { "allow_remove_during_combat": false },
  "layout": ["S......B", "..."]
}
```

Leyenda: `.` suelo construible · `#` roca (bloquea todo) · `~` camino (transitable, no construible) ·
`S` spawn · `B` base (la celda objetivo es la más cercana al centro de las `B`).
El loader rechaza: JSON inválido, versión no soportada, filas desiguales, caracteres desconocidos,
sin spawn/base, campos de tipo incorrecto, ids de estructura desconocidos, spawns sin ruta inicial.

## 11. Campaña 📐

40 misiones en 4 mundos (Dust Frontier, Iron District, Black Forest, Frozen Front), 10 cada uno.
No se crearán hasta validar que la misión 1 es divertida (Hito 6).

## 12. Preguntas abiertas

- ¿Construcción durante el combate? (más tensión vs complejidad de enemigos atrapados). Hoy: no.
- Tamaño de torretas (1×1 vs 2×2) y si bloquean a todas las clases.
- Precisión táctil: resuelta en parte con zoom/pan (D-014); validar en dispositivo (Hito 5).

## 13. Controles táctiles

- Vista global a zoom 1 (todo el mapa visible: imprescindible para leer el laberinto durante el combate).
- Pellizco = zoom (hasta 3×), dos dedos = desplazar, un dedo sin herramienta = desplazar.
- Con herramienta: tocar/arrastrar apunta, soltar construye; soltar fuera del mapa o poner un segundo dedo cancela.
- Retirar: dos toques sobre la misma estructura (muestra el reembolso antes de confirmar).
