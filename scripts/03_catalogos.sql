-- =====================================================================
-- Archivo   : 03_catalogos.sql
-- Dueño     : Laurente
-- Contenido : Registros de las tablas de referencia definidas en
--             01_esquema.sql (sección A) y datos de apoyo para las cargas.
-- Requiere  : 01_esquema.sql ejecutado (nombres de tablas y columnas tomados
--             de la versión preliminar de Matias).
-- Se ejecuta una sola vez sobre una base limpia.
--
-- Datos ficticios: los productos fitosanitarios, sus carencias, las tarifas y
-- los inspectores son valores de prueba del curso; no son referencia
-- agronómica ni de límites de residuos. Los códigos ubigeo corresponden a
-- distritos reales de zonas paltera (La Libertad, Lima e Ica).
--
-- No incluye las certificaciones: en el esquema son registros por parcela
-- (tabla certificacion) y las carga 06_carga_campo.sql.
-- =====================================================================

SET NAMES utf8mb4;
USE agro_trazabilidad;

-- ---------------------------------------------------------------------
-- Tipos de asociación del productor (Sección IV-A)
-- ---------------------------------------------------------------------
INSERT INTO tipo_asociacion (nombre) VALUES
  ('Socio de cooperativa'),
  ('Independiente'),
  ('Proveedor directo');

-- ---------------------------------------------------------------------
-- Entidades financieras (cuenta bancaria para liquidaciones)
-- ---------------------------------------------------------------------
INSERT INTO entidad_financiera (nombre) VALUES
  ('Banco de Crédito del Perú'),
  ('BBVA Perú'),
  ('Interbank'),
  ('Scotiabank Perú'),
  ('Banco de la Nación'),
  ('Agrobanco'),
  ('Mibanco'),
  ('Caja Trujillo'),
  ('Caja Piura');

-- ---------------------------------------------------------------------
-- Ubigeos (código INEI de 6 dígitos)
-- ---------------------------------------------------------------------
INSERT INTO ubigeo (codigo_ubigeo, departamento, provincia, distrito) VALUES
  ('130101', 'La Libertad', 'Trujillo',  'Trujillo'),
  ('130401', 'La Libertad', 'Chepén',    'Chepén'),
  ('131201', 'La Libertad', 'Virú',      'Virú'),
  ('131202', 'La Libertad', 'Virú',      'Chao'),
  ('131203', 'La Libertad', 'Virú',      'Guadalupito'),
  ('150201', 'Lima',        'Barranca',  'Barranca'),
  ('150501', 'Lima',        'Cañete',    'San Vicente de Cañete'),
  ('150601', 'Lima',        'Huaral',    'Huaral'),
  ('150801', 'Lima',        'Huaura',    'Huacho'),
  ('110101', 'Ica',         'Ica',       'Ica'),
  ('110201', 'Ica',         'Chincha',   'Chincha Alta'),
  ('110301', 'Ica',         'Nasca',     'Nasca'),
  ('110501', 'Ica',         'Pisco',     'Pisco');

-- ---------------------------------------------------------------------
-- Productos fitosanitarios y su periodo de carencia en días (FICTICIOS)
-- Base del cálculo: fecha de liberación = fecha de aplicación + carencia.
-- registro_senasa queda en NULL: no se inventan números de registro.
-- ---------------------------------------------------------------------
INSERT INTO producto_fitosanitario (nombre, registro_senasa, periodo_carencia_dias) VALUES
  ('Mancozeb',               NULL, 14),
  ('Oxicloruro de cobre',    NULL,  7),
  ('Hidróxido de cobre',     NULL,  7),
  ('Azoxistrobina',          NULL, 21),
  ('Imidacloprid',           NULL, 21),
  ('Abamectina',             NULL, 10),
  ('Spinosad',               NULL,  7),
  ('Bacillus thuringiensis', NULL,  1),
  ('Aceite agrícola',        NULL,  3),
  ('Glifosato',              NULL, 30);

-- ---------------------------------------------------------------------
-- Navieras (Sección IV-D)
-- ---------------------------------------------------------------------
INSERT INTO naviera (nombre) VALUES
  ('Maersk'),
  ('MSC'),
  ('CMA CGM'),
  ('Hapag-Lloyd'),
  ('COSCO Shipping'),
  ('Ocean Network Express (ONE)'),
  ('Evergreen');

