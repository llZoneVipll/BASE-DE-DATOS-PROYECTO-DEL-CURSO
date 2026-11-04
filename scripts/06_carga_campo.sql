-- =====================================================================
-- Archivo      : 06_carga_campo.sql
-- Responsable  : Castro
-- Proyecto     : Sistema de Trazabilidad Agroexportadora (UNMSM, BD I)
-- Motor        : MySQL 8.0.16+ / InnoDB / utf8mb4
-- Dependencias : 01_esquema.sql, 03_catalogos.sql y 04_objetos_campo_fitosanitario.sql
-- Objetivo     : Cargar datos ficticios coherentes de Campo y Fitosanitario.
--
-- Volumen generado:
--   100 productores
--   200 parcelas
--   300 lotes agrícolas
--   230 certificaciones (200 vigentes + 30 históricas vencidas)
--   10 inspectores autorizados
--   500 tratamientos fitosanitarios
--   300 inspecciones pre-cosecha
--
-- IMPORTANTE:
--   * Está pensado para ejecutarse en una instancia limpia, siguiendo el
--     orden oficial del proyecto.
--   * No recrea catálogos: toma IDs existentes de tipo_asociacion,
--     ubigeo y producto_fitosanitario. entidad_financiera es opcional.
--   * No desactiva triggers: la carga se ejecuta con los objetos del
--     script 04 activos.
-- =====================================================================

SET NAMES utf8mb4;
USE agro_trazabilidad;

DROP PROCEDURE IF EXISTS sp_carga_campo_castro;

DELIMITER $$

