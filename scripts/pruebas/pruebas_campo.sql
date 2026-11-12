-- =====================================================================
-- Archivo : pruebas/pruebas_campo.sql
-- Dueño   : Pacara
-- Contenido: Casos de prueba de las reglas de Campo y Control Fitosanitario
--            (fecha de liberación, certificaciones, inspección, carencia,
--            habilitación de lotes y vistas).
-- Cómo se usa: corre solo o desde 08_pruebas.sql. Cada caso termina en PASS
--            o FAIL. Los datos de prueba llevan el prefijo TST-C y se borran
--            al terminar, así que no alteran la base cargada.
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

DROP PROCEDURE IF EXISTS sp_tmp_pruebas_campo//
CREATE PROCEDURE sp_tmp_pruebas_campo()
BEGIN
    DECLARE v_err INT DEFAULT 0;
    DECLARE v_msg VARCHAR(300) DEFAULT NULL;
    DECLARE v_prod BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_parc BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_lote1 BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_lote2 BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_cert BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_insp BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_trat BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_inspector_ok BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_inspector_no BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_producto INT UNSIGNED DEFAULT NULL;
    DECLARE v_carencia INT UNSIGNED DEFAULT NULL;
    DECLARE v_aplicada INT UNSIGNED DEFAULT NULL;
    DECLARE v_estado VARCHAR(30) DEFAULT NULL;
    DECLARE v_n INT DEFAULT 0;
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
        SET v_err = 1;
    END;

    -- Limpieza previa (por si una corrida anterior quedó a medias)
    DELETE i FROM inspeccion_pre_cosecha i JOIN lote_agricola l ON l.id_lote = i.id_lote WHERE l.codigo_lote LIKE 'TST-C-%';
    DELETE t FROM tratamiento_fitosanitario t JOIN lote_agricola l ON l.id_lote = t.id_lote WHERE l.codigo_lote LIKE 'TST-C-%';
    DELETE FROM lote_agricola WHERE codigo_lote LIKE 'TST-C-%';
    DELETE FROM certificacion WHERE codigo_certificacion LIKE 'TST-C-%';
    DELETE FROM parcela WHERE codigo_catastral LIKE 'TST-C-%';
    DELETE FROM productor WHERE numero_documento LIKE 'TST-C-%';

    -- Datos base
    SELECT id_inspector INTO v_inspector_ok FROM inspector WHERE autorizado = TRUE ORDER BY id_inspector LIMIT 1;
    SELECT id_inspector INTO v_inspector_no FROM inspector WHERE autorizado = FALSE ORDER BY id_inspector LIMIT 1;
    SELECT id_producto_fitosanitario, periodo_carencia_dias INTO v_producto, v_carencia
    FROM producto_fitosanitario WHERE periodo_carencia_dias BETWEEN 5 AND 25 ORDER BY id_producto_fitosanitario LIMIT 1;

    CALL sp_mantenimiento_productor('INSERT', v_prod, 'DNI', 'TST-C-0001', 'Productor TST Campo', NULL,
        (SELECT MIN(id_tipo_asociacion) FROM tipo_asociacion), NULL, NULL, TRUE);
    CALL sp_mantenimiento_parcela('INSERT', v_parc, v_prod, 'TST-C-PAR-001', '131201', 'Sector TST',
        ST_GeomFromText('POLYGON((-78.70 -8.40,-78.69 -8.40,-78.69 -8.41,-78.70 -8.41,-78.70 -8.40))', 4326, 'axis-order=long-lat'));
    CALL sp_mantenimiento_lote('INSERT', v_lote1, v_parc, 'TST-C-L1', 'Palta', 'Hass', '2024-01-01', NULL, 10, 'REGISTRADO');
    CALL sp_mantenimiento_lote('INSERT', v_lote2, v_parc, 'TST-C-L2', 'Palta', 'Hass', '2024-01-01', NULL, 10, 'REGISTRADO');

    -- C1. Fecha de liberación = fecha de aplicación + periodo de carencia
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C1 Fecha de liberación = aplicación + carencia',
            IF(fn_calcular_fecha_liberacion('2026-06-01 08:00:00', v_producto)
               = DATE_ADD('2026-06-01 08:00:00', INTERVAL v_carencia DAY), 'PASS', 'FAIL'),
            CONCAT('carencia ', v_carencia, ' días: ', fn_calcular_fecha_liberacion('2026-06-01 08:00:00', v_producto)));

    -- C2. Un lote nuevo no puede nacer ya habilitado
    SET v_err = 0, v_msg = NULL;
    INSERT INTO lote_agricola (id_parcela, codigo_lote, especie, fecha_siembra, estado)
    VALUES (v_parc, 'TST-C-L3', 'Palta', '2024-01-01', 'HABILITADO_PARA_COSECHA');
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C2 Un lote nuevo no puede registrarse ya habilitado',
            IF(v_err = 1 AND v_msg LIKE '%nuevo%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- C3. Parcela sin certificación no habilita el lote
    SET v_err = 0, v_msg = NULL;
    UPDATE lote_agricola SET estado = 'HABILITADO_PARA_COSECHA' WHERE id_lote = v_lote1;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C3 Sin certificación no se habilita el lote',
            IF(v_err = 1 AND v_msg LIKE '%certificaci%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- C4. Certificación vencida no habilita el lote
    CALL sp_mantenimiento_certificacion('INSERT', v_cert, v_parc, 'GLOBALG.A.P.', 'TST-C-CERT-VENCIDA', 'Certificadora TST',
        DATE_SUB(CURDATE(), INTERVAL 800 DAY), DATE_SUB(CURDATE(), INTERVAL 400 DAY));
    SET v_err = 0, v_msg = NULL;
    UPDATE lote_agricola SET estado = 'HABILITADO_PARA_COSECHA' WHERE id_lote = v_lote1;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C4 Certificación vencida no habilita el lote',
            IF(v_err = 1 AND v_msg LIKE '%certificaci%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- C5. Con certificación vigente pero sin inspección aprobada, no se habilita
    SET v_cert = NULL;
    CALL sp_mantenimiento_certificacion('INSERT', v_cert, v_parc, 'GLOBALG.A.P.', 'TST-C-CERT-VIGENTE', 'Certificadora TST',
        DATE_SUB(CURDATE(), INTERVAL 100 DAY), DATE_ADD(CURDATE(), INTERVAL 265 DAY));
    SET v_err = 0, v_msg = NULL;
    UPDATE lote_agricola SET estado = 'HABILITADO_PARA_COSECHA' WHERE id_lote = v_lote1;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C5 Sin inspección aprobada no se habilita el lote',
            IF(v_err = 1 AND v_msg LIKE '%inspecci%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- C6. Un inspector no autorizado no puede emitir el acta
    SET v_err = 0, v_msg = NULL;
    CALL sp_mantenimiento_inspeccion('INSERT', v_insp, v_lote1, v_inspector_no, NOW(), 'APROBADA', 'TST');
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C6 Inspector no autorizado no puede emitir el acta',
            IF(v_err = 1 AND v_msg LIKE '%inspector autorizado%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- C7. Una inspección rechazada tampoco habilita el lote
    SET v_insp = NULL;
    CALL sp_mantenimiento_inspeccion('INSERT', v_insp, v_lote1, v_inspector_ok, NOW(), 'RECHAZADA', 'TST');
    SET v_err = 0, v_msg = NULL;
    UPDATE lote_agricola SET estado = 'HABILITADO_PARA_COSECHA' WHERE id_lote = v_lote1;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C7 Inspección rechazada no habilita el lote',
            IF(v_err = 1 AND v_msg LIKE '%inspecci%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- C8. El tratamiento guarda la carencia vigente al aplicar
    SET v_insp = NULL;
    CALL sp_mantenimiento_inspeccion('INSERT', v_insp, v_lote1, v_inspector_ok, NOW(), 'APROBADA', 'TST');
    CALL sp_registrar_tratamiento(v_lote1, v_producto, NOW(), 'TST', v_trat);
    SELECT periodo_carencia_dias_aplicado INTO v_aplicada FROM tratamiento_fitosanitario WHERE id_tratamiento = v_trat;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C8 El tratamiento guarda la carencia vigente al aplicar',
            IF(v_aplicada = v_carencia, 'PASS', 'FAIL'), CONCAT('guardada ', COALESCE(v_aplicada, -1), ', catálogo ', v_carencia));

    -- C9. Lote en periodo de carencia activo no se habilita
    SET v_err = 0, v_msg = NULL;
    UPDATE lote_agricola SET estado = 'HABILITADO_PARA_COSECHA' WHERE id_lote = v_lote1;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C9 Lote en carencia activa no se habilita',
            IF(v_err = 1 AND v_msg LIKE '%carencia%', 'PASS', 'FAIL'), COALESCE(v_msg, 'no hubo error'));

    -- C10. Con certificación vigente, inspección aprobada y carencia cumplida, el lote SÍ se habilita
    SET v_insp = NULL, v_trat = NULL;
    CALL sp_mantenimiento_inspeccion('INSERT', v_insp, v_lote2, v_inspector_ok, NOW(), 'APROBADA', 'TST');
    CALL sp_registrar_tratamiento(v_lote2, v_producto, DATE_SUB(NOW(), INTERVAL 60 DAY), 'TST', v_trat);
    SET v_err = 0, v_msg = NULL;
    UPDATE lote_agricola SET estado = 'HABILITADO_PARA_COSECHA' WHERE id_lote = v_lote2;
    SELECT estado INTO v_estado FROM lote_agricola WHERE id_lote = v_lote2;
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C10 Lote que cumple todos los requisitos sí se habilita',
            IF(v_err = 0 AND v_estado = 'HABILITADO_PARA_COSECHA', 'PASS', 'FAIL'), COALESCE(v_msg, v_estado));

    -- C11. La vista de lotes habilitables incluye solo el lote habilitado
    SELECT COUNT(*) INTO v_n FROM vw_lotes_habilitables WHERE codigo_lote IN ('TST-C-L1', 'TST-C-L2');
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C11 vw_lotes_habilitables muestra solo el lote habilitado',
            IF(v_n = 1 AND EXISTS (SELECT 1 FROM vw_lotes_habilitables WHERE codigo_lote = 'TST-C-L2'), 'PASS', 'FAIL'),
            CONCAT(v_n, ' lote(s) de prueba en la vista'));

    -- C12. La vista de certificaciones clasifica vigentes y vencidas
    INSERT INTO tmp_resultado_pruebas (modulo, prueba, resultado, detalle)
    VALUES ('CAMPO', 'C12 vw_certificaciones_vigentes_o_vencer clasifica VENCIDA y VIGENTE',
            IF((SELECT estado_vigencia FROM vw_certificaciones_vigentes_o_vencer WHERE codigo_certificacion = 'TST-C-CERT-VENCIDA') = 'VENCIDA'
               AND (SELECT estado_vigencia FROM vw_certificaciones_vigentes_o_vencer WHERE codigo_certificacion = 'TST-C-CERT-VIGENTE') = 'VIGENTE',
               'PASS', 'FAIL'), NULL);

    -- Limpieza final
    DELETE i FROM inspeccion_pre_cosecha i JOIN lote_agricola l ON l.id_lote = i.id_lote WHERE l.codigo_lote LIKE 'TST-C-%';
    DELETE t FROM tratamiento_fitosanitario t JOIN lote_agricola l ON l.id_lote = t.id_lote WHERE l.codigo_lote LIKE 'TST-C-%';
    DELETE FROM lote_agricola WHERE codigo_lote LIKE 'TST-C-%';
    DELETE FROM certificacion WHERE codigo_certificacion LIKE 'TST-C-%';
    DELETE FROM parcela WHERE codigo_catastral LIKE 'TST-C-%';
    DELETE FROM productor WHERE numero_documento LIKE 'TST-C-%';
END//

DELIMITER ;

CALL sp_tmp_pruebas_campo();
DROP PROCEDURE IF EXISTS sp_tmp_pruebas_campo;

SELECT n, prueba, resultado, detalle FROM tmp_resultado_pruebas WHERE modulo = 'CAMPO' ORDER BY n;
