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

GRANT USAGE ON *.* TO 'rol_productor';

GRANT SELECT, SHOW VIEW, TRIGGER, EVENT, LOCK TABLES ON agro_trazabilidad.* TO 'rol_respaldo';
GRANT SHOW_ROUTINE ON *.* TO 'rol_respaldo';

-- ---------------------------------------------------------------------
-- 3. USUARIOS DE EJEMPLO
--    Bloqueo temporal tras 5 intentos fallidos
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
