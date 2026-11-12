SET NAMES utf8mb4;
USE agro_trazabilidad;

SET SESSION cte_max_recursion_depth = 100000;
SET @fin_campana = DATE_SUB(CURDATE(), INTERVAL 5 DAY);

-- ---------------------------------------------------------------------
-- 1. Tickets de acopio (800). Cada ticket nace de un lote habilitado y su
--    fecha de cosecha es posterior a la liberación por carencia y a la
--    primera inspección aprobada del lote.
-- ---------------------------------------------------------------------
INSERT INTO ticket_acopio
    (codigo_ticket, id_lote, fecha_cosecha, fecha_recepcion, placa_vehiculo)
WITH RECURSIVE n (i) AS (
    SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 800
),
lotes AS (
    SELECT l.id_lote,
           ROW_NUMBER() OVER (ORDER BY l.id_lote) AS rn,
           COUNT(*) OVER () AS total,
           GREATEST(
               COALESCE((SELECT MAX(DATE(DATE_ADD(t.fecha_aplicacion,
                                         INTERVAL t.periodo_carencia_dias_aplicado DAY)))
                         FROM tratamiento_fitosanitario t
                         WHERE t.id_lote = l.id_lote), DATE('2000-01-01')),
               COALESCE((SELECT MIN(DATE(x.fecha_inspeccion))
                         FROM inspeccion_pre_cosecha x
                         WHERE x.id_lote = l.id_lote AND x.resultado = 'APROBADA'),
                        DATE('2000-01-01'))
           ) AS base
    FROM lote_agricola l
    WHERE l.estado = 'HABILITADO_PARA_COSECHA'
),
asignado AS (
    SELECT n.i, l.id_lote,
           DATE_ADD(l.base, INTERVAL MOD(CRC32(CONCAT('fecha-', n.i)),
                    GREATEST(DATEDIFF(@fin_campana, l.base), 0) + 1) DAY) AS f_cosecha
    FROM n
    JOIN lotes l ON l.rn = 1 + MOD(CRC32(CONCAT('lote-', n.i)), l.total)
)
SELECT CONCAT('TK-2026-', LPAD(a.i, 5, '0')),
       a.id_lote,
       a.f_cosecha,
       TIMESTAMP(a.f_cosecha, SEC_TO_TIME(25200 + MOD(CRC32(CONCAT('hora-', a.i)), 14400))),
       CONCAT(CHAR(65 + MOD(CRC32(CONCAT('pa', a.i)), 26) USING utf8mb4),
              CHAR(65 + MOD(CRC32(CONCAT('pb', a.i)), 26) USING utf8mb4),
              CHAR(65 + MOD(CRC32(CONCAT('pc', a.i)), 26) USING utf8mb4),
              '-', LPAD(MOD(CRC32(CONCAT('pd', a.i)), 1000), 3, '0'))
FROM asignado a;

-- ---------------------------------------------------------------------
-- 2. Control de calidad (uno por ticket): peso bruto, tara y descarte.
--    El peso neto pagable lo calcula la columna generada de la tabla.
-- ---------------------------------------------------------------------
INSERT INTO control_calidad
    (id_ticket, fecha_control, peso_bruto_kg, tara_kg, descarte_kg,
     id_calibre, id_destino_comercial)
WITH cal AS (
    SELECT id_calibre,
           ROW_NUMBER() OVER (ORDER BY CAST(codigo AS UNSIGNED)) AS rn,
           COUNT(*) OVER () AS total
    FROM calibre
    WHERE codigo REGEXP '^[0-9]+$'
),
base AS (
    SELECT t.id_ticket, t.codigo_ticket, t.fecha_recepcion,
           120 + MOD(CRC32(CONCAT(t.codigo_ticket, '-b')), 221) AS bruto
    FROM ticket_acopio t
    WHERE t.codigo_ticket LIKE 'TK-2026-%'
      AND NOT EXISTS (SELECT 1 FROM control_calidad c WHERE c.id_ticket = t.id_ticket)
)
SELECT b.id_ticket,
       DATE_ADD(b.fecha_recepcion, INTERVAL 1 HOUR),
       b.bruto,
       ROUND(b.bruto * (3 + MOD(CRC32(CONCAT(b.codigo_ticket, '-t')), 3)) / 100, 3),
       ROUND(b.bruto * (4 + MOD(CRC32(CONCAT(b.codigo_ticket, '-d')), 9)) / 100, 3),
       c.id_calibre,
       (SELECT d.id_destino_comercial FROM destino_comercial d
        WHERE d.nombre = IF(MOD(CRC32(CONCAT(b.codigo_ticket, '-x')), 100) < 88,
                            'EXPORTACION', 'NACIONAL'))
