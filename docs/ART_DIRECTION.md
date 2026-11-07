# Dirección de arte

**Estado actual:** todo lo visible son **placeholders procedurales** dibujados en `GridView._draw()` y UI
generada desde la paleta. No hay ilustraciones ni sprites finales.

## Identidad

Militar contemporáneo, táctico, sobrio. Cámara estrictamente cenital. Nada de cartoon infantil, neones,
fantasía futurista, ni insignias o marcas militares reales.

## Paleta oficial (`scripts/core/palette.gd`)

| Nombre | Hex | Uso |
|---|---|---|
| Olive Black | `#222B25` | Fondos, UI |
| Military Green | `#58664B` | Identidad, elementos militares propios |
| Sandstone | `#A5A58B` | Terreno, texto secundario, ruta de infantería |
| Tactical Gold | `#D3A43B` | Recursos, selección, progreso, ruta de vehículos de ruedas, base |
| Alert Red | `#B94336` | Daño, peligro, rechazos, spawns, ruta de orugas |

Neutros derivados (terreno, roca, hormigón) se definen en `Palette` como variaciones desaturadas, no tonos nuevos.

## Escala y cuadrícula

- **Celda:** 64×64 px lógicos (referencia 1080p). Sprites fuente a **128×128 por celda** (2×) para nitidez en
  pantallas de alta densidad; se importan con mipmaps desactivados y filtro lineal.
- **Proporciones** (en celdas): soldado ≈ 0,35 · vehículo ligero ≈ 0,7 × 0,45 · tanque ≈ 0,9 × 0,6 ·
  estructura 1×1 llena ≈ 0,9 (deja 0,05 de margen por lado para que se lea la cuadrícula).
- **Orientación:** unidades dibujadas mirando a la **derecha (+X)**; el motor rota.
- **Anclaje:** centro del sprite = centro de celda (unidades) o centro de la huella (estructuras).
- **Sombras:** sombra suave desplazada (+3, +4) px a 64 px, negro al 30 %, incluida en una capa aparte
  para poder desactivarla en gama baja.

## Capas (z_index / orden)

| z | Contenido |
|---|---|
| 0 | Terreno (TileMapLayer) |
| 10 | Decoración de suelo, marcas, rutas |
| 20 | Sombras |
| 30 | Estructuras y torretas (base) |
| 40 | Unidades terrestres |
| 50 | Torretas (cañón), proyectiles |
| 60 | Unidades aéreas |
| 70 | Explosiones, humo |
| 100 | Previsualización de construcción |
| UI | CanvasLayer |

## Nomenclatura de archivos

`<categoria>_<id>_<variante>_<estado>.png`, minúsculas y guiones bajos:
`structure_concrete_wall_base.png`, `turret_hmg_barrel_fire_sheet.png`, `enemy_heavy_tank_hull_damaged.png`,
`fx_explosion_medium_sheet.png`, `ui_icon_credits.png`, `terrain_desert_tileset.png`.

## Pipeline

1. Fuente (Krita/Aseprite/Blender render cenital) fuera del repo o en `art_src/` con Git LFS (por decidir).
2. Exportar PNG RGBA a `assets/<categoria>/`. Spritesheets en rejilla uniforme, frames de izquierda a derecha.
3. Terreno: `TileSet` con terrenos (autotile) en `assets/terrain/`.
4. Asignar el sprite en el `.tres` de datos (`StructureData.sprite`); el render placeholder se usa si es `null`.
5. Audio: OGG Vorbis (música en streaming), WAV cortos para disparos frecuentes. `assets/audio/`.
6. Revisión: verificar legibilidad con 50+ unidades en pantalla y en modo daltónico (rojo/verde no deben ser
   la única diferencia: por eso el fantasma inválido añade una X y el motivo en texto).

## Placeholders actuales

- Sacos: tres franjas arena. Muro: bloque gris con biselado. Barrera AT: "X" de acero (erizo checo).
- Spawn: marco rojo con "IN". Base: marco dorado con "HQ".

## Hito 3 — contraste de enemigos y efectos de combate (placeholders)

- **Problema medido en capturas del Hito 2:** cuerpos caqui sobre arena = bajo contraste.
- **Regla nueva:** facción enemiga = casco oscuro (`Palette.ENEMY_HULL`) + **contorno claro** de 2 px
  (`ENEMY_OUTLINE`) + marca roja (`ALERT_RED`: banda de casco o chevrón). Se lee sobre arena, roca y rutas.
- Tamaños visuales (solo dibujo; la navegación es por celdas): infantería 0,42; vehículo ligero 0,74 × 0,50;
  tanque 0,94 × 0,70 celdas. Destello claro al recibir impacto; barra de vida con fondo oscuro.
- Torretas: base octogonal fija (GridView) + arma giratoria (TurretView) con retroceso y fogonazo.
- Efectos: trazadora con halo + núcleo; misil con motor y estela de humo; chispas direccionales; explosión
  (bola de fuego + anillo + humo + quemadura 6–8 s); restos en vehículos destruidos; sacudida de cámara ligera en
  explosiones de misil y destrucción de blindados.
- Todos los colores de efectos y materiales están en `Palette` (`FX_*`, `METAL*`, `TRACK`, `SHADOW`).