CREATE PROCEDURE sp_carga_campo_castro()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE j INT DEFAULT 1;

    DECLARE v_tipo_asociacion INT UNSIGNED;
    DECLARE v_entidad_financiera INT UNSIGNED;
    DECLARE v_ubigeo CHAR(6);
    DECLARE v_producto_fitosanitario INT UNSIGNED;
    DECLARE v_carencia INT UNSIGNED;

    DECLARE v_productor_id BIGINT UNSIGNED;
    DECLARE v_parcela_id BIGINT UNSIGNED;
    DECLARE v_lote_id BIGINT UNSIGNED;
    DECLARE v_inspector_id BIGINT UNSIGNED;

    DECLARE v_lon DECIMAL(10,6);
    DECLARE v_lat DECIMAL(10,6);
    DECLARE v_wkt TEXT;

    DECLARE v_fecha_aplicacion DATETIME;
    DECLARE v_fecha_ultima_aplicacion DATETIME;
    DECLARE v_fecha_inspeccion DATETIME;
    DECLARE v_dias_hasta_inspeccion INT;

    -- -------------------------------------------------------------
    -- 0. Precondiciones: catálogos creados/cargados por scripts previos
    -- -------------------------------------------------------------
    SELECT MIN(id_tipo_asociacion)
      INTO v_tipo_asociacion
      FROM tipo_asociacion;

    SELECT MIN(id_entidad_financiera)
      INTO v_entidad_financiera
      FROM entidad_financiera;

    SELECT MIN(codigo_ubigeo)
      INTO v_ubigeo
      FROM ubigeo;

    SELECT MIN(id_producto_fitosanitario)
      INTO v_producto_fitosanitario
      FROM producto_fitosanitario;

    IF v_tipo_asociacion IS NULL THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = '06_carga_campo: tipo_asociacion está vacío. Ejecute 03_catalogos.sql.';
    END IF;

    IF v_ubigeo IS NULL THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = '06_carga_campo: ubigeo está vacío. Ejecute 03_catalogos.sql.';
    END IF;

    IF v_producto_fitosanitario IS NULL THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = '06_carga_campo: producto_fitosanitario está vacío. Ejecute 03_catalogos.sql.';
    END IF;

    SELECT periodo_carencia_dias
      INTO v_carencia
      FROM producto_fitosanitario
     WHERE id_producto_fitosanitario = v_producto_fitosanitario;

    -- Evita duplicar la carga si alguien intenta ejecutarla dos veces.
    IF EXISTS (
        SELECT 1
          FROM productor
         WHERE tipo_documento = 'DNI'
           AND numero_documento = '70000001'
    ) THEN
        SIGNAL SQLSTATE '45000'
          SET MESSAGE_TEXT = '06_carga_campo: la carga CASTRO ya parece existir. Use una instancia limpia.';
    END IF;

    START TRANSACTION;

    -- -------------------------------------------------------------
    -- 1. PRODUCTORES: 100
    -- -------------------------------------------------------------
    SET i = 1;
    WHILE i <= 100 DO
        INSERT INTO productor (
            tipo_documento,
            numero_documento,
            nombre_completo,
            telefono,
            id_tipo_asociacion,
            id_entidad_financiera,
            numero_cuenta,
            activo
        )
        VALUES (
            'DNI',
            LPAD(70000000 + i, 8, '0'),
            CONCAT('Productor Campo ', LPAD(i, 3, '0')),
            CONCAT('9', LPAD(10000000 + i, 8, '0')),
            v_tipo_asociacion,
            v_entidad_financiera,
            CASE
                WHEN v_entidad_financiera IS NULL THEN NULL
                ELSE CONCAT('CCI-CAMPO-', LPAD(i, 10, '0'))
            END,
            TRUE
        );

        SET i = i + 1;
    END WHILE;

    -- -------------------------------------------------------------
    -- 2. PARCELAS: 200 (2 por productor)
    --    Polígonos pequeños en una malla geográfica de prueba.
    -- -------------------------------------------------------------
    SET i = 1;
    WHILE i <= 200 DO
        SELECT id_productor
          INTO v_productor_id
          FROM productor
         WHERE tipo_documento = 'DNI'
           AND numero_documento = LPAD(70000000 + CEIL(i / 2), 8, '0');

        SET v_lon = -77.270000 + MOD(i - 1, 20) * 0.002000;
        SET v_lat = -11.560000 - FLOOR((i - 1) / 20) * 0.002000;

        SET v_wkt = CONCAT(
            'POLYGON((',
            v_lon, ' ', v_lat, ',',
            v_lon + 0.001000, ' ', v_lat, ',',
            v_lon + 0.001000, ' ', v_lat - 0.001000, ',',
            v_lon, ' ', v_lat - 0.001000, ',',
            v_lon, ' ', v_lat,
            '))'
        );

        INSERT INTO parcela (
            id_productor,
            codigo_catastral,
            codigo_ubigeo,
            sector_agricola,
            poligono
        )
        VALUES (
            v_productor_id,
            CONCAT('CASTRO-PAR-', LPAD(i, 4, '0')),
            v_ubigeo,
            CONCAT('Sector Agrícola ', LPAD(1 + MOD(i - 1, 10), 2, '0')),
            ST_GeomFromText(v_wkt, 4326, 'axis-order=long-lat')
        );

        SET i = i + 1;
    END WHILE;

    -- -------------------------------------------------------------
    -- 3. LOTES AGRÍCOLAS: 300
    --    Todas las parcelas tienen L1; las primeras 100 tienen L2.
    -- -------------------------------------------------------------
    SET i = 1;
    WHILE i <= 200 DO
        SELECT id_parcela
          INTO v_parcela_id
          FROM parcela
         WHERE codigo_catastral = CONCAT('CASTRO-PAR-', LPAD(i, 4, '0'));

        INSERT INTO lote_agricola (
            id_parcela,
            codigo_lote,
            especie,
            variedad,
            fecha_siembra,
            fecha_ultima_poda,
            rendimiento_estimado_tn,
            estado
        )
        VALUES (
            v_parcela_id,
            'L1',
            'Palta',
            'Hass',
            DATE_ADD('2019-01-01', INTERVAL MOD(i, 900) DAY),
            DATE_ADD('2026-03-01', INTERVAL MOD(i, 90) DAY),
            2.500 + MOD(i, 18) * 0.250,
            'EN_INSPECCION'
        );

        IF i <= 100 THEN
            INSERT INTO lote_agricola (
                id_parcela,
                codigo_lote,
                especie,
                variedad,
                fecha_siembra,
                fecha_ultima_poda,
                rendimiento_estimado_tn,
                estado
            )
            VALUES (
                v_parcela_id,
                'L2',
                'Palta',
                'Hass',
                DATE_ADD('2020-01-15', INTERVAL MOD(i * 3, 700) DAY),
                DATE_ADD('2026-04-01', INTERVAL MOD(i, 75) DAY),
                1.800 + MOD(i, 14) * 0.220,
                'EN_INSPECCION'
            );
        END IF;

        SET i = i + 1;
    END WHILE;

    -- -------------------------------------------------------------
    -- 4. CERTIFICACIONES: 230
    --    Una certificación vigente por parcela + 30 históricas vencidas.
    -- -------------------------------------------------------------
    SET i = 1;
    WHILE i <= 200 DO
        SELECT id_parcela
          INTO v_parcela_id
          FROM parcela
         WHERE codigo_catastral = CONCAT('CASTRO-PAR-', LPAD(i, 4, '0'));

        INSERT INTO certificacion (
            id_parcela,
            nombre,
            codigo_certificacion,
            entidad_certificadora,
            fecha_inicio,
            fecha_fin
        )
        VALUES (
            v_parcela_id,
            CASE MOD(i, 3)
                WHEN 0 THEN 'GLOBALG.A.P.'
                WHEN 1 THEN 'Certificación de Lugar de Producción'
                ELSE 'Buenas Prácticas Agrícolas'
            END,
            CONCAT('CERT-CAMPO-V-', LPAD(i, 4, '0')),
            CASE MOD(i, 3)
                WHEN 0 THEN 'Certificadora Agro Andina'
                WHEN 1 THEN 'Entidad Certificadora Nacional'
                ELSE 'Control Agrícola del Pacífico'
            END,
            '2026-01-01',
            '2027-12-31'
        );

        IF i <= 30 THEN
            INSERT INTO certificacion (
                id_parcela,
                nombre,
                codigo_certificacion,
                entidad_certificadora,
                fecha_inicio,
                fecha_fin
            )
            VALUES (
                v_parcela_id,
                'Certificación histórica',
                CONCAT('CERT-CAMPO-H-', LPAD(i, 4, '0')),
                'Archivo Histórico de Certificación',
                '2024-01-01',
                '2025-12-31'
            );
        END IF;

        SET i = i + 1;
    END WHILE;

    -- -------------------------------------------------------------
    -- 5. INSPECTORES: 10 autorizados
    -- -------------------------------------------------------------
    SET i = 1;
    WHILE i <= 10 DO
        INSERT INTO inspector (
            numero_documento,
            nombre_completo,
            autorizado
        )
        VALUES (
            CONCAT('INS-CAMPO-', LPAD(i, 3, '0')),
            CONCAT('Inspector Sanitario ', LPAD(i, 2, '0')),
            TRUE
        );

        SET i = i + 1;
    END WHILE;

    -- -------------------------------------------------------------
    -- 6. TRATAMIENTOS + INSPECCIONES
    --    L1 recibe 2 tratamientos; L2 recibe 1.
    --    Total: 500 tratamientos y 300 inspecciones.
    -- -------------------------------------------------------------
    SET i = 1;
    WHILE i <= 200 DO
        SELECT id_parcela
          INTO v_parcela_id
          FROM parcela
         WHERE codigo_catastral = CONCAT('CASTRO-PAR-', LPAD(i, 4, '0'));

        SET j = 1;
        WHILE j <= CASE WHEN i <= 100 THEN 2 ELSE 1 END DO

            SELECT id_lote
              INTO v_lote_id
              FROM lote_agricola
             WHERE id_parcela = v_parcela_id
               AND codigo_lote = CONCAT('L', j);

            -- Primer tratamiento del lote.
            SET v_fecha_aplicacion =
                DATE_ADD('2026-07-01 08:00:00', INTERVAL MOD(i * 2 + j, 35) DAY);

            INSERT INTO tratamiento_fitosanitario (
                id_lote,
                id_producto_fitosanitario,
                fecha_aplicacion,
                periodo_carencia_dias_aplicado,
                observaciones
            )
            VALUES (
                v_lote_id,
                v_producto_fitosanitario,
                v_fecha_aplicacion,
                v_carencia,
                'Aplicación preventiva registrada en campaña 2026.'
            );

            SET v_fecha_ultima_aplicacion = v_fecha_aplicacion;

            -- Los L1 reciben una segunda aplicación, separada 20 días.
            IF j = 1 THEN
                SET v_fecha_ultima_aplicacion =
                    DATE_ADD(v_fecha_aplicacion, INTERVAL 20 DAY);

                INSERT INTO tratamiento_fitosanitario (
                    id_lote,
                    id_producto_fitosanitario,
                    fecha_aplicacion,
                    periodo_carencia_dias_aplicado,
                    observaciones
                )
                VALUES (
                    v_lote_id,
                    v_producto_fitosanitario,
                    v_fecha_ultima_aplicacion,
                    v_carencia,
                    'Segunda aplicación de seguimiento; respeta el historial de carencia.'
                );
            END IF;

            -- Inspector autorizado rotativo.
            SELECT id_inspector
              INTO v_inspector_id
              FROM inspector
             WHERE numero_documento =
                   CONCAT('INS-CAMPO-', LPAD(1 + MOD(i + j - 2, 10), 3, '0'));

            -- La inspección ocurre después de la carencia de la última aplicación.
            SET v_dias_hasta_inspeccion = v_carencia + 7 + MOD(i + j, 8);
            SET v_fecha_inspeccion =
                DATE_ADD(v_fecha_ultima_aplicacion, INTERVAL v_dias_hasta_inspeccion DAY);

            INSERT INTO inspeccion_pre_cosecha (
                id_lote,
                id_inspector,
                fecha_inspeccion,
                resultado,
                observaciones
            )
            VALUES (
                v_lote_id,
                v_inspector_id,
                v_fecha_inspeccion,
                CASE
                    WHEN MOD(i + j, 13) = 0 THEN 'RECHAZADA'
                    WHEN MOD(i + j, 17) = 0 THEN 'PENDIENTE'
                    ELSE 'APROBADA'
                END,
                CASE
                    WHEN MOD(i + j, 13) = 0
                        THEN 'Observación de campo: requiere corrección antes de habilitar cosecha.'
                    WHEN MOD(i + j, 17) = 0
                        THEN 'Acta pendiente de cierre administrativo.'
                    ELSE 'Inspección conforme; sin observaciones críticas.'
                END
            );

            SET j = j + 1;
        END WHILE;

        SET i = i + 1;
    END WHILE;

    COMMIT;