FROM base b
JOIN cal c ON c.rn = 1 + MOD(CRC32(CONCAT(b.codigo_ticket, '-c')), c.total);

UPDATE ticket_acopio t
JOIN control_calidad cc ON cc.id_ticket = t.id_ticket
SET t.estado = 'EVALUADO'
WHERE t.codigo_ticket LIKE 'TK-2026-%' AND t.estado = 'RECIBIDO';

-- ---------------------------------------------------------------------
-- 3. Liquidación: tarifa vigente según calibre y destino. Las de más de
--    30 días figuran como pagadas.
-- ---------------------------------------------------------------------
INSERT INTO liquidacion
    (id_ticket, id_tarifa, fecha_liquidacion, peso_neto_pagable_kg,
     precio_kg_aplicado_pen, estado)
SELECT t.id_ticket,
       tf.id_tarifa,
       DATE_ADD(t.fecha_recepcion, INTERVAL 1 DAY),
       cc.peso_neto_pagable_kg,
       tf.precio_kg_pen,
       IF(DATE(t.fecha_recepcion) < DATE_SUB(CURDATE(), INTERVAL 30 DAY), 'PAGADA', 'PENDIENTE')
FROM ticket_acopio t
JOIN control_calidad cc ON cc.id_ticket = t.id_ticket
JOIN tarifa tf ON tf.id_calibre = cc.id_calibre
              AND tf.id_destino_comercial = cc.id_destino_comercial
              AND tf.vigencia_desde <= DATE(DATE_ADD(t.fecha_recepcion, INTERVAL 1 DAY))
              AND (tf.vigencia_hasta IS NULL
                   OR tf.vigencia_hasta >= DATE(DATE_ADD(t.fecha_recepcion, INTERVAL 1 DAY)))
WHERE t.codigo_ticket LIKE 'TK-2026-%'
  AND NOT EXISTS (SELECT 1 FROM liquidacion li WHERE li.id_ticket = t.id_ticket);

UPDATE ticket_acopio t
JOIN liquidacion li ON li.id_ticket = t.id_ticket
SET t.estado = 'LIQUIDADO'
WHERE t.codigo_ticket LIKE 'TK-2026-%' AND t.estado = 'EVALUADO';

