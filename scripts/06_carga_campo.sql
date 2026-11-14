-- ---------------------------------------------------------------------
-- Modulo: Carga de datos de Campo y Control Fitosanitario
-- Archivo: 06_carga_campo.sql
-- Autor: Castro
-- ---------------------------------------------------------------------

SET NAMES utf8mb4;
USE agro_trazabilidad;

DROP PROCEDURE IF EXISTS sp_carga_campo_castro;

DELIMITER $$

CREATE PROCEDURE sp_carga_campo_castro()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE j INT DEFAULT 1;

    DECLARE v_num_asociaciones INT DEFAULT 0;
    DECLARE v_num_bancos INT DEFAULT 0;
    DECLARE v_num_ubigeos INT DEFAULT 0;
    DECLARE v_num_productos INT DEFAULT 0;
    DECLARE v_num_inspectores_aut INT DEFAULT 0;

    DECLARE v_id_asociacion INT UNSIGNED;
    DECLARE v_id_banco INT UNSIGNED;
    DECLARE v_ubigeo CHAR(6);
    DECLARE v_id_producto INT UNSIGNED;

    DECLARE v_productor_id BIGINT UNSIGNED;
    DECLARE v_parcela_id BIGINT UNSIGNED;
    DECLARE v_lote_id BIGINT UNSIGNED;
    DECLARE v_certificacion_id BIGINT UNSIGNED;
    DECLARE v_inspector_id BIGINT UNSIGNED;
    DECLARE v_inspeccion_id BIGINT UNSIGNED;
    DECLARE v_tratamiento_id BIGINT UNSIGNED;

    DECLARE v_lon DECIMAL(10,6);
    DECLARE v_lat DECIMAL(10,6);
    DECLARE v_wkt TEXT;

    DECLARE v_max_lotes INT;
    DECLARE v_dias_atras INT;
    DECLARE v_fecha_aplicacion DATETIME;
    DECLARE v_fecha_ultima_aplicacion DATETIME;
    DECLARE v_fecha_liberacion DATETIME;
    DECLARE v_fecha_inspeccion DATETIME;
    DECLARE v_resultado VARCHAR(20);

    -- Control de errores
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Validación de catálogos y objetos necesarios

    SELECT COUNT(*) INTO v_num_asociaciones
    FROM tipo_asociacion;

    SELECT COUNT(*) INTO v_num_bancos
    FROM entidad_financiera;

    SELECT COUNT(*) INTO v_num_ubigeos
    FROM ubigeo;

    SELECT COUNT(*) INTO v_num_productos
    FROM producto_fitosanitario;

    SELECT COUNT(*) INTO v_num_inspectores_aut
    FROM inspector
    WHERE autorizado = TRUE;

    IF v_num_asociaciones = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: tipo_asociacion está vacío. Ejecute 03_catalogos.sql.';
    END IF;

    IF v_num_bancos = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: entidad_financiera está vacío. Ejecute 03_catalogos.sql.';
    END IF;

    IF v_num_ubigeos = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: ubigeo está vacío. Ejecute 03_catalogos.sql.';
    END IF;

    IF v_num_productos = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: producto_fitosanitario está vacío. Ejecute 03_catalogos.sql.';
    END IF;

    IF v_num_inspectores_aut = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: no existen inspectores autorizados. Revise 03_catalogos.sql.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME = 'sp_mantenimiento_productor'
          AND ROUTINE_TYPE = 'PROCEDURE'
    ) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: falta sp_mantenimiento_productor. Ejecute 04_objetos_campo_fitosanitario.sql.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME = 'sp_mantenimiento_parcela'
          AND ROUTINE_TYPE = 'PROCEDURE'
    ) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: falta sp_mantenimiento_parcela. Ejecute 04_objetos_campo_fitosanitario.sql.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME = 'sp_mantenimiento_lote'
          AND ROUTINE_TYPE = 'PROCEDURE'
    ) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: falta sp_mantenimiento_lote. Ejecute 04_objetos_campo_fitosanitario.sql.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME = 'sp_mantenimiento_certificacion'
          AND ROUTINE_TYPE = 'PROCEDURE'
    ) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: falta sp_mantenimiento_certificacion. Ejecute 04_objetos_campo_fitosanitario.sql.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME = 'sp_registrar_tratamiento'
          AND ROUTINE_TYPE = 'PROCEDURE'
    ) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: falta sp_registrar_tratamiento. Ejecute 04_objetos_campo_fitosanitario.sql.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME = 'sp_mantenimiento_inspeccion'
          AND ROUTINE_TYPE = 'PROCEDURE'
    ) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: falta sp_mantenimiento_inspeccion. Ejecute 04_objetos_campo_fitosanitario.sql.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA = DATABASE()
          AND ROUTINE_NAME = 'fn_calcular_fecha_liberacion'
          AND ROUTINE_TYPE = 'FUNCTION'
    ) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: falta fn_calcular_fecha_liberacion. Ejecute 04_objetos_campo_fitosanitario.sql.';
    END IF;

    IF (
        SELECT COUNT(*)
        FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA = DATABASE()
          AND TRIGGER_NAME = 'trg_valida_habilitacion_lote'
    ) = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: falta trg_valida_habilitacion_lote. Ejecute 04_objetos_campo_fitosanitario.sql.';
    END IF;

    -- Evitar duplicar la carga
    IF EXISTS (
        SELECT 1
        FROM productor
        WHERE tipo_documento = 'DNI'
          AND numero_documento = '70000001'
    ) OR EXISTS (
        SELECT 1
        FROM parcela
        WHERE codigo_catastral = 'CASTRO-PAR-0001'
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = '06_carga_campo: la carga Castro ya existe. Use una instancia limpia.';
    END IF;

    START TRANSACTION;

    -- Productores
    SET i = 1;

    WHILE i <= 100 DO

        SELECT x.id_tipo_asociacion
        INTO v_id_asociacion
        FROM (
            SELECT
                id_tipo_asociacion,
                ROW_NUMBER() OVER (ORDER BY id_tipo_asociacion) AS rn
            FROM tipo_asociacion
        ) AS x
        WHERE x.rn = 1 + MOD(i - 1, v_num_asociaciones);

        SELECT x.id_entidad_financiera
        INTO v_id_banco
        FROM (
            SELECT
                id_entidad_financiera,
                ROW_NUMBER() OVER (ORDER BY id_entidad_financiera) AS rn
            FROM entidad_financiera
        ) AS x
        WHERE x.rn = 1 + MOD(i - 1, v_num_bancos);

        SET v_productor_id = NULL;

        CALL sp_mantenimiento_productor(
            'INSERT',
            v_productor_id,
            'DNI',
            LPAD(70000000 + i, 8, '0'),
            CONCAT('Productor Campo ', LPAD(i, 3, '0')),
            CONCAT('9', LPAD(10000000 + i, 8, '0')),
            v_id_asociacion,
            v_id_banco,
            CONCAT('CCI-CAMPO-', LPAD(i, 20, '0')),
            TRUE
        );

        SET i = i + 1;
    END WHILE;

    -- Parcelas
    SET i = 1;

    WHILE i <= 200 DO

        SELECT id_productor
        INTO v_productor_id
        FROM productor
        WHERE tipo_documento = 'DNI'
          AND numero_documento = LPAD(70000000 + CEIL(i / 2), 8, '0');

        SELECT x.codigo_ubigeo
        INTO v_ubigeo
        FROM (
            SELECT
                codigo_ubigeo,
                ROW_NUMBER() OVER (ORDER BY codigo_ubigeo) AS rn
            FROM ubigeo
        ) AS x
        WHERE x.rn = 1 + MOD(i - 1, v_num_ubigeos);

        -- Coordenadas de prueba
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

        SET v_parcela_id = NULL;

        CALL sp_mantenimiento_parcela(
            'INSERT',
            v_parcela_id,
            v_productor_id,
            CONCAT('CASTRO-PAR-', LPAD(i, 4, '0')),
            v_ubigeo,
            CONCAT('Sector Agrícola ', LPAD(1 + MOD(i - 1, 10), 2, '0')),
            ST_GeomFromText(v_wkt, 4326, 'axis-order=long-lat')
        );

        SET i = i + 1;
    END WHILE;

    -- Lotes agrícolas
    SET i = 1;

    WHILE i <= 200 DO

        SELECT id_parcela
        INTO v_parcela_id
        FROM parcela
        WHERE codigo_catastral = CONCAT('CASTRO-PAR-', LPAD(i, 4, '0'));

        SET v_lote_id = NULL;

        CALL sp_mantenimiento_lote(
            'INSERT',
            v_lote_id,
            v_parcela_id,
            'L1',
            'Palta',
            'Hass',
            DATE_SUB(CURDATE(), INTERVAL (2200 + MOD(i, 800)) DAY),
            DATE_SUB(CURDATE(), INTERVAL (120 + MOD(i, 60)) DAY),
            2.500 + MOD(i, 18) * 0.250,
            'EN_INSPECCION'
        );

        IF i <= 100 THEN

            SET v_lote_id = NULL;

            CALL sp_mantenimiento_lote(
                'INSERT',
                v_lote_id,
                v_parcela_id,
                'L2',
                'Palta',
                'Hass',
                DATE_SUB(CURDATE(), INTERVAL (1900 + MOD(i * 3, 700)) DAY),
                DATE_SUB(CURDATE(), INTERVAL (100 + MOD(i, 50)) DAY),
                1.800 + MOD(i, 14) * 0.220,
                'EN_INSPECCION'
            );

        END IF;

        SET i = i + 1;
    END WHILE;

    -- Certificaciones
    SET i = 1;

    WHILE i <= 200 DO

        SELECT id_parcela
        INTO v_parcela_id
        FROM parcela
        WHERE codigo_catastral = CONCAT('CASTRO-PAR-', LPAD(i, 4, '0'));

        SET v_certificacion_id = NULL;

        CALL sp_mantenimiento_certificacion(
            'INSERT',
            v_certificacion_id,
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
            DATE_SUB(CURDATE(), INTERVAL 180 DAY),
            DATE_ADD(CURDATE(), INTERVAL 365 DAY)
        );

        IF i <= 30 THEN

            SET v_certificacion_id = NULL;

            CALL sp_mantenimiento_certificacion(
                'INSERT',
                v_certificacion_id,
                v_parcela_id,
                'Certificación histórica',
                CONCAT('CERT-CAMPO-H-', LPAD(i, 4, '0')),
                'Archivo Histórico de Certificación',
                DATE_SUB(CURDATE(), INTERVAL 730 DAY),
                DATE_SUB(CURDATE(), INTERVAL 365 DAY)
            );

        END IF;

        SET i = i + 1;
    END WHILE;

    -- Tratamientos e inspecciones
    SET i = 1;

    WHILE i <= 200 DO

        SELECT id_parcela
        INTO v_parcela_id
        FROM parcela
        WHERE codigo_catastral = CONCAT('CASTRO-PAR-', LPAD(i, 4, '0'));

        SET j = 1;
        SET v_max_lotes = IF(i <= 100, 2, 1);

        WHILE j <= v_max_lotes DO

            SELECT id_lote
            INTO v_lote_id
            FROM lote_agricola
            WHERE id_parcela = v_parcela_id
              AND codigo_lote = CONCAT('L', j);

            SELECT x.id_producto_fitosanitario
            INTO v_id_producto
            FROM (
                SELECT
                    id_producto_fitosanitario,
                    ROW_NUMBER() OVER (ORDER BY id_producto_fitosanitario) AS rn
                FROM producto_fitosanitario
            ) AS x
            WHERE x.rn = 1 + MOD(i + j - 2, v_num_productos);

            -- Fecha de aplicación
            SET v_dias_atras = 120 + MOD(i * 2 + j, 35);

            SET v_fecha_aplicacion =
                TIMESTAMP(
                    DATE_SUB(CURDATE(), INTERVAL v_dias_atras DAY),
                    '08:00:00'
                );

            SET v_tratamiento_id = NULL;

            CALL sp_registrar_tratamiento(
                v_lote_id,
                v_id_producto,
                v_fecha_aplicacion,
                'Aplicación preventiva registrada en campaña de prueba.',
                v_tratamiento_id
            );

            SET v_fecha_ultima_aplicacion = v_fecha_aplicacion;

            -- Segunda aplicación para lotes L1
            IF j = 1 THEN

                SELECT x.id_producto_fitosanitario
                INTO v_id_producto
                FROM (
                    SELECT
                        id_producto_fitosanitario,
                        ROW_NUMBER() OVER (ORDER BY id_producto_fitosanitario) AS rn
                    FROM producto_fitosanitario
                ) AS x
                WHERE x.rn = 1 + MOD(i + j + 2, v_num_productos);

                SET v_fecha_ultima_aplicacion =
                    DATE_ADD(v_fecha_aplicacion, INTERVAL 20 DAY);

                SET v_tratamiento_id = NULL;

                CALL sp_registrar_tratamiento(
                    v_lote_id,
                    v_id_producto,
                    v_fecha_ultima_aplicacion,
                    'Segunda aplicación de seguimiento.',
                    v_tratamiento_id
                );

            END IF;

            -- Fecha de liberación
            SET v_fecha_liberacion =
                fn_calcular_fecha_liberacion(
                    v_fecha_ultima_aplicacion,
                    v_id_producto
                );

            SET v_fecha_inspeccion =
                DATE_ADD(
                    v_fecha_liberacion,
                    INTERVAL (7 + MOD(i + j, 8)) DAY
                );

            -- Inspector autorizado
            SELECT x.id_inspector
            INTO v_inspector_id
            FROM (
                SELECT
                    id_inspector,
                    ROW_NUMBER() OVER (ORDER BY id_inspector) AS rn
                FROM inspector
                WHERE autorizado = TRUE
            ) AS x
            WHERE x.rn = 1 + MOD(i + j - 2, v_num_inspectores_aut);

            SET v_resultado =
                CASE
                    WHEN MOD(i + j, 13) = 0 THEN 'RECHAZADA'
                    WHEN MOD(i + j, 17) = 0 THEN 'PENDIENTE'
                    ELSE 'APROBADA'
                END;

            SET v_inspeccion_id = NULL;

            CALL sp_mantenimiento_inspeccion(
                'INSERT',
                v_inspeccion_id,
                v_lote_id,
                v_inspector_id,
                v_fecha_inspeccion,
                v_resultado,
                CASE
                    WHEN v_resultado = 'RECHAZADA'
                        THEN 'Observación de campo: requiere corrección antes de habilitar cosecha.'
                    WHEN v_resultado = 'PENDIENTE'
                        THEN 'Acta pendiente de cierre administrativo.'
                    ELSE 'Inspección conforme; sin observaciones críticas.'
                END
            );

            -- Estado del lote
            IF v_resultado = 'APROBADA' THEN

                UPDATE lote_agricola
                SET estado = 'HABILITADO_PARA_COSECHA'
                WHERE id_lote = v_lote_id;

            ELSEIF v_resultado = 'RECHAZADA' THEN

                UPDATE lote_agricola
                SET estado = 'BLOQUEADO'
                WHERE id_lote = v_lote_id;

            END IF;

            SET j = j + 1;
        END WHILE;

        SET i = i + 1;
    END WHILE;

    COMMIT;
END$$

DELIMITER ;

CALL sp_carga_campo_castro();
DROP PROCEDURE sp_carga_campo_castro;

-- Verificación de cantidades
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
JOIN parcela p
  ON p.id_parcela = la.id_parcela
WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'

UNION ALL

SELECT 'certificacion', COUNT(*)
FROM certificacion c
JOIN parcela p
  ON p.id_parcela = c.id_parcela
WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'

UNION ALL

SELECT 'tratamiento_fitosanitario', COUNT(*)
FROM tratamiento_fitosanitario tf
JOIN lote_agricola la
  ON la.id_lote = tf.id_lote
JOIN parcela p
  ON p.id_parcela = la.id_parcela
WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'

UNION ALL

SELECT 'inspeccion_pre_cosecha', COUNT(*)
FROM inspeccion_pre_cosecha ip
JOIN lote_agricola la
  ON la.id_lote = ip.id_lote
JOIN parcela p
  ON p.id_parcela = la.id_parcela
WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%';

-- Inspectores
SELECT
    COUNT(*) AS inspectores_catalogo,
    SUM(autorizado = TRUE) AS inspectores_autorizados,
    SUM(autorizado = FALSE) AS inspectores_no_autorizados
FROM inspector;

-- Estados de los lotes
SELECT
    la.estado,
    COUNT(*) AS cantidad
FROM lote_agricola la
JOIN parcela p
  ON p.id_parcela = la.id_parcela
WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'
GROUP BY la.estado
ORDER BY la.estado;

-- Validar inspectores autorizados
SELECT COUNT(*) AS inspecciones_con_inspector_no_autorizado
FROM inspeccion_pre_cosecha ip
JOIN inspector ins
  ON ins.id_inspector = ip.id_inspector
JOIN lote_agricola la
  ON la.id_lote = ip.id_lote
JOIN parcela p
  ON p.id_parcela = la.id_parcela
WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'
  AND ins.autorizado = FALSE;

-- Validar períodos de carencia
SELECT COUNT(*) AS tratamientos_con_carencia_inconsistente
FROM tratamiento_fitosanitario tf
JOIN producto_fitosanitario pf
  ON pf.id_producto_fitosanitario = tf.id_producto_fitosanitario
JOIN lote_agricola la
  ON la.id_lote = tf.id_lote
JOIN parcela p
  ON p.id_parcela = la.id_parcela
WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'
  AND tf.periodo_carencia_dias_aplicado <> pf.periodo_carencia_dias;

-- Validar certificaciones vigentes
SELECT COUNT(*) AS parcelas_sin_certificacion_vigente
FROM parcela p
WHERE p.codigo_catastral LIKE 'CASTRO-PAR-%'
  AND NOT EXISTS (
      SELECT 1
      FROM certificacion c
      WHERE c.id_parcela = p.id_parcela
        AND CURDATE() BETWEEN c.fecha_inicio AND c.fecha_fin
  );