END$$

DELIMITER ;

CALL sp_carga_campo_castro();
DROP PROCEDURE sp_carga_campo_castro;

-- =====================================================================
-- VALIDACIÓN DE VOLUMEN
-- =====================================================================
SELECT 'productor' AS tabla, COUNT(*) AS filas
  FROM productor
 WHERE tipo_documento = 'DNI'
   AND numero_documento BETWEEN '70000001' AND '70000100'
UNION ALL
SELECT 'parcela', COUNT(*)
  FROM parcela
 WHERE codigo_catastral LIKE 'CASTRO-PAR-%'
UNION ALL
SELECT 'lote_agricola', COUNT(*)
  FROM lote_agricola la
  JOIN parcela p ON p.id_parcela = la.id_parcela
 WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'
UNION ALL
SELECT 'certificacion', COUNT(*)
  FROM certificacion c
  JOIN parcela p ON p.id_parcela = c.id_parcela
 WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'
UNION ALL
SELECT 'inspector', COUNT(*)
  FROM inspector
 WHERE numero_documento LIKE 'INS-CAMPO-%'
UNION ALL
SELECT 'tratamiento_fitosanitario', COUNT(*)
  FROM tratamiento_fitosanitario tf
  JOIN lote_agricola la ON la.id_lote = tf.id_lote
  JOIN parcela p ON p.id_parcela = la.id_parcela
 WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'
UNION ALL
SELECT 'inspeccion_pre_cosecha', COUNT(*)
  FROM inspeccion_pre_cosecha ip
  JOIN lote_agricola la ON la.id_lote = ip.id_lote
  JOIN parcela p ON p.id_parcela = la.id_parcela
 WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%';

-- Resultado esperado:
-- productor                  100
-- parcela                    200
-- lote_agricola              300
-- certificacion              230
-- inspector                   10
-- tratamiento_fitosanitario  500
-- inspeccion_pre_cosecha     300
