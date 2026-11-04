SET NAMES utf8mb4;
USE agro_trazabilidad;

DELIMITER $$

DROP FUNCTION IF EXISTS fn_peso_neto $$
CREATE FUNCTION fn_peso_neto(
    p_bruto DECIMAL(12,3),
    p_tara DECIMAL(12,3),
    p_descarte DECIMAL(12,3)
)
RETURNS DECIMAL(12,3)
DETERMINISTIC
NO SQL
BEGIN
    IF p_bruto IS NULL OR p_tara IS NULL OR p_descarte IS NULL
       OR p_bruto <= 0 OR p_tara < 0 OR p_descarte < 0
       OR p_tara + p_descarte > p_bruto THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pesos invalidos';
    END IF;

    RETURN p_bruto - p_tara - p_descarte;
END $$

DROP FUNCTION IF EXISTS fn_tarifa_kg $$
CREATE FUNCTION fn_tarifa_kg(
    p_calibre INT UNSIGNED,
    p_destino INT UNSIGNED,
    p_fecha DATE
)
RETURNS DECIMAL(12,4)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(12,4) DEFAULT NULL;

    SELECT precio_kg_pen INTO v_precio
    FROM tarifa
    WHERE id_calibre = p_calibre
      AND id_destino_comercial = p_destino
      AND vigencia_desde <= p_fecha
      AND (vigencia_hasta IS NULL OR vigencia_hasta >= p_fecha)
    ORDER BY vigencia_desde DESC, id_tarifa DESC
    LIMIT 1;

    IF v_precio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe tarifa vigente';
    END IF;

    RETURN v_precio;
END $$