-- ---------------------------------------------------------------------
-- Puertos de salida (Perú) y de destino; país en código ISO alfa-2
-- ---------------------------------------------------------------------
INSERT INTO puerto (nombre, pais) VALUES
  ('Chancay',     'PE'),
  ('Callao',      'PE'),
  ('Paita',       'PE'),
  ('Rotterdam',   'NL'),
  ('Algeciras',   'ES'),
  ('Hamburgo',    'DE'),
  ('Los Ángeles', 'US'),
  ('Shanghái',    'CN');

-- ---------------------------------------------------------------------
-- Calibres y destinos comerciales (Sección IV-C)
-- Calibre menor = fruta más grande y de mejor precio.
-- ---------------------------------------------------------------------
INSERT INTO calibre (codigo, descripcion) VALUES
  ('12', 'Calibre 12'),
  ('14', 'Calibre 14'),
  ('16', 'Calibre 16'),
  ('18', 'Calibre 18'),
  ('20', 'Calibre 20'),
  ('22', 'Calibre 22'),
  ('24', 'Calibre 24');

INSERT INTO destino_comercial (nombre, descripcion) VALUES
  ('EXPORTACION', 'Mercado de exportación'),
  ('NACIONAL',    'Mercado nacional');

-- ---------------------------------------------------------------------
-- Tarifas por kilogramo en soles (FICTICIAS), según calibre y destino.
-- Se enlazan por código y nombre, sin depender de los ids generados.
-- ---------------------------------------------------------------------
INSERT INTO tarifa (id_calibre, id_destino_comercial, precio_kg_pen, vigencia_desde)
SELECT c.id_calibre, d.id_destino_comercial, v.precio, '2025-01-01'
FROM (
  SELECT '12' AS cod, 'EXPORTACION' AS dest, 5.20 AS precio
  UNION ALL SELECT '14' AS cod, 'EXPORTACION' AS dest, 5.00 AS precio
  UNION ALL SELECT '16' AS cod, 'EXPORTACION' AS dest, 4.80 AS precio
  UNION ALL SELECT '18' AS cod, 'EXPORTACION' AS dest, 4.50 AS precio
  UNION ALL SELECT '20' AS cod, 'EXPORTACION' AS dest, 4.20 AS precio
  UNION ALL SELECT '22' AS cod, 'EXPORTACION' AS dest, 3.80 AS precio
  UNION ALL SELECT '24' AS cod, 'EXPORTACION' AS dest, 3.40 AS precio
  UNION ALL SELECT '12' AS cod, 'NACIONAL' AS dest, 3.00 AS precio
  UNION ALL SELECT '14' AS cod, 'NACIONAL' AS dest, 2.90 AS precio
  UNION ALL SELECT '16' AS cod, 'NACIONAL' AS dest, 2.80 AS precio
  UNION ALL SELECT '18' AS cod, 'NACIONAL' AS dest, 2.60 AS precio
  UNION ALL SELECT '20' AS cod, 'NACIONAL' AS dest, 2.40 AS precio
  UNION ALL SELECT '22' AS cod, 'NACIONAL' AS dest, 2.10 AS precio
  UNION ALL SELECT '24' AS cod, 'NACIONAL' AS dest, 1.90 AS precio
) AS v
JOIN calibre c            ON c.codigo = v.cod
JOIN destino_comercial d  ON d.nombre = v.dest;

-- ---------------------------------------------------------------------
-- Inspectores de prueba (FICTICIOS): los necesitan las inspecciones
-- pre-cosecha que carga 06_carga_campo.sql. El último NO está autorizado,
-- para probar la regla de inspector autorizado.
-- ---------------------------------------------------------------------
INSERT INTO inspector (numero_documento, nombre_completo, autorizado) VALUES
  ('40000001', 'Inspector Prueba 01', TRUE),
  ('40000002', 'Inspector Prueba 02', TRUE),
  ('40000003', 'Inspector Prueba 03', TRUE),
  ('40000004', 'Inspector Prueba 04', TRUE),
  ('40000005', 'Inspector Prueba 05', TRUE),
  ('40000006', 'Inspector Prueba 06 (sin autorización)', FALSE);