-- ---------------------------------------------------------------------
-- 4. Pallets (relación "conforma", Ticket N:M Pallet). Solo la fruta de
--    EXPORTACION se paletiza. Cada pallet recibe 1 000 kg netos (unas 100
--    cajas de 10 kg) tomados de tickets en orden cronológico: un pallet
--    reúne fruta de varios tickets y un ticket puede repartirse en dos pallets.
-- ---------------------------------------------------------------------
CREATE TEMPORARY TABLE tmp_acum AS
SELECT t.id_ticket,
       t.fecha_recepcion,
       cc.peso_neto_pagable_kg AS neto,
       SUM(cc.peso_neto_pagable_kg) OVER (
           ORDER BY t.fecha_recepcion, t.id_ticket
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS fin_acum
FROM ticket_acopio t
JOIN control_calidad cc ON cc.id_ticket = t.id_ticket
JOIN destino_comercial d ON d.id_destino_comercial = cc.id_destino_comercial
                        AND d.nombre = 'EXPORTACION'
WHERE t.codigo_ticket LIKE 'TK-2026-%'
  AND NOT EXISTS (SELECT 1 FROM ticket_pallet tp WHERE tp.id_ticket = t.id_ticket);

CREATE TEMPORARY TABLE tmp_tp AS
WITH RECURSIVE seq (k) AS (
    SELECT 1 UNION ALL SELECT k + 1 FROM seq WHERE k < 500
)
SELECT a.id_ticket,
       s.k AS nro_pallet,
       a.fecha_recepcion,
       ROUND(LEAST(a.fin_acum, s.k * 1000) - GREATEST(a.fin_acum - a.neto, (s.k - 1) * 1000), 3) AS kg
FROM tmp_acum a
JOIN seq s ON s.k BETWEEN FLOOR((a.fin_acum - a.neto) / 1000) + 1 AND CEIL(a.fin_acum / 1000);

INSERT INTO pallet (codigo_pallet, fecha_armado)
SELECT CONCAT('0017612345', LPAD(nro_pallet, 8, '0')),
       DATE_ADD(DATE_ADD(MAX(fecha_recepcion), INTERVAL 1 DAY), INTERVAL 3 HOUR)
FROM tmp_tp
WHERE kg > 0
GROUP BY nro_pallet;

-- Tabla auxiliar con los ids de pallet: el trigger trg_ticket_pallet_ai_cajas
-- actualiza pallet, y MySQL no permite leer esa misma tabla en el INSERT.
CREATE TEMPORARY TABLE tmp_pal AS
SELECT CAST(SUBSTRING(codigo_pallet, 11) AS UNSIGNED) AS nro_pallet, id_pallet
FROM pallet
WHERE codigo_pallet LIKE '0017612345%';

INSERT INTO ticket_pallet (id_ticket, id_pallet, cantidad_cajas, peso_neto_kg)
SELECT tp.id_ticket,
       pl.id_pallet,
       GREATEST(1, CAST(ROUND(tp.kg / 10) AS UNSIGNED)),
       tp.kg
FROM tmp_tp tp
JOIN tmp_pal pl ON pl.nro_pallet = tp.nro_pallet
WHERE tp.kg > 0;

-- ---------------------------------------------------------------------
-- 5. Contenedores reefer de 20 pallets y su consolidación (Pallet N:M
--    Contenedor): los llenos se despachan, el último con pallets queda
--    EN_CARGA y se deja uno PLANIFICADO vacío. Los pallets más recientes
--    quedan ARMADOS, sin contenedor.
-- ---------------------------------------------------------------------
SET @n_pallets    = (SELECT COUNT(*) FROM pallet WHERE codigo_pallet LIKE '0017612345%');
SET @n_asignados  = LEAST(@n_pallets, 140);
SET @n_cont_carga = CEIL(@n_asignados / 20);
SET @n_cont       = @n_cont_carga + 1;

CREATE TEMPORARY TABLE tmp_cont AS
WITH RECURSIVE c (k) AS (
    SELECT 1 UNION ALL SELECT k + 1 FROM c WHERE k < @n_cont
)
SELECT k,
       CAST(CEIL(k / 2) AS UNSIGNED) AS emb,
       CONCAT(ELT(1 + MOD(CEIL(k / 2) - 1, 5), 'MSKU', 'MSCU', 'CMAU', 'HLXU', 'CSNU'),
              LPAD(MOD(k * 1234567 + 89101, 10000000), 7, '0')) AS numero
FROM c;

INSERT INTO contenedor_maritimo (numero_contenedor)
SELECT numero FROM tmp_cont ORDER BY k;

INSERT INTO consolidacion (id_pallet, id_contenedor, fecha_consolidacion)
SELECT x.id_pallet, c.id_contenedor, DATE_ADD(p.fecha_armado, INTERVAL 1 HOUR)
FROM (SELECT id_pallet,
             ROW_NUMBER() OVER (ORDER BY fecha_armado, id_pallet) AS r
      FROM pallet
      WHERE codigo_pallet LIKE '0017612345%') x
JOIN pallet p ON p.id_pallet = x.id_pallet
JOIN tmp_cont tc ON tc.k = CEIL(x.r / 20)
JOIN contenedor_maritimo c ON c.numero_contenedor = tc.numero
WHERE x.r <= @n_asignados;

UPDATE pallet p
JOIN consolidacion cs ON cs.id_pallet = p.id_pallet
SET p.estado = 'ASIGNADO'
WHERE p.codigo_pallet LIKE '0017612345%';

UPDATE contenedor_maritimo c
JOIN tmp_cont tc ON tc.numero = c.numero_contenedor
SET c.estado = 'EN_CARGA'
WHERE tc.k <= @n_cont_carga;

-- ---------------------------------------------------------------------
-- 6. Embarques: cada uno agrupa 2 contenedores (relación 1..N). La naviera,
--    los puertos, el rango de temperatura y la fecha de zarpe son del embarque.
--    Los embarques ya zarpados despachan sus contenedores llenos.
-- ---------------------------------------------------------------------
INSERT INTO embarque_maritimo
    (codigo_embarque, id_naviera, id_puerto_salida, id_puerto_destino,
     temperatura_min_c, temperatura_max_c, fecha_programada, fecha_zarpe)
SELECT CONCAT('EMB-2026-', LPAD(e.emb, 3, '0')),
       nv.id_naviera,
       ps.id_puerto,
       pd.id_puerto,
       5.00, 7.00,
       e.f_prog,
       IF(e.min_k < @n_cont_carga, DATE_ADD(e.f_prog, INTERVAL 1 DAY), NULL)
FROM (SELECT tc.emb,
             MIN(tc.k) AS min_k,
             DATE_ADD(DATE_ADD(DATE(MAX(p.fecha_armado)), INTERVAL 2 DAY), INTERVAL 8 HOUR) AS f_prog
      FROM tmp_cont tc
      JOIN contenedor_maritimo c ON c.numero_contenedor = tc.numero
      JOIN consolidacion cs ON cs.id_contenedor = c.id_contenedor
      JOIN pallet p ON p.id_pallet = cs.id_pallet
      GROUP BY tc.emb) e
JOIN naviera nv ON nv.nombre = ELT(1 + MOD(e.emb - 1, 5), 'Maersk', 'MSC', 'CMA CGM', 'Hapag-Lloyd', 'COSCO Shipping')
JOIN puerto ps ON ps.pais = 'PE' AND ps.nombre = ELT(1 + MOD(e.emb, 2), 'Callao', 'Chancay')
JOIN puerto pd ON pd.nombre = ELT(1 + MOD(e.emb, 5), 'Rotterdam', 'Los Ángeles', 'Algeciras', 'Hamburgo', 'Shanghái');

UPDATE contenedor_maritimo c
JOIN tmp_cont tc ON tc.numero = c.numero_contenedor
JOIN embarque_maritimo e ON e.codigo_embarque = CONCAT('EMB-2026-', LPAD(tc.emb, 3, '0'))
SET c.id_embarque = e.id_embarque;

-- Despacho (el trigger valida embarque, fecha de zarpe y pallets consolidados)
UPDATE contenedor_maritimo c
JOIN tmp_cont tc ON tc.numero = c.numero_contenedor
SET c.estado = 'DESPACHADO'
WHERE tc.k < @n_cont_carga;

UPDATE pallet p
JOIN consolidacion cs ON cs.id_pallet = p.id_pallet
JOIN contenedor_maritimo c ON c.id_contenedor = cs.id_contenedor
SET p.estado = 'DESPACHADO'
WHERE c.estado = 'DESPACHADO' AND p.estado = 'ASIGNADO';

DROP TEMPORARY TABLE IF EXISTS tmp_acum;
DROP TEMPORARY TABLE IF EXISTS tmp_tp;
DROP TEMPORARY TABLE IF EXISTS tmp_pal;
DROP TEMPORARY TABLE IF EXISTS tmp_cont;

-- ---------------------------------------------------------------------
-- 7. Resumen de la carga
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS tickets,
       ROUND(SUM(cc.peso_bruto_kg) / 1000, 1) AS toneladas_recibidas,
       ROUND(SUM(cc.peso_neto_pagable_kg) / 1000, 1) AS toneladas_netas_pagables
FROM control_calidad cc
JOIN ticket_acopio t ON t.id_ticket = cc.id_ticket
WHERE t.codigo_ticket LIKE 'TK-2026-%';

SELECT (SELECT COUNT(*) FROM liquidacion) AS liquidaciones,
       (SELECT ROUND(SUM(importe_total_pen), 2) FROM liquidacion) AS importe_total_pen,
       (SELECT COUNT(*) FROM pallet) AS pallets,
       (SELECT SUM(cantidad_cajas) FROM pallet) AS cajas_en_pallets,
       (SELECT COUNT(*) FROM ticket_pallet) AS lineas_ticket_pallet,
       (SELECT COUNT(*) FROM consolidacion) AS consolidaciones,
       (SELECT COUNT(*) FROM contenedor_maritimo) AS contenedores,
       (SELECT COUNT(*) FROM embarque_maritimo) AS embarques;

SELECT estado, COUNT(*) AS contenedores FROM contenedor_maritimo GROUP BY estado;
SELECT estado, COUNT(*) AS pallets FROM pallet GROUP BY estado;
