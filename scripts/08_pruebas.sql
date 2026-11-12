SET NAMES utf8mb4;
USE agro_trazabilidad;

DROP TEMPORARY TABLE IF EXISTS tmp_resultado_pruebas;
CREATE TEMPORARY TABLE tmp_resultado_pruebas (
    n INT AUTO_INCREMENT PRIMARY KEY,
    modulo VARCHAR(10) NOT NULL,
    prueba VARCHAR(160) NOT NULL,
    resultado VARCHAR(4) NOT NULL,
    detalle VARCHAR(300) NULL
);

SOURCE pruebas/pruebas_campo.sql;
SOURCE pruebas/pruebas_acopio.sql;

-- ---------------------------------------------------------------------
-- RESUMEN
-- ---------------------------------------------------------------------
SELECT modulo, resultado, COUNT(*) AS cantidad
FROM tmp_resultado_pruebas
GROUP BY modulo, resultado
ORDER BY modulo, resultado;

SELECT COUNT(*) AS pruebas_totales,
       SUM(resultado = 'PASS') AS aprobadas,
       SUM(resultado = 'FAIL') AS fallidas
FROM tmp_resultado_pruebas;

-- Si hay fallas, se listan aquí (vacío = todas aprobadas)
SELECT modulo, prueba, detalle FROM tmp_resultado_pruebas WHERE resultado = 'FAIL';

-- Los datos de prueba (prefijo TST-) deben haberse borrado
SELECT (SELECT COUNT(*) FROM productor WHERE numero_documento LIKE 'TST-%') AS productores_de_prueba_restantes,
       (SELECT COUNT(*) FROM ticket_acopio WHERE codigo_ticket LIKE 'TST-%') AS tickets_de_prueba_restantes;

DROP TEMPORARY TABLE IF EXISTS tmp_resultado_pruebas;
