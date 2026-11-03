# Convenciones de nomenclatura

Propuesta inicial de Matias para que el equipo ajuste el día 1. Una vez acordada, no se cambia.

| Objeto | Convención | Ejemplo |
|---|---|---|
| Base de datos | `snake_case` | `agro_trazabilidad` |
| Tablas | `snake_case`, singular | `productor`, `lote_agricola` |
| Columnas | `snake_case` | `fecha_liberacion_cosecha` |
| Llave primaria | `pk_<tabla>` | `pk_productor` |
| Llave foránea | `fk_<hija>_<padre>` | `fk_parcela_productor` |
| Índice | `idx_<tabla>_<columna>` | `idx_parcela_ubigeo` |
| Único | `uq_<tabla>_<columna>` | `uq_productor_documento` |
| Check | `ck_<tabla>_<regla>` | `ck_lote_estado` |
| Trigger | `trg_<tabla>_<momento_evento>` | `trg_lote_bu_habilitacion` |
| Procedimiento | `sp_<verbo>_<objeto>` | `sp_registrar_ticket` |
| Función | `fn_<nombre>` | `fn_peso_neto` |
| Vista | `vw_<nombre>` | `vw_trazabilidad_reversa` |

Notas para MySQL: no hay secuencias (se usa `AUTO_INCREMENT`) ni paquetes (los objetos se agrupan por archivo y área). Codificación `utf8mb4`.

## Puntos por definir

- Relación Pallet–Ticket de acopio: si es N:M, lleva tabla intermedia.
- Generalización de Productor: tabla única con tipo, o una tabla por subtipo.
- Atributos derivados (fecha de liberación, peso neto pagable): trigger o función, o solo vistas.
