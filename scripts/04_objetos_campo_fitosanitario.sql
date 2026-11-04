-- ---------------------------------------------------------------------
-- Modulo: Campo y Control Fitosanitario
-- Archivo: 04_objetos_campo_fitosanitario.sql
-- Autor: Pacara
-- ---------------------------------------------------------------------

DELIMITER //

-- Función para calcular la fecha de liberación sumando el período de carencia
DROP FUNCTION IF EXISTS fn_calcular_fecha_liberacion//
CREATE FUNCTION fn_calcular_fecha_liberacion(
    p_fecha_aplicacion DATETIME, 
    p_id_producto INT UNSIGNED
)
RETURNS DATETIME
DETERMINISTIC
BEGIN
    DECLARE v_dias INT UNSIGNED;
    
    SELECT periodo_carencia_dias INTO v_dias
    FROM producto_fitosanitario
    WHERE id_producto_fitosanitario = p_id_producto;
    
    RETURN DATE_ADD(p_fecha_aplicacion, INTERVAL COALESCE(v_dias, 0) DAY);
END//

-- Procedimiento genérico para Productor
DROP PROCEDURE IF EXISTS sp_mantenimiento_productor//
CREATE PROCEDURE sp_mantenimiento_productor(
    IN p_accion VARCHAR(10),
    INOUT p_id_productor BIGINT UNSIGNED,
    IN p_tipo_doc VARCHAR(15),
    IN p_num_doc VARCHAR(20),
    IN p_nombre VARCHAR(160),
    IN p_tel VARCHAR(20),
    IN p_id_asoc INT UNSIGNED,
    IN p_id_banco INT UNSIGNED,
    IN p_num_cuenta VARCHAR(34),
    IN p_activo BOOLEAN
)
BEGIN
    IF p_accion = 'INSERT' THEN
        INSERT INTO productor (tipo_documento, numero_documento, nombre_completo, telefono, id_tipo_asociacion, id_entidad_financiera, numero_cuenta, activo)
        VALUES (p_tipo_doc, p_num_doc, p_nombre, p_tel, p_id_asoc, p_id_banco, p_num_cuenta, COALESCE(p_activo, TRUE));
        SET p_id_productor = LAST_INSERT_ID();
    ELSEIF p_accion = 'UPDATE' THEN
        UPDATE productor 
        SET tipo_documento = p_tipo_doc, numero_documento = p_num_doc, nombre_completo = p_nombre, 
            telefono = p_tel, id_tipo_asociacion = p_id_asoc, id_entidad_financiera = p_id_banco, 
            numero_cuenta = p_num_cuenta, activo = p_activo
        WHERE id_productor = p_id_productor;
    END IF;
END//

-- Procedimiento para Parcela
DROP PROCEDURE IF EXISTS sp_mantenimiento_parcela//
CREATE PROCEDURE sp_mantenimiento_parcela(
    IN p_accion VARCHAR(10),
    INOUT p_id_parcela BIGINT UNSIGNED,
    IN p_id_productor BIGINT UNSIGNED,
    IN p_catastral VARCHAR(60),
    IN p_ubigeo CHAR(6),
    IN p_sector VARCHAR(120),
    IN p_poligono POLYGON
)
BEGIN
    IF p_accion = 'INSERT' THEN
        INSERT INTO parcela (id_productor, codigo_catastral, codigo_ubigeo, sector_agricola, poligono)
        VALUES (p_id_productor, p_catastral, p_ubigeo, p_sector, p_poligono);
        SET p_id_parcela = LAST_INSERT_ID();
    ELSEIF p_accion = 'UPDATE' THEN
        UPDATE parcela 
        SET id_productor = p_id_productor, codigo_catastral = p_catastral, 
            codigo_ubigeo = p_ubigeo, sector_agricola = p_sector, poligono = p_poligono
        WHERE id_parcela = p_id_parcela;
    END IF;
END//

