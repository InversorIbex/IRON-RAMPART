# IRON RAMPART — Game Design Document

Estado: borrador vivo. Los valores numéricos son provisionales hasta las pruebas de equilibrio (Hito 6).
Marcadores: ✅ implementado · 🧪 implementado sin verificar en motor · 📐 diseñado, no implementado.

## 1. Pilares

1. **El jugador diseña el camino.** No hay rutas fijas; cada estructura cambia la ruta enemiga.
2. **Cada construcción es una decisión.** Presupuesto escaso, roles distintos, nada es "más de lo mismo".
3. **Fácil de leer, difícil de dominar.** La ruta actual de cada tipo de enemigo siempre es visible.
4. **Gana la planificación.** El mismo presupuesto bien colocado debe superar al mal colocado por mucho.

## 2. Bucle de juego ✅

Preparación (sin prisa) → START WAVE → combate (construir con recargo) → oleada resuelta (bono) → preparación …
→ victoria (todas las oleadas) o derrota (HQ a 0). Ver §9.

## 3. Cuadrícula y laberintos ✅

- Mapa de celdas (misión 1: 24×16, celda 64 px lógicos). Dimensiones definidas por el nivel.
- Movimiento enemigo ortogonal (sin diagonales).
- **Regla de oro:** no se puede construir si deja a algún spawn sin ruta a la base **para alguna clase de
  movimiento presente en la misión**. El rechazo explica la clase afectada y marca el spawn en rojo.
- La ruta actual de cada clase se dibuja en el mapa (arena = infantería, oro = ruedas, rojo = orugas).
- Retirada: solo en fase de construcción (configurable por nivel), dos toques, reembolso `floor(coste × refund_ratio)`.
- **Construir en combate** ✅ (confirmado, D-012/D-015):
  - Entre oleadas, coste normal; en combate, **recargo del 25 %** (`combat_build_surcharge`, configurable por nivel),
    solo en construcciones nuevas, visible en el botón (`125 CR*` + nota) y sobre el fantasma (`125 CR (+25)`).
    El reembolso al retirar usa el coste base.
  - No se puede construir sobre enemigos, ni dejar enemigos atrapados, ni bloquear el acceso a la base.
  - Una construcción rechazada nunca consume créditos (validación y cobro son una sola operación).
  - Los enemigos adoptan la nueva ruta al llegar a su siguiente celda.

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

## 6. Torretas ✅ (Hito 3; valores provisionales en `data/turrets/*.tres` + `data/structures/turret_*.tres`)

| Torreta | Coste | Vida | Alcance | Cadencia | Daño | Tipo | Área | Objetivos | Prioridad |
|---|---|---|---|---|---|---|---|---|---|
| Heavy Machine Gun | 100 | 250 | 3,0 | 8,3/s | 9 | BULLET | — | Tierra | FIRST |
| Missile Launcher | 180 | 300 | 4,5 | 0,6/s | 120 | EXPLOSIVE | 0,9 (50 %) | Tierra | STRONGEST |
| Anti-Aircraft Defense | 150 | 250 | 5,0 | 2,9/s | 30 | FLAK | 0,5 (50 %) | **Solo aire** | CLOSEST |

- Huella 1×1; **bloquean a todas las clases**: son parte del laberinto (y tampoco pueden sellar la base).
- Giran hacia el objetivo (velocidad de giro y tolerancia de puntería en datos) y solo disparan alineadas.
- Prioridades: FIRST (menor distancia **real por ruta** a la base, del campo de flujo), CLOSEST, STRONGEST.
  Desempate por id: determinista.
- El AA no dispara a unidades terrestres (no hay aéreas todavía): queda preparado para el mundo 3.
- Pendiente: mejoras de torretas, cambio de prioridad en partida, vida de torretas (los enemigos aún no atacan).

### Daño y blindaje

`daño final = daño × multiplicador[tipo][blindaje]`

| Tipo \ Blindaje | NONE (infantería) | LIGHT (vehículo ligero) | HEAVY (tanque) |
|---|---|---|---|
| BULLET | 1,00 | 0,50 | 0,10 |
| EXPLOSIVE | 0,60 | 1,00 | 1,00 |
| FLAK | 0,60 | 0,40 | 0,15 |
| GENERIC | 1,00 | 0,75 | 0,40 |

