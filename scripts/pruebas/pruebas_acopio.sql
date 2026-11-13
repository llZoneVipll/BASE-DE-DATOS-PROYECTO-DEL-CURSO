
-- =====================================================================
-- Archivo : pruebas/pruebas_acopio.sql
-- Dueño   : Bujaico
-- Contenido: Pruebas de Acopio, Calidad y Embarque.
-- =====================================================================

SET NAMES utf8mb4;
USE agro_trazabilidad;

CREATE TEMPORARY TABLE IF NOT EXISTS tmp_resultado_pruebas (
    n INT AUTO_INCREMENT PRIMARY KEY,
    modulo VARCHAR(10) NOT NULL,
    prueba VARCHAR(160) NOT NULL,
    resultado VARCHAR(4) NOT NULL,
    detalle VARCHAR(300) NULL
);

DROP TEMPORARY TABLE IF EXISTS tmp_pruebas_bujaico;

CREATE TEMPORARY TABLE tmp_pruebas_bujaico (
    prueba VARCHAR(160),
    resultado VARCHAR(4),
    detalle VARCHAR(300)
) ENGINE=MEMORY;

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_pruebas_acopio_bujaico $$

CREATE PROCEDURE sp_pruebas_acopio_bujaico()
BEGIN
    DECLARE v_tag VARCHAR(20);
    DECLARE v_tipo INT UNSIGNED;
    DECLARE v_banco INT UNSIGNED;
    DECLARE v_ubigeo CHAR(6);
    DECLARE v_calibre INT UNSIGNED;
    DECLARE v_exportacion INT UNSIGNED;
    DECLARE v_nacional INT UNSIGNED;
    DECLARE v_inspector BIGINT UNSIGNED;
    DECLARE v_fitosanitario INT UNSIGNED;
    DECLARE v_naviera INT UNSIGNED;
    DECLARE v_salida INT UNSIGNED;
    DECLARE v_destino INT UNSIGNED;

    DECLARE v_productor BIGINT UNSIGNED;
    DECLARE v_parcela BIGINT UNSIGNED;
    DECLARE v_lote BIGINT UNSIGNED;
    DECLARE v_certificacion BIGINT UNSIGNED;
    DECLARE v_inspeccion BIGINT UNSIGNED;
    DECLARE v_tratamiento BIGINT UNSIGNED;

    DECLARE v_ticket1 BIGINT UNSIGNED;
    DECLARE v_ticket2 BIGINT UNSIGNED;
    DECLARE v_ticket3 BIGINT UNSIGNED;
    DECLARE v_pallet1 BIGINT UNSIGNED;
    DECLARE v_pallet2 BIGINT UNSIGNED;
    DECLARE v_contenedor1 BIGINT UNSIGNED;
    DECLARE v_contenedor2 BIGINT UNSIGNED;
    DECLARE v_embarque BIGINT UNSIGNED;

    DECLARE v_error INT DEFAULT 0;
    DECLARE v_cantidad INT DEFAULT 0;
    DECLARE v_valor DECIMAL(14,4);
    DECLARE v_precio DECIMAL(12,4);

    SET v_tag = CONCAT('TST-BJ-', LEFT(REPLACE(UUID(), '-', ''), 9));

    SELECT MIN(id_tipo_asociacion) INTO v_tipo
    FROM tipo_asociacion;

    SELECT MIN(id_entidad_financiera) INTO v_banco
    FROM entidad_financiera;

    SELECT MIN(codigo_ubigeo) INTO v_ubigeo
    FROM ubigeo;

    SELECT MIN(id_inspector) INTO v_inspector
    FROM inspector
    WHERE autorizado = TRUE;

    SELECT MIN(id_producto_fitosanitario) INTO v_fitosanitario
    FROM producto_fitosanitario;

    SELECT MIN(id_naviera) INTO v_naviera
    FROM naviera;

    SELECT MIN(id_puerto) INTO v_salida
    FROM puerto
    WHERE pais = 'PE';

    SELECT MIN(id_puerto) INTO v_destino
    FROM puerto
    WHERE pais <> 'PE';

    SELECT MIN(id_destino_comercial) INTO v_exportacion
    FROM destino_comercial
    WHERE nombre = 'EXPORTACION';

    SELECT MIN(id_destino_comercial) INTO v_nacional
    FROM destino_comercial
    WHERE nombre = 'NACIONAL';

    SELECT MIN(id_calibre) INTO v_calibre
    FROM tarifa
    WHERE id_destino_comercial = v_exportacion
      AND vigencia_desde <= CURDATE()
      AND (vigencia_hasta IS NULL OR vigencia_hasta >= CURDATE());

    IF v_tipo IS NULL OR v_banco IS NULL OR v_ubigeo IS NULL
       OR v_inspector IS NULL OR v_fitosanitario IS NULL
       OR v_naviera IS NULL OR v_salida IS NULL OR v_destino IS NULL
       OR v_exportacion IS NULL OR v_nacional IS NULL
       OR v_calibre IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Faltan datos de 03_catalogos.sql';
    END IF;

    -- Datos de prueba

    INSERT INTO productor
        (tipo_documento, numero_documento, nombre_completo,
         id_tipo_asociacion, id_entidad_financiera, numero_cuenta)
    VALUES
        ('DNI', v_tag, 'Productor Prueba Bujaico',
         v_tipo, v_banco, 'CCI-PRUEBA');

    SET v_productor = LAST_INSERT_ID();

    INSERT INTO parcela
        (id_productor, codigo_catastral, codigo_ubigeo,
         sector_agricola, poligono)
    VALUES
        (v_productor, v_tag, v_ubigeo,
         'Sector Prueba',
         ST_GeomFromText(
             'POLYGON((-77.05 -12.05,-77.04 -12.05,-77.04 -12.04,-77.05 -12.04,-77.05 -12.05))',
             4326, 'axis-order=long-lat'
         ));

    SET v_parcela = LAST_INSERT_ID();

    INSERT INTO lote_agricola
        (id_parcela, codigo_lote, especie, fecha_siembra, estado)
    VALUES
        (v_parcela, 'L1', 'Palta', '2024-01-01', 'REGISTRADO');

    SET v_lote = LAST_INSERT_ID();

    INSERT INTO certificacion
        (id_parcela, nombre, codigo_certificacion,
         entidad_certificadora, fecha_inicio, fecha_fin)
    VALUES
        (v_parcela, 'Certificacion Prueba', v_tag,
         'Entidad Prueba',
         DATE_SUB(CURDATE(), INTERVAL 2 DAY),
         DATE_ADD(CURDATE(), INTERVAL 30 DAY));

    SET v_certificacion = LAST_INSERT_ID();

    INSERT INTO inspeccion_pre_cosecha
        (id_lote, id_inspector, fecha_inspeccion, resultado)
    VALUES
        (v_lote, v_inspector,
         DATE_SUB(NOW(), INTERVAL 1 DAY), 'APROBADA');

    SET v_inspeccion = LAST_INSERT_ID();

    UPDATE lote_agricola
    SET estado = 'HABILITADO_PARA_COSECHA'
    WHERE id_lote = v_lote;

    -- 1. Peso neto

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Peso neto correcto',
        IF(fn_peso_neto(100, 5, 10) = 85, 'PASS', 'FAIL'),
        '100 - 5 - 10 = 85'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        SET v_valor = fn_peso_neto(100, 80, 30);
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Peso con descarte excesivo',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar tara y descarte superiores al peso bruto'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        SET v_valor = fn_peso_neto(100, -5, 10);
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Peso con tara negativa',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar pesos negativos'
    );

    -- 2. Tarifas

    SET v_precio = fn_tarifa_kg(v_calibre, v_exportacion, CURDATE());

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Tarifa vigente',
        IF(v_precio > 0, 'PASS', 'FAIL'),
        'Debe devolver el precio por kilogramo'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        SET v_precio = fn_tarifa_kg(999999, 999999, CURDATE());
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Tarifa inexistente',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar una tarifa inexistente'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        SET v_precio = fn_tarifa_kg(v_calibre, v_exportacion, '2000-01-01');
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Tarifa fuera de vigencia',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar una fecha sin tarifa vigente'
    );

    -- 3. Tickets de acopio

    CALL sp_registrar_ticket(
        CONCAT(v_tag, '-T1'),
        v_lote, CURDATE(), NOW(), 'ABC-123'
    );

    SET v_ticket1 = LAST_INSERT_ID();

    SELECT COUNT(*) INTO v_cantidad
    FROM ticket_acopio
    WHERE id_ticket = v_ticket1;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Registro de ticket valido',
        IF(v_cantidad = 1, 'PASS', 'FAIL'),
        'Ticket registrado correctamente'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_registrar_ticket(
            CONCAT(v_tag, '-TX'),
            999999999, CURDATE(), NOW(), 'ABC-123'
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Ticket con lote inexistente',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar lotes inexistentes'
    );

    UPDATE certificacion
    SET fecha_fin = DATE_SUB(CURDATE(), INTERVAL 1 DAY)
    WHERE id_certificacion = v_certificacion;

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_registrar_ticket(
            CONCAT(v_tag, '-TC'),
            v_lote, CURDATE(), NOW(), 'ABC-123'
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Ticket sin certificacion vigente',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe impedir la recepcion sin certificacion vigente'
    );

    UPDATE certificacion
    SET fecha_fin = DATE_ADD(CURDATE(), INTERVAL 30 DAY)
    WHERE id_certificacion = v_certificacion;

    INSERT INTO tratamiento_fitosanitario
        (id_lote, id_producto_fitosanitario,
         fecha_aplicacion, periodo_carencia_dias_aplicado)
    VALUES
        (v_lote, v_fitosanitario,
         DATE_SUB(NOW(), INTERVAL 1 DAY), 7);

    SET v_tratamiento = LAST_INSERT_ID();

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_registrar_ticket(
            CONCAT(v_tag, '-TF'),
            v_lote, CURDATE(), NOW(), 'ABC-123'
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Ticket durante periodo de carencia',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe bloquear la cosecha durante el periodo de carencia'
    );

    DELETE FROM tratamiento_fitosanitario
    WHERE id_tratamiento = v_tratamiento;

    CALL sp_registrar_ticket(
        CONCAT(v_tag, '-T2'),
        v_lote, CURDATE(), NOW(), 'ABC-123'
    );

    SET v_ticket2 = LAST_INSERT_ID();

    CALL sp_registrar_ticket(
        CONCAT(v_tag, '-T3'),
        v_lote, CURDATE(), NOW(), 'ABC-123'
    );

    SET v_ticket3 = LAST_INSERT_ID();

    -- 4. Control de calidad

    CALL sp_registrar_control_calidad(
        v_ticket1, NOW(), 100, 5, 10,
        v_calibre, v_exportacion
    );

    SELECT peso_neto_pagable_kg INTO v_valor
    FROM control_calidad
    WHERE id_ticket = v_ticket1;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Control de calidad valido',
        IF(v_valor = 85, 'PASS', 'FAIL'),
        'El peso neto debe ser 85 kg'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_registrar_control_calidad(
            v_ticket2, NOW(), 100, 80, 30,
            v_calibre, v_nacional
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Control de calidad con pesos invalidos',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar un descarte excesivo'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_registrar_control_calidad(
            v_ticket1, NOW(), 100, 5, 10,
            v_calibre, v_exportacion
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Control de calidad duplicado',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'No debe permitir dos controles para un mismo ticket'
    );

    CALL sp_registrar_control_calidad(
        v_ticket2, NOW(), 100, 5, 10,
        v_calibre, v_nacional
    );

    -- 5. Liquidacion

    CALL sp_registrar_liquidacion(v_ticket1, NOW());

    SELECT COUNT(*) INTO v_cantidad
    FROM liquidacion
    WHERE id_ticket = v_ticket1;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Liquidacion valida',
        IF(v_cantidad = 1, 'PASS', 'FAIL'),
        'Debe registrar la liquidacion'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        CALL sp_registrar_liquidacion(v_ticket3, NOW());
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Liquidacion sin control de calidad',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar tickets sin control de calidad'
    );

    UPDATE productor
    SET id_entidad_financiera = NULL,
        numero_cuenta = NULL
    WHERE id_productor = v_productor;

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        CALL sp_registrar_liquidacion(v_ticket2, NOW());
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Liquidacion sin datos bancarios',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe impedir liquidaciones sin datos bancarios'
    );

    UPDATE productor
    SET id_entidad_financiera = v_banco,
        numero_cuenta = 'CCI-PRUEBA'
    WHERE id_productor = v_productor;

    -- 6. Pallets y trazabilidad

    CALL sp_armar_pallet(CONCAT(v_tag, '-P1'), NOW());
    SET v_pallet1 = LAST_INSERT_ID();

    CALL sp_armar_pallet(CONCAT(v_tag, '-P2'), NOW());
    SET v_pallet2 = LAST_INSERT_ID();

    SELECT COUNT(*) INTO v_cantidad
    FROM pallet
    WHERE id_pallet IN (v_pallet1, v_pallet2);

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Creacion de pallets',
        IF(v_cantidad = 2, 'PASS', 'FAIL'),
        'Se crean dos pallets con codigos diferentes'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        CALL sp_armar_pallet(CONCAT(v_tag, '-P1'), NOW());
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Codigo de pallet duplicado',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe impedir codigos de pallet duplicados'
    );

    CALL sp_agregar_ticket_pallet(
        v_ticket1, v_pallet1, 3, 30
    );

    SELECT cantidad_cajas INTO v_cantidad
    FROM pallet
    WHERE id_pallet = v_pallet1;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Asignacion de ticket a pallet',
        IF(v_cantidad = 3, 'PASS', 'FAIL'),
        'El trigger debe actualizar la cantidad de cajas'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_agregar_ticket_pallet(
            v_ticket1, v_pallet2, 10, 100
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Peso excesivo al armar pallet',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'El peso asignado no debe superar el neto pagable'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_agregar_ticket_pallet(
            v_ticket2, v_pallet2, 1, 10
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Pallet con ticket nacional',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Solo se permite paletizar fruta de exportacion'
    );

    -- 7. Consolidacion

    INSERT INTO contenedor_maritimo (numero_contenedor)
    VALUES (CONCAT(v_tag, '-C1'));

    SET v_contenedor1 = LAST_INSERT_ID();

    INSERT INTO contenedor_maritimo (numero_contenedor)
    VALUES (CONCAT(v_tag, '-C2'));

    SET v_contenedor2 = LAST_INSERT_ID();

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_consolidar_pallet(
            v_pallet2, v_contenedor1
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Consolidacion de pallet vacio',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar pallets sin tickets'
    );

    CALL sp_consolidar_pallet(
        v_pallet1, v_contenedor1
    );

    SELECT COUNT(*) INTO v_cantidad
    FROM consolidacion
    WHERE id_pallet = v_pallet1
      AND id_contenedor = v_contenedor1;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Consolidacion valida',
        IF(v_cantidad = 1, 'PASS', 'FAIL'),
        'Pallet asignado al contenedor'
    );

    CALL sp_agregar_ticket_pallet(
        v_ticket1, v_pallet2, 2, 20
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_consolidar_pallet(
            v_pallet2, 999999999
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Consolidacion con contenedor inexistente',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar contenedores inexistentes'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_consolidar_pallet(
            v_pallet1, v_contenedor2
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Relacion N:M pallet y contenedor',
        IF(v_error = 0, 'PASS', 'FAIL'),
        'Comprueba si el mismo pallet puede asociarse a dos contenedores'
    );

    -- 8. Actualizacion de cajas

    UPDATE ticket_pallet
    SET cantidad_cajas = 4
    WHERE id_ticket = v_ticket1
      AND id_pallet = v_pallet2;

    SELECT cantidad_cajas INTO v_cantidad
    FROM pallet
    WHERE id_pallet = v_pallet2;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Actualizacion de cantidad de cajas',
        IF(v_cantidad = 4, 'PASS', 'FAIL'),
        'El trigger actualiza la cantidad de cajas'
    );

    DELETE FROM ticket_pallet
    WHERE id_ticket = v_ticket1
      AND id_pallet = v_pallet2;

    SELECT cantidad_cajas INTO v_cantidad
    FROM pallet
    WHERE id_pallet = v_pallet2;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Eliminacion de cajas del pallet',
        IF(v_cantidad = 0, 'PASS', 'FAIL'),
        'El trigger descuenta las cajas eliminadas'
    );

    -- 9. Embarque y despacho

    INSERT INTO embarque_maritimo
        (codigo_embarque, id_naviera,
         id_puerto_salida, id_puerto_destino,
         temperatura_min_c, temperatura_max_c,
         fecha_programada)
    VALUES
        (CONCAT(v_tag, '-E1'), v_naviera,
         v_salida, v_destino, 4, 8, NOW());

    SET v_embarque = LAST_INSERT_ID();

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        CALL sp_despachar_contenedor(v_contenedor1);
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Despacho sin embarque asignado',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe impedir el despacho sin embarque'
    );

    CALL sp_asignar_contenedor_embarque(
        v_contenedor1, v_embarque
    );

    SELECT COUNT(*) INTO v_cantidad
    FROM contenedor_maritimo
    WHERE id_contenedor = v_contenedor1
      AND id_embarque = v_embarque;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Asignacion de contenedor a embarque',
        IF(v_cantidad = 1, 'PASS', 'FAIL'),
        'Contenedor asociado correctamente'
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;

        CALL sp_asignar_contenedor_embarque(
            v_contenedor2, 999999999
        );
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Asignacion a embarque inexistente',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe rechazar embarques inexistentes'
    );

    UPDATE contenedor_maritimo
    SET estado = 'EN_CARGA'
    WHERE id_contenedor = v_contenedor2;

    CALL sp_asignar_contenedor_embarque(
        v_contenedor2, v_embarque
    );

    SET v_error = 0;

    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_error = 1;
        CALL sp_despachar_contenedor(v_contenedor2);
    END;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Despacho de contenedor sin pallets',
        IF(v_error = 1, 'PASS', 'FAIL'),
        'Debe impedir despachar contenedores vacios'
    );

    CALL sp_despachar_contenedor(v_contenedor1);

    SELECT COUNT(*) INTO v_cantidad
    FROM contenedor_maritimo
    WHERE id_contenedor = v_contenedor1
      AND estado = 'DESPACHADO';

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Despacho valido',
        IF(v_cantidad = 1, 'PASS', 'FAIL'),
        'Contenedor despachado correctamente'
    );

    SELECT COUNT(*) INTO v_cantidad
    FROM pallet
    WHERE id_pallet = v_pallet1
      AND estado = 'DESPACHADO';

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Actualizacion de estado del pallet',
        IF(v_cantidad = 1, 'PASS', 'FAIL'),
        'El pallet debe quedar despachado'
    );

    -- 10. Vistas

    SELECT COUNT(*) INTO v_cantidad
    FROM vw_trazabilidad_reversa
    WHERE codigo_pallet = CONCAT(v_tag, '-P1')
      AND numero_documento = v_tag
      AND codigo_ticket = CONCAT(v_tag, '-T1');

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Vista de trazabilidad reversa',
        IF(v_cantidad >= 1, 'PASS', 'FAIL'),
        'Debe mostrar el productor y ticket de origen'
    );

    SELECT COUNT(*) INTO v_cantidad
    FROM vw_liquidacion_productor
    WHERE id_productor = v_productor
      AND tickets_liquidados = 1
      AND peso_total_kg = 85;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Vista de liquidacion por productor',
        IF(v_cantidad = 1, 'PASS', 'FAIL'),
        'Debe mostrar el peso y liquidacion del productor'
    );

    -- 11. Limpieza de datos

    DELETE FROM consolidacion
    WHERE id_contenedor IN (v_contenedor1, v_contenedor2);

    DELETE FROM ticket_pallet
    WHERE id_pallet IN (v_pallet1, v_pallet2);

    DELETE FROM pallet
    WHERE id_pallet IN (v_pallet1, v_pallet2);

    DELETE FROM contenedor_maritimo
    WHERE id_contenedor IN (v_contenedor1, v_contenedor2);

    DELETE FROM embarque_maritimo
    WHERE id_embarque = v_embarque;

    DELETE FROM liquidacion
    WHERE id_ticket IN (v_ticket1, v_ticket2, v_ticket3);

    DELETE FROM control_calidad
    WHERE id_ticket IN (v_ticket1, v_ticket2, v_ticket3);

    DELETE FROM ticket_acopio
    WHERE id_ticket IN (v_ticket1, v_ticket2, v_ticket3);

    DELETE FROM inspeccion_pre_cosecha
    WHERE id_inspeccion = v_inspeccion;

    DELETE FROM tratamiento_fitosanitario
    WHERE id_lote = v_lote;

    DELETE FROM lote_agricola
    WHERE id_lote = v_lote;

    DELETE FROM certificacion
    WHERE id_certificacion = v_certificacion;

    DELETE FROM parcela
    WHERE id_parcela = v_parcela;

    DELETE FROM productor
    WHERE id_productor = v_productor;

    SELECT COUNT(*) INTO v_cantidad
    FROM productor
    WHERE numero_documento = v_tag;

    INSERT INTO tmp_pruebas_bujaico
    VALUES (
        'Limpieza de datos de prueba',
        IF(v_cantidad = 0, 'PASS', 'FAIL'),
        'No deben quedar datos del productor de prueba'
    );

END $$

DELIMITER ;

CALL sp_pruebas_acopio_bujaico();

INSERT INTO tmp_resultado_pruebas
    (modulo, prueba, resultado, detalle)
SELECT
    'ACOPIO', prueba, resultado, detalle
FROM tmp_pruebas_bujaico;

SELECT prueba, resultado, detalle
FROM tmp_resultado_pruebas
WHERE modulo = 'ACOPIO'
ORDER BY n;

DROP PROCEDURE IF EXISTS sp_pruebas_acopio_bujaico;
DROP TEMPORARY TABLE IF EXISTS tmp_pruebas_bujaico;