-- Procedimiento para Lote Agrícola
DROP PROCEDURE IF EXISTS sp_mantenimiento_lote//
CREATE PROCEDURE sp_mantenimiento_lote(
    IN p_accion VARCHAR(10),
    INOUT p_id_lote BIGINT UNSIGNED,
    IN p_id_parcela BIGINT UNSIGNED,
    IN p_cod_lote VARCHAR(40),
    IN p_especie VARCHAR(80),
    IN p_variedad VARCHAR(80),
    IN p_f_siembra DATE,
    IN p_f_poda DATE,
    IN p_rendimiento DECIMAL(12,3),
    IN p_estado VARCHAR(30)
)
BEGIN
    IF p_accion = 'INSERT' THEN
        INSERT INTO lote_agricola (id_parcela, codigo_lote, especie, variedad, fecha_siembra, fecha_ultima_poda, rendimiento_estimado_tn, estado)
        VALUES (p_id_parcela, p_cod_lote, p_especie, p_variedad, p_f_siembra, p_f_poda, p_rendimiento, COALESCE(p_estado, 'REGISTRADO'));
        SET p_id_lote = LAST_INSERT_ID();
    ELSEIF p_accion = 'UPDATE' THEN
        UPDATE lote_agricola 
        SET id_parcela = p_id_parcela, codigo_lote = p_cod_lote, especie = p_especie, 
            variedad = p_variedad, fecha_siembra = p_f_siembra, fecha_ultima_poda = p_f_poda, 
            rendimiento_estimado_tn = p_rendimiento, estado = p_estado
        WHERE id_lote = p_id_lote;
    END IF;
END//

-- Procedimiento para Certificación
DROP PROCEDURE IF EXISTS sp_mantenimiento_certificacion//
CREATE PROCEDURE sp_mantenimiento_certificacion(
    IN p_accion VARCHAR(10),
    INOUT p_id_cert BIGINT UNSIGNED,
    IN p_id_parcela BIGINT UNSIGNED,
    IN p_nombre VARCHAR(100),
    IN p_cod_cert VARCHAR(80),
    IN p_entidad VARCHAR(120),
    IN p_f_inicio DATE,
    IN p_f_fin DATE
)
BEGIN
    IF p_accion = 'INSERT' THEN
        INSERT INTO certificacion (id_parcela, nombre, codigo_certificacion, entidad_certificadora, fecha_inicio, fecha_fin)
        VALUES (p_id_parcela, p_nombre, p_cod_cert, p_entidad, p_f_inicio, p_f_fin);
        SET p_id_cert = LAST_INSERT_ID();
    ELSEIF p_accion = 'UPDATE' THEN
        UPDATE certificacion 
        SET id_parcela = p_id_parcela, nombre = p_nombre, codigo_certificacion = p_cod_cert, 
            entidad_certificadora = p_entidad, fecha_inicio = p_f_inicio, fecha_fin = p_f_fin
        WHERE id_certificacion = p_id_cert;
    END IF;
END//

-- Registro de Tratamiento Fitosanitario
DROP PROCEDURE IF EXISTS sp_registrar_tratamiento//
CREATE PROCEDURE sp_registrar_tratamiento(
    IN p_id_lote BIGINT UNSIGNED,
    IN p_id_producto INT UNSIGNED,
    IN p_f_apli DATETIME,
    IN p_obs VARCHAR(500),
    OUT p_id_tratamiento BIGINT UNSIGNED
)
BEGIN
    DECLARE v_carencia INT UNSIGNED;
    
    SELECT periodo_carencia_dias INTO v_carencia
    FROM producto_fitosanitario
    WHERE id_producto_fitosanitario = p_id_producto;
    
    INSERT INTO tratamiento_fitosanitario (id_lote, id_producto_fitosanitario, fecha_aplicacion, periodo_carencia_dias_aplicado, observaciones)
    VALUES (p_id_lote, p_id_producto, p_f_apli, COALESCE(v_carencia, 0), p_obs);
    
    SET p_id_tratamiento = LAST_INSERT_ID();
END//

-- Procedimiento para Inspección Pre-Cosecha
DROP PROCEDURE IF EXISTS sp_mantenimiento_inspeccion//
CREATE PROCEDURE sp_mantenimiento_inspeccion(
    IN p_accion VARCHAR(10),
    INOUT p_id_insp BIGINT UNSIGNED,
    IN p_id_lote BIGINT UNSIGNED,
    IN p_id_inspector BIGINT UNSIGNED,
    IN p_f_insp DATETIME,
    IN p_resultado VARCHAR(20),
    IN p_obs VARCHAR(500)
)
BEGIN
    IF p_accion = 'INSERT' THEN
        INSERT INTO inspeccion_pre_cosecha (id_lote, id_inspector, fecha_inspeccion, resultado, observaciones)
        VALUES (p_id_lote, p_id_inspector, p_f_insp, COALESCE(p_resultado, 'PENDIENTE'), p_obs);
        SET p_id_insp = LAST_INSERT_ID();
    ELSEIF p_accion = 'UPDATE' THEN
        UPDATE inspeccion_pre_cosecha 
        SET id_lote = p_id_lote, id_inspector = p_id_inspector, fecha_inspeccion = p_f_insp, 
            resultado = p_resultado, observaciones = p_obs
        WHERE id_inspeccion = p_id_insp;
    END IF;
