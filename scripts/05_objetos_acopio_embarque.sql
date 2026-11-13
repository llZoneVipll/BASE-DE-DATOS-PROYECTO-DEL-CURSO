-- =====================================================================
-- Archivo : 05_objetos_acopio_embarque.sql
-- Dueño   : Bujaico
-- Contenido: Funciones, triggers, procedimientos y vistas de Acopio, Calidad y Embarque (peso neto pagable, tarifa por kg, pallets, consolidación, despacho, trazabilidad reversa, liquidación).
-- =====================================================================


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

-- Relacion "conforma" (Ticket N:M Pallet): un pallet reune fruta de varios tickets
DROP PROCEDURE IF EXISTS sp_agregar_ticket_pallet $$
CREATE PROCEDURE sp_agregar_ticket_pallet(
    IN p_ticket BIGINT UNSIGNED,
    IN p_pallet BIGINT UNSIGNED,
    IN p_cantidad_cajas INT UNSIGNED,
    IN p_peso_neto_kg DECIMAL(10,3)
)
BEGIN
    DECLARE v_neto DECIMAL(12,3) DEFAULT NULL;
    DECLARE v_asignado DECIMAL(12,3) DEFAULT 0;

    IF NOT EXISTS (
        SELECT 1 FROM pallet WHERE id_pallet = p_pallet AND estado = 'ARMADO'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pallet no disponible';
    END IF;

    SELECT cc.peso_neto_pagable_kg INTO v_neto
    FROM ticket_acopio t
    JOIN control_calidad cc ON cc.id_ticket = t.id_ticket
    JOIN destino_comercial d ON d.id_destino_comercial = cc.id_destino_comercial
    WHERE t.id_ticket = p_ticket AND d.nombre = 'EXPORTACION';

    IF v_neto IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El ticket no es de exportacion o no tiene control de calidad';
    END IF;

    SELECT COALESCE(SUM(peso_neto_kg), 0) INTO v_asignado
    FROM ticket_pallet WHERE id_ticket = p_ticket;

    IF v_asignado + p_peso_neto_kg > v_neto THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El peso supera el neto pagable del ticket';
    END IF;

    INSERT INTO ticket_pallet (id_ticket, id_pallet, cantidad_cajas, peso_neto_kg)
    VALUES (p_ticket, p_pallet, p_cantidad_cajas, p_peso_neto_kg);
END $$

-- La cantidad de cajas del pallet es un atributo derivado: la mantienen estos triggers
DROP TRIGGER IF EXISTS trg_ticket_pallet_ai_cajas $$
CREATE TRIGGER trg_ticket_pallet_ai_cajas
AFTER INSERT ON ticket_pallet
FOR EACH ROW
BEGIN
    UPDATE pallet SET cantidad_cajas = cantidad_cajas + NEW.cantidad_cajas
    WHERE id_pallet = NEW.id_pallet;
END $$

DROP TRIGGER IF EXISTS trg_ticket_pallet_au_cajas $$
CREATE TRIGGER trg_ticket_pallet_au_cajas
AFTER UPDATE ON ticket_pallet
FOR EACH ROW
BEGIN
    UPDATE pallet SET cantidad_cajas = cantidad_cajas - OLD.cantidad_cajas
    WHERE id_pallet = OLD.id_pallet;

    UPDATE pallet SET cantidad_cajas = cantidad_cajas + NEW.cantidad_cajas
    WHERE id_pallet = NEW.id_pallet;
END $$

DROP TRIGGER IF EXISTS trg_ticket_pallet_ad_cajas $$
CREATE TRIGGER trg_ticket_pallet_ad_cajas
AFTER DELETE ON ticket_pallet
FOR EACH ROW
BEGIN
    UPDATE pallet SET cantidad_cajas = cantidad_cajas - OLD.cantidad_cajas
    WHERE id_pallet = OLD.id_pallet;
END $$

-- Entidad asociativa Consolidacion (Pallet N:M Contenedor): reglas al consolidar
DROP TRIGGER IF EXISTS trg_consolidacion_bi_valida $$
CREATE TRIGGER trg_consolidacion_bi_valida
BEFORE INSERT ON consolidacion
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pallet WHERE id_pallet = NEW.id_pallet AND estado = 'ARMADO'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pallet no disponible';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM ticket_pallet WHERE id_pallet = NEW.id_pallet
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pallet sin tickets';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM contenedor_maritimo
        WHERE id_contenedor = NEW.id_contenedor
          AND estado IN ('PLANIFICADO', 'EN_CARGA')
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Contenedor no disponible';
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

    INSERT INTO consolidacion (id_pallet, id_contenedor, fecha_consolidacion)
    VALUES (p_pallet, p_contenedor, NOW());

    UPDATE pallet SET estado = 'ASIGNADO' WHERE id_pallet = p_pallet;

    UPDATE contenedor_maritimo SET estado = 'EN_CARGA'
    WHERE id_contenedor = p_contenedor;

    COMMIT;
END $$

-- Un contenedor se despacha en un embarque (0..1); un embarque agrupa 1..N contenedores
DROP PROCEDURE IF EXISTS sp_asignar_contenedor_embarque $$
CREATE PROCEDURE sp_asignar_contenedor_embarque(
    IN p_contenedor BIGINT UNSIGNED,
    IN p_embarque BIGINT UNSIGNED
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM embarque_maritimo WHERE id_embarque = p_embarque) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Embarque inexistente';
    END IF;

    UPDATE contenedor_maritimo
    SET id_embarque = p_embarque
    WHERE id_contenedor = p_contenedor AND estado <> 'DESPACHADO';

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Contenedor no disponible';
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_contenedor_maritimo_bu_despacho $$
CREATE TRIGGER trg_contenedor_maritimo_bu_despacho
BEFORE UPDATE ON contenedor_maritimo
FOR EACH ROW
BEGIN
    IF NEW.estado = 'DESPACHADO' AND OLD.estado <> 'DESPACHADO' THEN
        IF NEW.numero_contenedor IS NULL OR TRIM(NEW.numero_contenedor) = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Faltan datos del contenedor';
        END IF;

        IF NEW.id_embarque IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Faltan datos del embarque: el contenedor no tiene embarque asignado';
        END IF;

        -- naviera, puertos y rango de temperatura son obligatorios en el embarque;
        -- aqui se exige ademas que ya tenga fecha de zarpe
        IF NOT EXISTS (
            SELECT 1 FROM embarque_maritimo
            WHERE id_embarque = NEW.id_embarque
              AND id_puerto_salida <> id_puerto_destino
              AND fecha_zarpe IS NOT NULL
        ) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Faltan datos del embarque';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM consolidacion cs
            JOIN pallet p ON p.id_pallet = cs.id_pallet
            WHERE cs.id_contenedor = NEW.id_contenedor AND p.estado = 'ASIGNADO'
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

    UPDATE embarque_maritimo e
    JOIN contenedor_maritimo c ON c.id_embarque = e.id_embarque
    SET e.fecha_zarpe = NOW()
    WHERE c.id_contenedor = p_contenedor AND e.fecha_zarpe IS NULL;

    UPDATE contenedor_maritimo
    SET estado = 'DESPACHADO'
    WHERE id_contenedor = p_contenedor AND estado = 'EN_CARGA';

    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Contenedor no disponible para despacho';
    END IF;

    UPDATE pallet p
    JOIN consolidacion cs ON cs.id_pallet = p.id_pallet
    SET p.estado = 'DESPACHADO'
    WHERE cs.id_contenedor = p_contenedor AND p.estado = 'ASIGNADO';

    COMMIT;
END $$

-- Control de ingreso a planta: ademas de estar habilitado, en la fecha de cosecha el lote
-- debe tener certificacion vigente y no estar en periodo de carencia
DROP TRIGGER IF EXISTS trg_ticket_acopio_bi_valida $$
CREATE TRIGGER trg_ticket_acopio_bi_valida
BEFORE INSERT ON ticket_acopio
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM lote_agricola
        WHERE id_lote = NEW.id_lote AND estado = 'HABILITADO_PARA_COSECHA'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lote no habilitado';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM lote_agricola l
        JOIN certificacion c ON c.id_parcela = l.id_parcela
        WHERE l.id_lote = NEW.id_lote
          AND NEW.fecha_cosecha BETWEEN c.fecha_inicio AND c.fecha_fin
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La parcela no tiene certificacion vigente en la fecha de cosecha';
    END IF;

    IF EXISTS (
        SELECT 1 FROM tratamiento_fitosanitario t
        WHERE t.id_lote = NEW.id_lote
          AND DATE(t.fecha_aplicacion) <= NEW.fecha_cosecha
          AND DATE(t.fecha_liberacion) > NEW.fecha_cosecha
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El lote esta en periodo de carencia en la fecha de cosecha';
    END IF;
END $$

-- Informacion de pago: no se liquida ni se paga a un productor sin entidad financiera y cuenta
DROP TRIGGER IF EXISTS trg_liquidacion_bi_pago $$
CREATE TRIGGER trg_liquidacion_bi_pago
BEFORE INSERT ON liquidacion
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM ticket_acopio t
        JOIN lote_agricola l ON l.id_lote = t.id_lote
        JOIN parcela pa ON pa.id_parcela = l.id_parcela
        JOIN productor pr ON pr.id_productor = pa.id_productor
        WHERE t.id_ticket = NEW.id_ticket
          AND pr.id_entidad_financiera IS NOT NULL
          AND pr.numero_cuenta IS NOT NULL AND TRIM(pr.numero_cuenta) <> ''
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Productor sin datos de pago: falta entidad financiera o numero de cuenta';
    END IF;
END $$

DROP TRIGGER IF EXISTS trg_liquidacion_bu_pago $$
CREATE TRIGGER trg_liquidacion_bu_pago
BEFORE UPDATE ON liquidacion
FOR EACH ROW
BEGIN
    IF NEW.estado = 'PAGADA' AND OLD.estado <> 'PAGADA' THEN
        IF NOT EXISTS (
            SELECT 1
            FROM ticket_acopio t
            JOIN lote_agricola l ON l.id_lote = t.id_lote
            JOIN parcela pa ON pa.id_parcela = l.id_parcela
            JOIN productor pr ON pr.id_productor = pa.id_productor
            WHERE t.id_ticket = NEW.id_ticket
              AND pr.id_entidad_financiera IS NOT NULL
              AND pr.numero_cuenta IS NOT NULL AND TRIM(pr.numero_cuenta) <> ''
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Productor sin datos de pago: falta entidad financiera o numero de cuenta';
        END IF;
    END IF;
END $$

DELIMITER ;

CREATE OR REPLACE VIEW vw_trazabilidad_reversa AS
SELECT p.codigo_pallet, tp.cantidad_cajas, t.codigo_ticket,
       l.codigo_lote, pa.codigo_catastral,
       pr.numero_documento, pr.nombre_completo,
       co.numero_contenedor, em.codigo_embarque
FROM pallet p
JOIN ticket_pallet tp ON tp.id_pallet = p.id_pallet
JOIN ticket_acopio t ON t.id_ticket = tp.id_ticket
JOIN lote_agricola l ON l.id_lote = t.id_lote
JOIN parcela pa ON pa.id_parcela = l.id_parcela
JOIN productor pr ON pr.id_productor = pa.id_productor
LEFT JOIN consolidacion cs ON cs.id_pallet = p.id_pallet
LEFT JOIN contenedor_maritimo co ON co.id_contenedor = cs.id_contenedor
LEFT JOIN embarque_maritimo em ON em.id_embarque = co.id_embarque;

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