DROP PROCEDURE IF EXISTS sp_registrar_ticket $$
CREATE PROCEDURE sp_registrar_ticket(
    IN p_codigo VARCHAR(50),
    IN p_lote BIGINT UNSIGNED,
    IN p_cosecha DATE,
    IN p_recepcion DATETIME,
    IN p_placa VARCHAR(15)
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM lote_agricola
        WHERE id_lote = p_lote AND estado = 'HABILITADO_PARA_COSECHA'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lote no habilitado';
    END IF;

    INSERT INTO ticket_acopio
        (codigo_ticket, id_lote, fecha_cosecha, fecha_recepcion, placa_vehiculo)
    VALUES
        (p_codigo, p_lote, p_cosecha, p_recepcion, p_placa);

    SELECT LAST_INSERT_ID() AS id_ticket;
END $$

DROP PROCEDURE IF EXISTS sp_registrar_control_calidad $$
CREATE PROCEDURE sp_registrar_control_calidad(
    IN p_ticket BIGINT UNSIGNED,
    IN p_fecha DATETIME,
    IN p_bruto DECIMAL(12,3),
    IN p_tara DECIMAL(12,3),
    IN p_descarte DECIMAL(12,3),
    IN p_calibre INT UNSIGNED,
    IN p_destino INT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO control_calidad
        (id_ticket, fecha_control, peso_bruto_kg, tara_kg,
         descarte_kg, id_calibre, id_destino_comercial)
    VALUES
        (p_ticket, p_fecha, p_bruto, p_tara,
         p_descarte, p_calibre, p_destino);

    UPDATE ticket_acopio
    SET estado = 'EVALUADO'
    WHERE id_ticket = p_ticket;

    COMMIT;
    SELECT LAST_INSERT_ID() AS id_control_calidad;
END $$

DROP PROCEDURE IF EXISTS sp_registrar_liquidacion $$
CREATE PROCEDURE sp_registrar_liquidacion(
    IN p_ticket BIGINT UNSIGNED,
    IN p_fecha DATETIME
)
BEGIN
    DECLARE v_peso DECIMAL(12,3) DEFAULT NULL;
    DECLARE v_calibre INT UNSIGNED;
    DECLARE v_destino INT UNSIGNED;
    DECLARE v_tarifa BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_precio DECIMAL(12,4);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT peso_neto_pagable_kg, id_calibre, id_destino_comercial
    INTO v_peso, v_calibre, v_destino
    FROM control_calidad
    WHERE id_ticket = p_ticket;

    IF v_peso IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ticket sin control de calidad';
    END IF;

    SELECT id_tarifa, precio_kg_pen INTO v_tarifa, v_precio
    FROM tarifa
    WHERE id_calibre = v_calibre
      AND id_destino_comercial = v_destino
      AND vigencia_desde <= DATE(p_fecha)
      AND (vigencia_hasta IS NULL OR vigencia_hasta >= DATE(p_fecha))
    ORDER BY vigencia_desde DESC, id_tarifa DESC
    LIMIT 1;

    IF v_tarifa IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe tarifa vigente';
    END IF;

    START TRANSACTION;

    INSERT INTO liquidacion
        (id_ticket, id_tarifa, fecha_liquidacion,
         peso_neto_pagable_kg, precio_kg_aplicado_pen)
    VALUES (p_ticket, v_tarifa, p_fecha, v_peso, v_precio);

    UPDATE ticket_acopio
    SET estado = 'LIQUIDADO'
    WHERE id_ticket = p_ticket;

    COMMIT;
    SELECT LAST_INSERT_ID() AS id_liquidacion;
END $$

DROP PROCEDURE IF EXISTS sp_armar_pallet $$
CREATE PROCEDURE sp_armar_pallet(
    IN p_codigo VARCHAR(80),
    IN p_fecha DATETIME
)
BEGIN
    INSERT INTO pallet (codigo_pallet, fecha_armado)
    VALUES (p_codigo, p_fecha);

    SELECT LAST_INSERT_ID() AS id_pallet;
END $$

DROP PROCEDURE IF EXISTS sp_agregar_caja_pallet $$
CREATE PROCEDURE sp_agregar_caja_pallet(
    IN p_caja BIGINT UNSIGNED,
    IN p_pallet BIGINT UNSIGNED
)
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pallet
        WHERE id_pallet = p_pallet AND estado = 'ARMADO'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pallet no disponible';
    END IF;

    UPDATE caja
    SET id_pallet = p_pallet
    WHERE id_caja = p_caja AND id_pallet IS NULL;

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Caja inexistente o asignada';
    END IF;
END $$

DROP PROCEDURE IF EXISTS sp_consolidar_pallet $$
CREATE PROCEDURE sp_consolidar_pallet(
    IN p_pallet BIGINT UNSIGNED,
    IN p_contenedor BIGINT UNSIGNED
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM contenedor_maritimo
        WHERE id_contenedor = p_contenedor
          AND estado IN ('PLANIFICADO', 'EN_CARGA')
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Contenedor no disponible';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM caja WHERE id_pallet = p_pallet
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pallet sin cajas';
    END IF;

    UPDATE pallet
    SET id_contenedor = p_contenedor, estado = 'ASIGNADO'
    WHERE id_pallet = p_pallet
      AND id_contenedor IS NULL AND estado = 'ARMADO';

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pallet no disponible';
    END IF;

    UPDATE contenedor_maritimo
    SET estado = 'EN_CARGA'
    WHERE id_contenedor = p_contenedor;

    COMMIT;
END $$

DROP TRIGGER IF EXISTS trg_contenedor_maritimo_bu_despacho $$
CREATE TRIGGER trg_contenedor_maritimo_bu_despacho
BEFORE UPDATE ON contenedor_maritimo
FOR EACH ROW
BEGIN
    IF NEW.estado = 'DESPACHADO' AND OLD.estado <> 'DESPACHADO' THEN
        IF NEW.numero_contenedor IS NULL OR TRIM(NEW.numero_contenedor) = ''
           OR NEW.id_naviera IS NULL
           OR NEW.temperatura_min_c IS NULL
           OR NEW.temperatura_max_c IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Faltan datos del contenedor';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM embarque_maritimo
            WHERE id_contenedor = NEW.id_contenedor
              AND id_puerto_salida <> id_puerto_destino
              AND fecha_despacho IS NOT NULL
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Faltan datos del embarque';
        END IF;

        IF NOT EXISTS (
            SELECT 1 FROM pallet
            WHERE id_contenedor = NEW.id_contenedor AND estado = 'ASIGNADO'
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Contenedor sin pallets';
        END IF;
    END IF;
END $$

DROP PROCEDURE IF EXISTS sp_despachar_contenedor $$
CREATE PROCEDURE sp_despachar_contenedor(IN p_contenedor BIGINT UNSIGNED)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    UPDATE embarque_maritimo
    SET fecha_despacho = NOW()
    WHERE id_contenedor = p_contenedor AND fecha_despacho IS NULL;

    UPDATE contenedor_maritimo
    SET estado = 'DESPACHADO'
    WHERE id_contenedor = p_contenedor AND estado = 'EN_CARGA';

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Contenedor no disponible para despacho';
    END IF;

    UPDATE pallet
    SET estado = 'DESPACHADO'
    WHERE id_contenedor = p_contenedor AND estado = 'ASIGNADO';

    COMMIT;
END $$

DELIMITER ;

CREATE OR REPLACE VIEW vw_trazabilidad_reversa AS
SELECT p.codigo_pallet, c.codigo_caja, t.codigo_ticket,
       l.codigo_lote, pa.codigo_catastral,
       pr.numero_documento, pr.nombre_completo,
       co.numero_contenedor
FROM pallet p
JOIN caja c ON c.id_pallet = p.id_pallet
JOIN ticket_acopio t ON t.id_ticket = c.id_ticket
JOIN lote_agricola l ON l.id_lote = t.id_lote
JOIN parcela pa ON pa.id_parcela = l.id_parcela
JOIN productor pr ON pr.id_productor = pa.id_productor
LEFT JOIN contenedor_maritimo co ON co.id_contenedor = p.id_contenedor;

CREATE OR REPLACE VIEW vw_liquidacion_productor AS
SELECT pr.id_productor, pr.nombre_completo,
       COUNT(*) AS tickets_liquidados,
       SUM(li.peso_neto_pagable_kg) AS peso_total_kg,
       SUM(li.importe_total_pen) AS importe_total_pen
FROM liquidacion li
JOIN ticket_acopio t ON t.id_ticket = li.id_ticket
JOIN lote_agricola l ON l.id_lote = t.id_lote
JOIN parcela pa ON pa.id_parcela = l.id_parcela
JOIN productor pr ON pr.id_productor = pa.id_productor
WHERE li.estado <> 'ANULADA'
GROUP BY pr.id_productor, pr.nombre_completo;