END//

-- Trigger para validar que el lote cumpla requisitos antes de habilitarlo para cosecha
DROP TRIGGER IF EXISTS trg_valida_habilitacion_lote//
CREATE TRIGGER trg_valida_habilitacion_lote
BEFORE UPDATE ON lote_agricola
FOR EACH ROW
BEGIN
    DECLARE v_cert INT;
    DECLARE v_insp INT;
    DECLARE v_trat INT;
    
    IF NEW.estado = 'HABILITADO_PARA_COSECHA' AND OLD.estado <> 'HABILITADO_PARA_COSECHA' THEN
        
        -- 1. Validar certificación vigente en la parcela
        SELECT COUNT(*) INTO v_cert
        FROM certificacion
        WHERE id_parcela = NEW.id_parcela AND NOW() BETWEEN fecha_inicio AND fecha_fin;
        
        IF v_cert = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: La parcela no tiene certificación vigente.';
        END IF;
        
        -- 2. Validar inspección aprobada
        SELECT COUNT(*) INTO v_insp
        FROM inspeccion_pre_cosecha
        WHERE id_lote = NEW.id_lote AND resultado = 'APROBADA';
        
        IF v_insp = 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: El lote no cuenta con inspección aprobada.';
        END IF;
        
        -- 3. Validar período de carencia de plaguicidas
        SELECT COUNT(*) INTO v_trat
        FROM tratamiento_fitosanitario
        WHERE id_lote = NEW.id_lote AND NOW() < DATE_ADD(fecha_aplicacion, INTERVAL periodo_carencia_dias_aplicado DAY);
        
        IF v_trat > 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: El lote está en período de carencia activo.';
        END IF;
        
    END IF;
END//

-- Vistas requeridas
DROP VIEW IF EXISTS vw_certificaciones_vigentes_o_vencer//
CREATE VIEW vw_certificaciones_vigentes_o_vencer AS
SELECT 
    c.id_certificacion, c.id_parcela, p.codigo_catastral, pr.id_productor, pr.nombre_completo AS productor,
    c.nombre AS certificacion, c.codigo_certificacion, c.entidad_certificadora, c.fecha_inicio, c.fecha_fin,
    DATEDIFF(c.fecha_fin, NOW()) AS dias_para_vencer,
    CASE 
        WHEN NOW() > c.fecha_fin THEN 'VENCIDA'
        WHEN DATEDIFF(c.fecha_fin, NOW()) <= 30 THEN 'POR_VENCER'
        ELSE 'VIGENTE'
    END AS estado_vigencia
FROM certificacion c
JOIN parcela p ON c.id_parcela = p.id_parcela
JOIN productor pr ON p.id_productor = pr.id_productor;

DROP VIEW IF EXISTS vw_lotes_habilitables//
CREATE VIEW vw_lotes_habilitables AS
SELECT 
    l.id_lote, l.codigo_lote, l.id_parcela, p.codigo_catastral, pr.id_productor, pr.nombre_completo AS productor,
    l.especie, l.variedad, l.estado
FROM lote_agricola l
JOIN parcela p ON l.id_parcela = p.id_parcela
JOIN productor pr ON p.id_productor = pr.id_productor
WHERE l.estado = 'HABILITADO_PARA_COSECHA';

DELIMITER ;

-- =====================================================================
-- CASOS DE PRUEBA: MÓDULO DE CAMPO Y CONTROL FITOSANITARIO (pruebas_campo)
-- =====================================================================

-- PRUEBA 1: Verificar el cálculo de la función fn_calcular_fecha_liberacion
-- (Prueba con una aplicación efectuada hoy para un plaguicida de id = 1)
SELECT fn_calcular_fecha_liberacion(NOW(), 1) AS fecha_liberacion_esperada;

-- PRUEBA 2: Consulta de prueba para la vista de certificaciones vigentes / por vencer
SELECT * FROM vw_certificaciones_vigentes_o_vencer;

-- PRUEBA 3: Consulta de prueba para la vista de lotes habilitables
SELECT * FROM vw_lotes_habilitables;

-- PRUEBA 4: Intento de actualización de estado para validar la activación del trigger trg_valida_habilitacion_lote
-- Nota: Si el lote id 1 no cumple con la certificación vigente, inspección aprobada o carencia, lanzará un error SQLSTATE '45000'.
-- UPDATE lote_agricola SET estado = 'HABILITADO_PARA_COSECHA' WHERE id_lote = 1;