DPS efectivo aproximado: HMG 75 vs infantería, 37 vs ligero, 7,5 vs tanque; misiles 45 vs infantería (+área),
75 vs ligero/tanque. Resultado buscado: la HMG barre infantería y no sirve contra tanques; los misiles son la
respuesta al blindaje.

## 7. Enemigos ✅ (Hito 2; valores provisionales en `data/enemies/*.tres`)

| Enemigo | Clase | Vida | Velocidad (celdas/s) | Blindaje | Daño a HQ | Recompensa |
|---|---|---|---|---|---|---|
| Infantry | INFANTRY | 60 | 1,5 | NONE | 1 | 5 |
| Light Vehicle | WHEELED | 110 | 2,4 | LIGHT | 2 | 10 |
| Heavy Tank | TRACKED | 600 | 0,8 | HEAVY | 5 | 30 |

(Hito 4: ligero 140 → 110 HP y recompensas ajustadas por simulación, D-021. Las oleadas pueden multiplicar vida y
velocidad por unidad.)

- Blindaje = clase (NONE/LIGHT/HEAVY) contra el tipo de daño del arma (ver tabla en §6).
- Todos los enemigos de una clase comparten la misma navegación; la ruta dibujada es exactamente la que siguen.
- `TEST ASSAULT` (HUD, depuración) lanza una columna de 10 unidades (17 de daño al HQ si nadie dispara).

## 8. Economía ✅ (Hito 4)

| Concepto | Valor (misión 1) | Regla |
|---|---|---|
| Presupuesto inicial | **350 CR** | Da para HMG + lanzamisiles, o HMG + laberinto, pero no ambas cosas a la vez |
| Baja de infantería / ligero / tanque | 5 / 10 / 30 CR | Se paga **una vez** al morir; llegar al HQ no paga nada |
| Bono por oleada completada | 60 / 70 / 90 / 110 / — | Una vez por oleada; la última no tiene bono (la recompensa es la victoria) |
| Construcción entre oleadas | coste base | `PREPARATION` y `WAVE_COMPLETED` |
| Construcción en combate | coste × 1,25 (redondeo hacia arriba) | `combat_build_surcharge`, configurable por misión |
| Retirar | 75 % del coste base | Solo entre oleadas en la misión 1 (`allow_remove_during_combat: false`) |

- Créditos nunca negativos; una construcción rechazada no cobra; precio único (`price_of`) para HUD, fantasma y cobro.
- Ingresos totales de una partida completa bien defendida ≈ 1080 CR (simulación): no alcanza para "todo".
- Reparar: no aplica todavía (los enemigos no dañan estructuras). Reorganizar = retirar (75 %) y reconstruir.

## 9. OPERATION FIRST ASSAULT ✅ (Hito 4) — `data/levels/mission_01.json`

**Briefing:** el Puesto Avanzado Kilo protege la única ruta de suministro del Dust Frontier. Columnas hostiles entran
por la carretera oeste y el paso norte. Mantener el HQ (20 puntos) durante cinco oleadas.

| # | Nombre | Composición | Entradas | Modificadores | Bono | Intención de diseño |
|---|---|---|---|---|---|---|
| 1 | First Contact | 8 infantería (cada 1,6 s) | oeste | — | 60 | Aprender: una HMG bien colocada basta |
| 2 | Fast Approach | 10 infantería + 3 ligeros (desde 8 s) | ambas / norte | — | 70 | Lección de velocidad: el norte necesita cobertura |
| 3 | Armored Threat | 8 inf. + 5 ligeros + **1 tanque** (14 s) | oeste / norte / oeste | — | 90 | Primer blindado: aviso "ARMOR INBOUND"; las balas no bastan |
| 4 | Breaking Point | 12 inf. + 6 ligeros + 3 tanques (cada 7 s) | alternas | vida ×1,1 | 110 | Presión mixta por los dos accesos |
| 5 | Iron Assault | 18 inf. + 9 ligeros + **6 tanques** (cada 3,5 s) | alternas | vida ×1,25, vel. ×1,05 | — | Clímax: la defensa debe estar completa |

Escalada por **composición, entradas y ritmo** (no solo vida): solo las oleadas 4 y 5 llevan modificadores.

### Estados de partida

`PREPARATION` (sin límite de tiempo, construir sin recargo, panel INTEL con la próxima oleada) → START WAVE →
`WAVE_ACTIVE` (borde rojo "UNDER ATTACK", construcción con recargo) → oleada resuelta → `WAVE_COMPLETED`
(banner + bono, construir sin recargo; START WAVE la salta) → `PREPARATION` … → `VICTORY` tras la 5.ª, o
`DEFEAT` si el HQ llega a 0. `PAUSED` desde cualquier estado no final, reanuda el anterior.

