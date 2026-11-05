-- =====================================================================
-- Archivo   : 02_seguridad.sql
-- Dueño     : Laurente
-- Contenido : Roles, usuarios, privilegios y política de respaldo.
-- Requiere  : MySQL 8.0.20 o superior y haber ejecutado 01_esquema.sql.
-- Nota      : Las contraseñas son de EJEMPLO. En un entorno real se cambian
--             antes de poner la base en producción.
-- =====================================================================

SET NAMES utf8mb4;
USE agro_trazabilidad;

-- ---------------------------------------------------------------------
-- 1. ROLES (uno por actor del sistema, más administración y respaldo)
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS 'rol_admin_bd';    -- administra la base de datos
CREATE ROLE IF NOT EXISTS 'rol_productor';   -- pequeño productor / cooperativa (solo consulta)
CREATE ROLE IF NOT EXISTS 'rol_inspector';   -- inspector de campo y control de calidad
CREATE ROLE IF NOT EXISTS 'rol_planta';      -- planta de procesamiento / exportadora
CREATE ROLE IF NOT EXISTS 'rol_auditor';     -- auditoría (solo lectura)
CREATE ROLE IF NOT EXISTS 'rol_respaldo';    -- cuenta técnica para copias de seguridad

-- ---------------------------------------------------------------------
-- 2. PRIVILEGIOS POR ROL (mínimo necesario)
--    Principio: los actores operativos NO modifican tablas directamente;
--    registran información mediante los procedimientos almacenados (sp_*),
--    que validan las reglas de negocio. Por eso reciben EXECUTE y SELECT,
--    pero no INSERT, UPDATE ni DELETE.
--    Importante: los procedimientos deben crearse con SQL SECURITY DEFINER
--    (valor por defecto) y con una cuenta que sí tenga permisos de escritura,
--    para que funcionen aunque quien los llame no pueda escribir en las tablas.
-- ---------------------------------------------------------------------
GRANT ALL PRIVILEGES ON agro_trazabilidad.* TO 'rol_admin_bd';

GRANT SELECT, EXECUTE ON agro_trazabilidad.* TO 'rol_inspector';
GRANT SELECT, EXECUTE ON agro_trazabilidad.* TO 'rol_planta';

GRANT SELECT ON agro_trazabilidad.* TO 'rol_auditor';

-- El productor solo debe ver sus propios datos: se le dará acceso únicamente
-- a vistas, no al esquema completo. Descomentar cuando existan las vistas
-- (nombres según el plan de objetos; ajustar si cambian):
-- GRANT SELECT ON agro_trazabilidad.vw_liquidacion_productor    TO 'rol_productor';
-- GRANT SELECT ON agro_trazabilidad.vw_certificaciones_vigentes TO 'rol_productor';
GRANT USAGE ON *.* TO 'rol_productor';

-- Afinar cuando existan los procedimientos: en lugar de EXECUTE sobre todo el
-- esquema, dar solo los que cada rol necesita, por ejemplo:
-- GRANT EXECUTE ON PROCEDURE agro_trazabilidad.sp_emitir_acta_inspeccion TO 'rol_inspector';
-- GRANT EXECUTE ON PROCEDURE agro_trazabilidad.sp_registrar_ticket       TO 'rol_planta';

-- Cuenta de respaldo: lectura y los permisos que exige mysqldump.
GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES ON agro_trazabilidad.* TO 'rol_respaldo';
GRANT SHOW_ROUTINE ON *.* TO 'rol_respaldo';

-- ---------------------------------------------------------------------
-- 3. USUARIOS DE EJEMPLO
--    Bloqueo temporal tras 5 intentos fallidos (MySQL 8.0.19+).
-- ---------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'usr_admin'@'localhost'
  IDENTIFIED BY 'Cambiar#Admin2026'
  FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
CREATE USER IF NOT EXISTS 'usr_inspector01'@'localhost'
  IDENTIFIED BY 'Cambiar#Inspector2026'
  FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
CREATE USER IF NOT EXISTS 'usr_planta01'@'localhost'
  IDENTIFIED BY 'Cambiar#Planta2026'
  FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
CREATE USER IF NOT EXISTS 'usr_productor01'@'localhost'
  IDENTIFIED BY 'Cambiar#Productor2026'
  FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
CREATE USER IF NOT EXISTS 'usr_auditor01'@'localhost'
  IDENTIFIED BY 'Cambiar#Auditor2026'
  FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;
CREATE USER IF NOT EXISTS 'usr_respaldo'@'localhost'
  IDENTIFIED BY 'Cambiar#Respaldo2026'
  FAILED_LOGIN_ATTEMPTS 5 PASSWORD_LOCK_TIME 1;

-- Asignar roles y dejarlos activos al iniciar sesión
GRANT 'rol_admin_bd'  TO 'usr_admin'@'localhost';
GRANT 'rol_inspector' TO 'usr_inspector01'@'localhost';
GRANT 'rol_planta'    TO 'usr_planta01'@'localhost';
GRANT 'rol_productor' TO 'usr_productor01'@'localhost';
GRANT 'rol_auditor'   TO 'usr_auditor01'@'localhost';
GRANT 'rol_respaldo'  TO 'usr_respaldo'@'localhost';

SET DEFAULT ROLE 'rol_admin_bd'  TO 'usr_admin'@'localhost';
SET DEFAULT ROLE 'rol_inspector' TO 'usr_inspector01'@'localhost';
SET DEFAULT ROLE 'rol_planta'    TO 'usr_planta01'@'localhost';
SET DEFAULT ROLE 'rol_productor' TO 'usr_productor01'@'localhost';
SET DEFAULT ROLE 'rol_auditor'   TO 'usr_auditor01'@'localhost';
SET DEFAULT ROLE 'rol_respaldo'  TO 'usr_respaldo'@'localhost';

-- ---------------------------------------------------------------------
-- 4. POLÍTICA DE RESPALDO (estrategia y mecanismos)
-- ---------------------------------------------------------------------
-- Estrategia:
--   * Copia completa diaria con mysqldump, fuera del horario de acopio.
--   * Registro binario (binary log) activo para recuperar la base hasta un
--     punto exacto en el tiempo (por ejemplo, justo antes de un error).
--   * Retención sugerida: 7 copias diarias, 4 semanales y 3 mensuales.
--   * Guardar una copia fuera del servidor (nube o disco externo) y limitar
--     el acceso a los archivos de respaldo.
--   * Probar la restauración en una base de prueba al menos una vez al mes.
--
-- Copia (incluye procedimientos, funciones, triggers y eventos), con la
-- cuenta usr_respaldo; ejecutar desde la terminal, no desde MySQL:
--   mysqldump -u usr_respaldo -p --single-transaction --routines --triggers --events
--             --no-tablespaces --default-character-set=utf8mb4
--             agro_trazabilidad > respaldo_agro_AAAAMMDD.sql
--
-- Restauración en una base vacía:
--   mysql -u usr_admin -p --default-character-set=utf8mb4 agro_trazabilidad < respaldo_agro_AAAAMMDD.sql
--
-- Automatización: tarea programada (cron en Linux o Programador de tareas en
-- Windows) que ejecute la copia a diario y borre las que superen la retención.
--
-- Seguridad complementaria:
--   * Cambiar todas las contraseñas de ejemplo antes de producción.
--   * Aceptar conexiones solo desde los equipos necesarios (no usar '%').
--   * Registrar cambios de datos sensibles con triggers de auditoría.