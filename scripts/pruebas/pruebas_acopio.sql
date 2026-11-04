-- =====================================================================
-- Archivo : pruebas/pruebas_acopio.sql
-- Dueño   : Bujaico
-- Contenido: Casos de prueba de las reglas de Acopio, Calidad y Embarque (2 o 3 por regla).
-- =====================================================================

SET NAMES utf8mb4;
USE agro_trazabilidad;

SELECT fn_peso_neto(100, 5, 10);

INSERT INTO tipo_asociacion (nombre)
VALUES ('Asociacion Prueba');
SET @tipo = LAST_INSERT_ID();

INSERT INTO ubigeo
VALUES ('999998', 'Lima', 'Lima', 'Prueba');

INSERT INTO productor
(tipo_documento, numero_documento, nombre_completo, id_tipo_asociacion)
VALUES ('DNI', '99999998', 'Productor Prueba', @tipo);
SET @productor = LAST_INSERT_ID();

INSERT INTO parcela
(id_productor, codigo_catastral, codigo_ubigeo, sector_agricola, poligono)
VALUES (
    @productor, 'PARCELA-PRUEBA', '999998', 'Sector Prueba',
    ST_GeomFromText(
        'POLYGON((-77.05 -12.05,-77.04 -12.05,-77.04 -12.04,-77.05 -12.04,-77.05 -12.05))',
        4326, 'axis-order=long-lat'
    )
);
SET @parcela = LAST_INSERT_ID();

INSERT INTO lote_agricola
(id_parcela, codigo_lote, especie, fecha_siembra, estado)
VALUES
(@parcela, 'LOTE-PRUEBA', 'Palta', '2024-01-01', 'HABILITADO_PARA_COSECHA');
SET @lote = LAST_INSERT_ID();

INSERT INTO calibre (codigo)
VALUES ('CALIBRE-PRUEBA');
SET @calibre = LAST_INSERT_ID();

INSERT INTO destino_comercial (nombre)
VALUES ('DESTINO-PRUEBA');
SET @destino = LAST_INSERT_ID();

INSERT INTO tarifa
(id_calibre, id_destino_comercial, precio_kg_pen, vigencia_desde)
VALUES (@calibre, @destino, 4.50, '2026-01-01');

SELECT fn_tarifa_kg(@calibre, @destino, '2026-11-04');

CALL sp_registrar_ticket(
    'TICKET-PRUEBA', @lote,
    '2026-11-04', '2026-11-04 08:00:00', 'ABC-123'
);
SET @ticket = LAST_INSERT_ID();

CALL sp_registrar_control_calidad(
    @ticket, '2026-11-04 09:00:00',
    100, 5, 10, @calibre, @destino
);

CALL sp_registrar_liquidacion(
    @ticket, '2026-11-04 10:00:00'
);

CALL sp_armar_pallet(
    'PALLET-PRUEBA-FINAL', '2026-11-04 11:00:00'
);
SET @pallet = LAST_INSERT_ID();

INSERT INTO caja
(codigo_caja, id_ticket, fecha_empaque, peso_neto_kg)
VALUES ('CAJA-PRUEBA', @ticket, '2026-11-04 11:00:00', 85);
SET @caja = LAST_INSERT_ID();

CALL sp_agregar_caja_pallet(@caja, @pallet);

INSERT INTO naviera (nombre)
VALUES ('Naviera Prueba');
SET @naviera = LAST_INSERT_ID();

INSERT INTO puerto (nombre, pais)
VALUES ('Puerto Salida Prueba', 'PE');
SET @salida = LAST_INSERT_ID();

INSERT INTO puerto (nombre, pais)
VALUES ('Puerto Destino Prueba', 'US');
SET @destino_puerto = LAST_INSERT_ID();

INSERT INTO contenedor_maritimo
(numero_contenedor, id_naviera, temperatura_min_c, temperatura_max_c)
VALUES ('CONTENEDOR-PRUEBA', @naviera, 4, 8);
SET @contenedor = LAST_INSERT_ID();

CALL sp_consolidar_pallet(@pallet, @contenedor);

INSERT INTO embarque_maritimo
(codigo_embarque, id_contenedor, id_puerto_salida,
 id_puerto_destino, fecha_programada)
VALUES
('EMBARQUE-PRUEBA', @contenedor, @salida,
 @destino_puerto, '2026-11-04 12:00:00');

CALL sp_despachar_contenedor(@contenedor);

SELECT * FROM vw_trazabilidad_reversa
WHERE codigo_pallet = 'PALLET-PRUEBA-FINAL';

SELECT * FROM vw_liquidacion_productor
WHERE id_productor = @productor;

SELECT numero_contenedor, estado
FROM contenedor_maritimo
WHERE id_contenedor = @contenedor;

/*
Pruebas con datos incorrectos.
Ejecutar cada consulta por separado.

SELECT fn_peso_neto(100, 80, 30);

SELECT fn_tarifa_kg(999999, 999999, '2026-11-04');

CALL sp_registrar_ticket(
    'TICKET-ERROR', 999999,
    '2026-11-04', '2026-11-04 10:00:00', 'ABC-123'
);

CALL sp_registrar_control_calidad(
    999999, NOW(), 100, 5, 10, 999999, 999999
);

CALL sp_registrar_liquidacion(999999, NOW());

CALL sp_agregar_caja_pallet(999999, 999999);

CALL sp_consolidar_pallet(999999, 999999);

CALL sp_despachar_contenedor(999999);
*/