### Victoria, derrota y puntuación

- Victoria: 5 oleadas completadas, sin enemigos activos, HQ > 0 → MISSION COMPLETE con oleadas, bajas, HQ, créditos,
  puntuación y estrellas. Derrota: HQ = 0 → MISSION FAILED con oleada alcanzada y bajas. Ambas detienen la simulación.
- **Puntuación** = 500 × oleadas + 10 × bajas + 150 × HQ restante + créditos + 1000 si victoria.
  Estrellas: 3 sin daño al HQ, 2 con ≥ 50 %, 1 victoria ajustada.

### Feedback

Banner de misión al entrar; banner de inicio de oleada; "ARMOR INBOUND" con la primera aparición de tanques en una
oleada; destello rojo + sacudida al dañar el HQ; "+N" dorado en cada baja; "WAVE N CLEARED +bono"; pulso rojo del
contador y sonido seco si faltan créditos; pantallas de resultados. Sonidos sintetizados provisionales (D-022).

## 10. Formato de misiones

`data/levels/<id>.json` (ejemplo resumido; referencia completa: `mission_01.json`):

```json
{
  "format_version": 1,
  "id": "w1_m01",
  "name": "Operation First Assault",
  "mission": { "region": "Dust Frontier", "theme": "desert", "briefing": "...",
               "spawn_names": ["north", "west"], "debrief_seconds": 3.0 },
  "victory": { "type": "survive_all_waves" },
  "cell_size": 64,
  "starting_credits": 350,
  "base_max_hp": 20,
  "movement_classes": ["infantry", "wheeled", "tracked"],
  "available_structures": ["sandbags", "concrete_wall", "antitank_barrier", "turret_hmg", "turret_missile", "turret_aa"],
  "rules": { "allow_build_during_combat": true, "combat_build_surcharge": 0.25, "allow_remove_during_combat": false },
  "waves": [
    { "id": "w1", "name": "First Contact", "reward": 60, "modifiers": { "hp": 1.0, "speed": 1.0 },
      "completion": "all_spawned_and_cleared",
      "groups": [ { "enemy": "infantry", "count": 8, "start": 0, "interval": 1.6, "spawn": "west" } ] }
  ],
  "layout": ["S......B", "..."]
}
```

Leyenda del layout: `.` suelo construible · `#` roca · `~` camino (transitable, no construible) · `S` spawn (orden de
lectura = orden de `spawn_names`) · `B` base. `spawn` de un grupo: nombre, índice o `"alternate"`.

El loader rechaza con mensaje explícito: JSON inválido, versión, filas desiguales, caracteres desconocidos, sin
spawn/base, tipos incorrectos, estructuras/enemigos desconocidos, spawns sin ruta, ids de oleada repetidos, grupos
vacíos, `count`/`start`/`interval`/modificadores fuera de rango, spawn inexistente, `spawn_names` de longitud
distinta, tema o tipo de victoria desconocidos, `completion` desconocida.

## 11. Campaña 📐

40 misiones en 4 mundos (Dust Frontier, Iron District, Black Forest, Frozen Front), 10 cada uno.
No se crearán hasta validar que la misión 1 es divertida (Hito 6). El formato ya lo soporta: una misión = un JSON con
mapa, presupuesto, HQ, spawns con nombre, oleadas, reglas, victoria e identidad (`mission.region/theme/briefing`);
una prueba carga una segunda misión distinta sin cambios de código.

## 12. Preguntas abiertas

- ¿Construcción durante el combate? (más tensión vs complejidad de enemigos atrapados). Hoy: no.
- Tamaño de torretas (1×1 vs 2×2) y si bloquean a todas las clases.
- Precisión táctil: resuelta en parte con zoom/pan (D-014); validar en dispositivo (Hito 5).

## 13. Controles táctiles

- Vista global a zoom 1 (todo el mapa visible: imprescindible para leer el laberinto durante el combate).
- Pellizco = zoom (hasta 3×), dos dedos = desplazar, un dedo sin herramienta = desplazar.
- Con herramienta: tocar/arrastrar apunta, soltar construye; soltar fuera del mapa o poner un segundo dedo cancela.
- Retirar: dos toques sobre la misma estructura (muestra el reembolso antes de confirmar).
