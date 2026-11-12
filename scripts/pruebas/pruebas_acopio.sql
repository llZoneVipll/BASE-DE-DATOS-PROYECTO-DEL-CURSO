-- =====================================================================
-- Archivo : pruebas/pruebas_acopio.sql
-- Dueño   : Bujaico
-- Contenido: Casos de prueba de las reglas de Acopio, Calidad y Embarque
--            (peso neto, tarifa, ticket, liquidación, pallets, consolidación,
--            embarque con varios contenedores, despacho y vistas), segun el
--            diagrama conceptual (Ticket N:M Pallet, Consolidacion, Embarque 1:N).
-- Cómo se usa: corre solo o desde 08_pruebas.sql. Cada caso termina en PASS
--            o FAIL. Los datos de prueba llevan el prefijo TST-A y se borran
--            al terminar (los procedimientos de acopio confirman sus propias
--            transacciones, por eso la limpieza es con DELETE y no con
--            ROLLBACK). No se crean catálogos falsos: se usan los de 03.
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

DELIMITER //

DROP PROCEDURE IF EXISTS sp_tmp_pruebas_acopio//
CREATE PROCEDURE sp_tmp_pruebas_acopio()
BEGIN
    DECLARE v_err INT DEFAULT 0;
    DECLARE v_msg VARCHAR(300) DEFAULT NULL;
    DECLARE v_prod BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_parc BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_loteA BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_loteB BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_cert BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_insp BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_inspector BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_cal INT UNSIGNED DEFAULT NULL;
    DECLARE v_dest INT UNSIGNED DEFAULT NULL;
    DECLARE v_naviera INT UNSIGNED DEFAULT NULL;
    DECLARE v_dest_nac INT UNSIGNED DEFAULT NULL;
    DECLARE v_prodfito INT UNSIGNED DEFAULT NULL;
    DECLARE v_banco INT UNSIGNED DEFAULT NULL;
    DECLARE v_ticket4 BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_trat BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_ticket3 BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_emb BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_ps INT UNSIGNED DEFAULT NULL;
    DECLARE v_pd INT UNSIGNED DEFAULT NULL;
    DECLARE v_precio DECIMAL(12,4) DEFAULT NULL;
    DECLARE v_ticket BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_ticket2 BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_caja BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_pallet BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_pallet2 BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_cont1 BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_cont2 BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_estado VARCHAR(30) DEFAULT NULL;
    DECLARE v_estado2 VARCHAR(30) DEFAULT NULL;
    DECLARE v_neto DECIMAL(12,3) DEFAULT NULL;
    DECLARE v_importe DECIMAL(14,2) DEFAULT NULL;
    DECLARE v_n INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        SET v_err = 1;
    END;

    -- Limpieza previa
    DELETE cs FROM consolidacion cs JOIN pallet p ON p.id_pallet = cs.id_pallet WHERE p.codigo_pallet LIKE 'TST-A-%';
    DELETE tp FROM ticket_pallet tp JOIN ticket_acopio t ON t.id_ticket = tp.id_ticket WHERE t.codigo_ticket LIKE 'TST-A-%';
    DELETE FROM pallet WHERE codigo_pallet LIKE 'TST-A-%';
    DELETE FROM contenedor_maritimo WHERE numero_contenedor LIKE 'TST-A-%';
    DELETE FROM embarque_maritimo WHERE codigo_embarque LIKE 'TST-A-%';
    DELETE li FROM liquidacion li JOIN ticket_acopio t ON t.id_ticket = li.id_ticket WHERE t.codigo_ticket LIKE 'TST-A-%';
    DELETE cc FROM control_calidad cc JOIN ticket_acopio t ON t.id_ticket = cc.id_ticket WHERE t.codigo_ticket LIKE 'TST-A-%';
    DELETE FROM ticket_acopio WHERE codigo_ticket LIKE 'TST-A-%';
    DELETE i FROM inspeccion_pre_cosecha i JOIN lote_agricola l ON l.id_lote = i.id_lote WHERE l.codigo_lote LIKE 'TST-A-%';
    DELETE tr FROM tratamiento_fitosanitario tr JOIN lote_agricola l ON l.id_lote = tr.id_lote WHERE l.codigo_lote LIKE 'TST-A-%';
    DELETE FROM lote_agricola WHERE codigo_lote LIKE 'TST-A-%';
    DELETE FROM certificacion WHERE codigo_certificacion LIKE 'TST-A-%';
    DELETE FROM parcela WHERE codigo_catastral LIKE 'TST-A-%';
    DELETE FROM productor WHERE numero_documento LIKE 'TST-A-%';

    -- Datos base (catálogos de 03) y lote habilitado por el camino correcto
    SELECT id_inspector INTO v_inspector FROM inspector WHERE autorizado = TRUE ORDER BY id_inspector LIMIT 1;
    SELECT id_calibre INTO v_cal FROM calibre WHERE codigo REGEXP '^[0-9]+$' ORDER BY CAST(codigo AS UNSIGNED) LIMIT 1;
    SELECT id_destino_comercial INTO v_dest FROM destino_comercial WHERE nombre = 'EXPORTACION';
    SELECT id_destino_comercial INTO v_dest_nac FROM destino_comercial WHERE nombre = 'NACIONAL';
    SELECT id_naviera INTO v_naviera FROM naviera ORDER BY id_naviera LIMIT 1;
    SELECT id_puerto INTO v_ps FROM puerto WHERE nombre = 'Callao' AND pais = 'PE';
    SELECT id_puerto INTO v_pd FROM puerto WHERE nombre = 'Rotterdam' AND pais = 'NL';
    SELECT precio_kg_pen INTO v_precio FROM tarifa
    WHERE id_calibre = v_cal AND id_destino_comercial = v_dest AND vigencia_desde <= CURDATE()
      AND (vigencia_hasta IS NULL OR vigencia_hasta >= CURDATE())
    ORDER BY vigencia_desde DESC, id_tarifa DESC LIMIT 1;

    SELECT MIN(id_entidad_financiera) INTO v_banco FROM entidad_financiera;
    SELECT id_producto_fitosanitario INTO v_prodfito FROM producto_fitosanitario
    WHERE periodo_carencia_dias >= 7 ORDER BY id_producto_fitosanitario LIMIT 1;
    INSERT INTO productor (tipo_documento, numero_documento, nombre_completo, id_tipo_asociacion, id_entidad_financiera, numero_cuenta)
    VALUES ('DNI', 'TST-A-0001', 'Productor TST Acopio', (SELECT MIN(id_tipo_asociacion) FROM tipo_asociacion), v_banco, 'TST-CTA-0001');
    SET v_prod = LAST_INSERT_ID();
    INSERT INTO parcela (id_productor, codigo_catastral, codigo_ubigeo, sector_agricola, poligono)
    VALUES (v_prod, 'TST-A-PAR-001', '131201', 'Sector TST',
            ST_GeomFromText('POLYGON((-78.70 -8.40,-78.69 -8.40,-78.69 -8.41,-78.70 -8.41,-78.70 -8.40))', 4326, 'axis-order=long-lat'));
    SET v_parc = LAST_INSERT_ID();
    INSERT INTO certificacion (id_parcela, nombre, codigo_certificacion, entidad_certificadora, fecha_inicio, fecha_fin)
    VALUES (v_parc, 'GLOBALG.A.P.', 'TST-A-CERT-1', 'Certificadora TST', DATE_SUB(CURDATE(), INTERVAL 100 DAY), DATE_ADD(CURDATE(), INTERVAL 265 DAY));
    INSERT INTO lote_agricola (id_parcela, codigo_lote, especie, fecha_siembra)
    VALUES (v_parc, 'TST-A-LA', 'Palta', '2024-01-01');
    SET v_loteA = LAST_INSERT_ID();
    INSERT INTO lote_agricola (id_parcela, codigo_lote, especie, fecha_siembra)
    VALUES (v_parc, 'TST-A-LB', 'Palta', '2024-01-01');
    SET v_loteB = LAST_INSERT_ID();
    INSERT INTO inspeccion_pre_cosecha (id_lote, id_inspector, fecha_inspeccion, resultado)
    VALUES (v_loteA, v_inspector, NOW(), 'APROBADA');
    UPDATE lote_agricola SET estado = 'HABILITADO_PARA_COSECHA' WHERE id_lote = v_loteA;

    -- A1. Peso neto = bruto - tara - descarte
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A1 fn_peso_neto(100, 5, 10) = 85',
            IF(fn_peso_neto(100, 5, 10) = 85, 'PASS', 'FAIL'), CAST(fn_peso_neto(100, 5, 10) AS CHAR));

    -- A2. Pesos inválidos se rechazan
    SET v_err = 0, v_msg = NULL;
    SET v_neto = fn_peso_neto(100, 80, 30);
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A2 fn_peso_neto rechaza tara + descarte mayor al bruto',
            IF(v_err = 1 AND v_msg LIKE '%Pesos%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A3. Tarifa vigente según calibre y destino
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A3 fn_tarifa_kg devuelve la tarifa vigente',
            IF(fn_tarifa_kg(v_cal, v_dest, CURDATE()) = v_precio, 'PASS', 'FAIL'), CONCAT('S/ ', v_precio, ' por kg'));

    -- A4. Sin tarifa vigente se rechaza
    SET v_err = 0, v_msg = NULL;
    SET v_precio = fn_tarifa_kg(0, 0, CURDATE());
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A4 fn_tarifa_kg rechaza calibre/destino sin tarifa',
            IF(v_err = 1 AND v_msg LIKE '%tarifa%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));
    SELECT precio_kg_pen INTO v_precio FROM tarifa
    WHERE id_calibre = v_cal AND id_destino_comercial = v_dest AND vigencia_desde <= CURDATE()
      AND (vigencia_hasta IS NULL OR vigencia_hasta >= CURDATE())
    ORDER BY vigencia_desde DESC, id_tarifa DESC LIMIT 1;

    -- A5. No se registra ticket de un lote no habilitado
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_ticket('TST-A-T0', v_loteB, CURDATE(), NOW(), 'TST-000');
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A5 No se registra ticket de un lote no habilitado',
            IF(v_err = 1 AND v_msg LIKE '%no habilitado%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A6. Ticket de un lote habilitado
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_ticket('TST-A-T1', v_loteA, CURDATE(), NOW(), 'TST-001');
    SELECT id_ticket, estado INTO v_ticket, v_estado FROM ticket_acopio WHERE codigo_ticket = 'TST-A-T1';
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A6 Ticket de un lote habilitado queda RECIBIDO',
            IF(v_err = 0 AND v_estado = 'RECIBIDO', 'PASS', 'FAIL'), COALESCE(v_msg, v_estado));

    -- A7. Control de calidad: ticket EVALUADO y peso neto pagable calculado
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_control_calidad(v_ticket, NOW(), 100, 5, 10, v_cal, v_dest);
    SELECT estado INTO v_estado FROM ticket_acopio WHERE id_ticket = v_ticket;
    SELECT peso_neto_pagable_kg INTO v_neto FROM control_calidad WHERE id_ticket = v_ticket;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A7 Control de calidad: ticket EVALUADO y peso neto pagable = 85',
            IF(v_err = 0 AND v_estado = 'EVALUADO' AND v_neto = 85, 'PASS', 'FAIL'),
            CONCAT(COALESCE(v_estado, '-'), ', neto ', COALESCE(v_neto, -1)));

    -- A8. Liquidación con la tarifa vigente
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_liquidacion(v_ticket, NOW());
    SELECT estado INTO v_estado FROM ticket_acopio WHERE id_ticket = v_ticket;
    SELECT importe_total_pen INTO v_importe FROM liquidacion WHERE id_ticket = v_ticket;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A8 Liquidación: ticket LIQUIDADO e importe = neto x tarifa',
            IF(v_err = 0 AND v_estado = 'LIQUIDADO' AND v_importe = ROUND(85 * v_precio, 2), 'PASS', 'FAIL'),
            CONCAT('importe S/ ', COALESCE(v_importe, -1)));

    -- A9. No se liquida un ticket sin control de calidad
    INSERT INTO ticket_acopio (codigo_ticket, id_lote, fecha_cosecha, fecha_recepcion)
    VALUES ('TST-A-T2', v_loteA, CURDATE(), NOW());
    SET v_ticket2 = LAST_INSERT_ID();
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_liquidacion(v_ticket2, NOW());
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A9 No se liquida un ticket sin control de calidad',
            IF(v_err = 1 AND v_msg LIKE '%sin control%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A10. Control de calidad con tara + descarte mayor al bruto se rechaza
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_control_calidad(v_ticket2, NOW(), 100, 80, 30, v_cal, v_dest);
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A10 Control de calidad rechaza tara + descarte mayor al bruto',
            IF(v_err = 1 AND v_msg LIKE '%ck_control_calidad_pesos%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A11. Un pallet reúne fruta de un ticket (Ticket N:M Pallet): la cantidad de cajas la calculan los triggers
    SET v_err = 0, v_msg = NULL;
    CALL sp_armar_pallet('TST-A-PAL1', NOW());
    SELECT id_pallet INTO v_pallet FROM pallet WHERE codigo_pallet = 'TST-A-PAL1';
    CALL sp_agregar_ticket_pallet(v_ticket, v_pallet, 9, 85);
    SELECT cantidad_cajas INTO v_n FROM pallet WHERE id_pallet = v_pallet;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A11 El pallet registra la fruta del ticket y su cantidad de cajas',
            IF(v_err = 0 AND v_n = 9 AND EXISTS (SELECT 1 FROM ticket_pallet WHERE id_ticket = v_ticket AND id_pallet = v_pallet), 'PASS', 'FAIL'),
            COALESCE(v_msg, CONCAT('cajas del pallet: ', v_n)));

    -- A12. No se asigna a pallets más peso que el neto pagable del ticket
    SET v_err = 0, v_msg = NULL;
    CALL sp_agregar_ticket_pallet(v_ticket, v_pallet, 1, 10);
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A12 No se asigna a pallets más peso que el neto pagable del ticket',
            IF(v_err = 1 AND v_msg LIKE '%supera%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A13. Solo la fruta de exportación se paletiza
    INSERT INTO ticket_acopio (codigo_ticket, id_lote, fecha_cosecha, fecha_recepcion)
    VALUES ('TST-A-T3', v_loteA, CURDATE(), NOW());
    SET v_ticket3 = LAST_INSERT_ID();
    CALL sp_registrar_control_calidad(v_ticket3, NOW(), 100, 5, 10, v_cal, v_dest_nac);
    SET v_err = 0, v_msg = NULL;
    CALL sp_agregar_ticket_pallet(v_ticket3, v_pallet, 5, 50);
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A13 Un ticket de mercado nacional no se paletiza',
            IF(v_err = 1 AND v_msg LIKE '%exportacion%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A14. No se consolida un pallet sin tickets
    INSERT INTO pallet (codigo_pallet, fecha_armado) VALUES ('TST-A-PAL2', NOW());
    SET v_pallet2 = LAST_INSERT_ID();
    INSERT INTO contenedor_maritimo (numero_contenedor) VALUES ('TST-A-CONT1');
    SET v_cont1 = LAST_INSERT_ID();
    INSERT INTO contenedor_maritimo (numero_contenedor) VALUES ('TST-A-CONT2');
    SET v_cont2 = LAST_INSERT_ID();
    SET v_err = 0, v_msg = NULL;
    CALL sp_consolidar_pallet(v_pallet2, v_cont1);
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A14 No se consolida un pallet sin tickets',
            IF(v_err = 1 AND v_msg LIKE '%sin tickets%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A15. Consolidación (Pallet N:M Contenedor): pallet ASIGNADO y contenedor EN_CARGA
    SET v_err = 0, v_msg = NULL;
    CALL sp_consolidar_pallet(v_pallet, v_cont1);
    SELECT estado INTO v_estado FROM pallet WHERE id_pallet = v_pallet;
    SELECT estado INTO v_estado2 FROM contenedor_maritimo WHERE id_contenedor = v_cont1;
    SELECT COUNT(*) INTO v_n FROM consolidacion WHERE id_pallet = v_pallet AND id_contenedor = v_cont1;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A15 Consolidación: pallet ASIGNADO, contenedor EN_CARGA y registro en consolidacion',
            IF(v_err = 0 AND v_estado = 'ASIGNADO' AND v_estado2 = 'EN_CARGA' AND v_n = 1, 'PASS', 'FAIL'),
            CONCAT('pallet ', COALESCE(v_estado, '-'), ', contenedor ', COALESCE(v_estado2, '-')));

    -- A16. Un pallet ya consolidado no se consolida otra vez
    SET v_err = 0, v_msg = NULL;
    CALL sp_consolidar_pallet(v_pallet, v_cont2);
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A16 Un pallet ya consolidado no se consolida otra vez',
            IF(v_err = 1 AND v_msg LIKE '%no disponible%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A17. Un contenedor sin embarque no se puede despachar
    SET v_err = 0, v_msg = NULL;
    UPDATE contenedor_maritimo SET estado = 'DESPACHADO' WHERE id_contenedor = v_cont1;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A17 Un contenedor sin embarque no se puede despachar',
            IF(v_err = 1 AND v_msg LIKE '%embarque%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A18. Un embarque no puede salir y llegar al mismo puerto
    SET v_err = 0, v_msg = NULL;
    INSERT INTO embarque_maritimo (codigo_embarque, id_naviera, id_puerto_salida, id_puerto_destino, temperatura_min_c, temperatura_max_c, fecha_programada)
    VALUES ('TST-A-EMB0', v_naviera, v_ps, v_ps, 5, 7, NOW());
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A18 Un embarque no puede tener el mismo puerto de salida y de destino',
            IF(v_err = 1 AND v_msg LIKE '%ck_embarque_puertos%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A19. El rango de temperatura debe ser válido
    SET v_err = 0, v_msg = NULL;
    INSERT INTO embarque_maritimo (codigo_embarque, id_naviera, id_puerto_salida, id_puerto_destino, temperatura_min_c, temperatura_max_c, fecha_programada)
    VALUES ('TST-A-EMB0', v_naviera, v_ps, v_pd, 9, 7, NOW());
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A19 El rango de temperatura del embarque debe ser válido (mín <= máx)',
            IF(v_err = 1 AND v_msg LIKE '%ck_embarque_temperatura%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A20. Un embarque agrupa varios contenedores (Embarque 1:N Contenedor)
    INSERT INTO embarque_maritimo (codigo_embarque, id_naviera, id_puerto_salida, id_puerto_destino, temperatura_min_c, temperatura_max_c, fecha_programada)
    VALUES ('TST-A-EMB1', v_naviera, v_ps, v_pd, 5, 7, NOW());
    SET v_emb = LAST_INSERT_ID();
    SET v_err = 0, v_msg = NULL;
    CALL sp_asignar_contenedor_embarque(v_cont1, v_emb);
    CALL sp_asignar_contenedor_embarque(v_cont2, v_emb);
    SELECT COUNT(*) INTO v_n FROM contenedor_maritimo WHERE id_embarque = v_emb;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A20 Un embarque agrupa varios contenedores',
            IF(v_err = 0 AND v_n = 2, 'PASS', 'FAIL'), CONCAT(v_n, ' contenedores en el embarque'));

    -- A21. Despacho: contenedor y pallet DESPACHADOS, con fecha de zarpe del embarque
    SET v_err = 0, v_msg = NULL;
    CALL sp_despachar_contenedor(v_cont1);
    SELECT estado INTO v_estado FROM pallet WHERE id_pallet = v_pallet;
    SELECT estado INTO v_estado2 FROM contenedor_maritimo WHERE id_contenedor = v_cont1;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A21 Despacho: contenedor y pallet DESPACHADOS y zarpe registrado',
            IF(v_err = 0 AND v_estado = 'DESPACHADO' AND v_estado2 = 'DESPACHADO'
               AND (SELECT fecha_zarpe FROM embarque_maritimo WHERE id_embarque = v_emb) IS NOT NULL, 'PASS', 'FAIL'),
            CONCAT('pallet ', COALESCE(v_estado, '-'), ', contenedor ', COALESCE(v_estado2, '-')));

    -- A22. Un contenedor ya despachado no se despacha de nuevo
    SET v_err = 0, v_msg = NULL;
    CALL sp_despachar_contenedor(v_cont1);
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A22 Un contenedor ya despachado no se despacha otra vez',
            IF(v_err = 1 AND v_msg LIKE '%no disponible%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A23. Un contenedor sin pallets no se despacha aunque tenga embarque
    SET v_err = 0, v_msg = NULL;
    UPDATE contenedor_maritimo SET estado = 'DESPACHADO' WHERE id_contenedor = v_cont2;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A23 Un contenedor sin pallets no se despacha',
            IF(v_err = 1 AND v_msg LIKE '%sin pallets%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A24. Trazabilidad reversa: del pallet hasta el productor, el contenedor y el embarque
    SELECT COUNT(*) INTO v_n FROM vw_trazabilidad_reversa
    WHERE codigo_pallet = 'TST-A-PAL1' AND codigo_ticket = 'TST-A-T1' AND codigo_lote = 'TST-A-LA'
      AND codigo_catastral = 'TST-A-PAR-001' AND numero_documento = 'TST-A-0001'
      AND numero_contenedor = 'TST-A-CONT1' AND codigo_embarque = 'TST-A-EMB1';
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A24 vw_trazabilidad_reversa llega del pallet al productor, contenedor y embarque',
            IF(v_n = 1, 'PASS', 'FAIL'), CONCAT(v_n, ' fila(s)'));

    -- A25. Liquidación acumulada por productor
    SELECT importe_total_pen INTO v_importe FROM vw_liquidacion_productor WHERE id_productor = v_prod;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A25 vw_liquidacion_productor suma el importe del productor',
            IF(v_importe = ROUND(85 * v_precio, 2), 'PASS', 'FAIL'), CONCAT('S/ ', COALESCE(v_importe, -1)));

    -- A26. No se liquida ni se paga a un productor sin datos de pago
    INSERT INTO ticket_acopio (codigo_ticket, id_lote, fecha_cosecha, fecha_recepcion)
    VALUES ('TST-A-T4', v_loteA, CURDATE(), NOW());
    SET v_ticket4 = LAST_INSERT_ID();
    CALL sp_registrar_control_calidad(v_ticket4, NOW(), 100, 5, 10, v_cal, v_dest);
    UPDATE productor SET numero_cuenta = NULL WHERE id_productor = v_prod;
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_liquidacion(v_ticket4, NOW());
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A26 No se liquida a un productor sin entidad financiera o cuenta',
            IF(v_err = 1 AND v_msg LIKE '%datos de pago%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));
    UPDATE productor SET numero_cuenta = 'TST-CTA-0001' WHERE id_productor = v_prod;

    -- A27. No se recibe fruta de una parcela sin certificación vigente en la fecha de cosecha
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_ticket('TST-A-T5', v_loteA, DATE_SUB(CURDATE(), INTERVAL 200 DAY), NOW(), 'TST-005');
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A27 No se recibe fruta si la parcela no tenía certificación vigente ese día',
            IF(v_err = 1 AND v_msg LIKE '%certificacion%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- A28. No se recibe fruta de un lote en periodo de carencia
    CALL sp_registrar_tratamiento(v_loteA, v_prodfito, NOW(), 'TST', v_trat);
    SET v_err = 0, v_msg = NULL;
    CALL sp_registrar_ticket('TST-A-T6', v_loteA, CURDATE(), NOW(), 'TST-006');
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('ACOPIO', 'A28 No se recibe fruta de un lote en periodo de carencia',
            IF(v_err = 1 AND v_msg LIKE '%carencia%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- Limpieza final
    DELETE cs FROM consolidacion cs JOIN pallet p ON p.id_pallet = cs.id_pallet WHERE p.codigo_pallet LIKE 'TST-A-%';
    DELETE tp FROM ticket_pallet tp JOIN ticket_acopio t ON t.id_ticket = tp.id_ticket WHERE t.codigo_ticket LIKE 'TST-A-%';
    DELETE FROM pallet WHERE codigo_pallet LIKE 'TST-A-%';
    DELETE FROM contenedor_maritimo WHERE numero_contenedor LIKE 'TST-A-%';
    DELETE FROM embarque_maritimo WHERE codigo_embarque LIKE 'TST-A-%';
    DELETE li FROM liquidacion li JOIN ticket_acopio t ON t.id_ticket = li.id_ticket WHERE t.codigo_ticket LIKE 'TST-A-%';
    DELETE cc FROM control_calidad cc JOIN ticket_acopio t ON t.id_ticket = cc.id_ticket WHERE t.codigo_ticket LIKE 'TST-A-%';
    DELETE FROM ticket_acopio WHERE codigo_ticket LIKE 'TST-A-%';
    DELETE i FROM inspeccion_pre_cosecha i JOIN lote_agricola l ON l.id_lote = i.id_lote WHERE l.codigo_lote LIKE 'TST-A-%';
    DELETE tr FROM tratamiento_fitosanitario tr JOIN lote_agricola l ON l.id_lote = tr.id_lote WHERE l.codigo_lote LIKE 'TST-A-%';
    DELETE FROM lote_agricola WHERE codigo_lote LIKE 'TST-A-%';
    DELETE FROM certificacion WHERE codigo_certificacion LIKE 'TST-A-%';
    DELETE FROM parcela WHERE codigo_catastral LIKE 'TST-A-%';
    DELETE FROM productor WHERE numero_documento LIKE 'TST-A-%';

END//

DELIMITER ;

CALL sp_tmp_pruebas_acopio();
DROP PROCEDURE IF EXISTS sp_tmp_pruebas_acopio;

SELECT n, prueba, resultado, detalle FROM tmp_resultado_pruebas WHERE modulo = 'ACOPIO' ORDER BY n;
