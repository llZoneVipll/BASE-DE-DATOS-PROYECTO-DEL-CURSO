-- =====================================================================
-- Archivo   : 01_esquema.sql
-- Responsable: Matias
-- Proyecto  : Sistema de Trazabilidad Agroexportadora (UNMSM, BD I)
-- Estado    : PRELIMINAR - contrato de tablas para revision del equipo.
-- Motor     : MySQL 8.0.16+ / InnoDB / utf8mb4
-- Alcance   : DDL; los datos de catalogos corresponden al script 03 y
--             los procedimientos, funciones y triggers a los scripts 04/05.
-- =====================================================================
-- DECISIONES PROVISIONALES QUE EL EQUIPO DEBE CONFIRMAR:
-- 1) Cada ticket de acopio corresponde a un lote agricola.
-- 2) Cada caja proviene de un ticket; un pallet puede reunir varias cajas.
-- 3) Un pallet tiene como maximo un contenedor asignado a la vez. Si se
--    exige historial de movimientos, se ampliara el modelo.
-- 4) Al habilitar la cosecha se verificaran certificaciones vigentes,
--    inspeccion aprobada y la carencia maxima de los tratamientos.
-- 5) Las reglas entre tablas y el estado DESPACHADO requieren triggers o
--    procedimientos de los responsables de 04/05; este DDL no las valida.
-- 6) Los importes y pesos se expresan en soles y kilogramos, salvo acuerdo.
-- =====================================================================

SET NAMES utf8mb4;
CREATE DATABASE IF NOT EXISTS agro_trazabilidad
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE agro_trazabilidad;

-- ---------------------------------------------------------------------
-- A. TABLAS DE REFERENCIA (el script 03 insertara sus registros)
-- ---------------------------------------------------------------------
CREATE TABLE tipo_asociacion (
  id_tipo_asociacion INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nombre VARCHAR(80) NOT NULL,
  PRIMARY KEY (id_tipo_asociacion),
  CONSTRAINT uq_tipo_asociacion_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE entidad_financiera (
  id_entidad_financiera INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nombre VARCHAR(120) NOT NULL,
  PRIMARY KEY (id_entidad_financiera),
  CONSTRAINT uq_entidad_financiera_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE ubigeo (
  codigo_ubigeo CHAR(6) NOT NULL,
  departamento VARCHAR(80) NOT NULL,
  provincia VARCHAR(80) NOT NULL,
  distrito VARCHAR(80) NOT NULL,
  PRIMARY KEY (codigo_ubigeo),
  CONSTRAINT ck_ubigeo_formato CHECK (codigo_ubigeo REGEXP '^[0-9]{6}$')
) ENGINE=InnoDB;

CREATE TABLE producto_fitosanitario (
  id_producto_fitosanitario INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nombre VARCHAR(120) NOT NULL,
  registro_senasa VARCHAR(60) NULL,
  periodo_carencia_dias INT UNSIGNED NOT NULL,
  PRIMARY KEY (id_producto_fitosanitario),
  CONSTRAINT uq_producto_fitosanitario_nombre UNIQUE (nombre),
  CONSTRAINT uq_producto_fitosanitario_registro UNIQUE (registro_senasa)
) ENGINE=InnoDB;

CREATE TABLE naviera (
  id_naviera INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nombre VARCHAR(120) NOT NULL,
  PRIMARY KEY (id_naviera),
  CONSTRAINT uq_naviera_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

CREATE TABLE puerto (
  id_puerto INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nombre VARCHAR(120) NOT NULL,
  pais CHAR(2) NOT NULL COMMENT 'Codigo ISO 3166-1 alfa-2',
  PRIMARY KEY (id_puerto),
  CONSTRAINT uq_puerto_nombre_pais UNIQUE (nombre, pais)
) ENGINE=InnoDB;

CREATE TABLE calibre (
  id_calibre INT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo VARCHAR(30) NOT NULL,
  descripcion VARCHAR(120) NULL,
  PRIMARY KEY (id_calibre),
  CONSTRAINT uq_calibre_codigo UNIQUE (codigo)
) ENGINE=InnoDB;

CREATE TABLE destino_comercial (
  id_destino_comercial INT UNSIGNED NOT NULL AUTO_INCREMENT,
  nombre VARCHAR(80) NOT NULL,
  descripcion VARCHAR(200) NULL,
  PRIMARY KEY (id_destino_comercial),
  CONSTRAINT uq_destino_comercial_nombre UNIQUE (nombre)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- B. PRODUCTORES Y PARCELAS
-- ---------------------------------------------------------------------
CREATE TABLE productor (
  id_productor BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  tipo_documento VARCHAR(15) NOT NULL,
  numero_documento VARCHAR(20) NOT NULL,
  nombre_completo VARCHAR(160) NOT NULL,
  telefono VARCHAR(20) NULL,
  id_tipo_asociacion INT UNSIGNED NOT NULL,
  id_entidad_financiera INT UNSIGNED NULL,
  numero_cuenta VARCHAR(34) NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id_productor),
  CONSTRAINT uq_productor_documento UNIQUE (tipo_documento, numero_documento),
  KEY idx_productor_tipo_asociacion (id_tipo_asociacion),
  KEY idx_productor_entidad_financiera (id_entidad_financiera),
  CONSTRAINT fk_productor_tipo_asociacion FOREIGN KEY (id_tipo_asociacion)
    REFERENCES tipo_asociacion (id_tipo_asociacion),
  CONSTRAINT fk_productor_entidad_financiera FOREIGN KEY (id_entidad_financiera)
    REFERENCES entidad_financiera (id_entidad_financiera),
  CONSTRAINT ck_productor_activo CHECK (activo IN (0, 1))
) ENGINE=InnoDB;

CREATE TABLE parcela (
  id_parcela BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_productor BIGINT UNSIGNED NOT NULL,
  codigo_catastral VARCHAR(60) NOT NULL,
  codigo_ubigeo CHAR(6) NOT NULL,
  sector_agricola VARCHAR(120) NOT NULL,
  poligono POLYGON NOT NULL SRID 4326,
  PRIMARY KEY (id_parcela),
  CONSTRAINT uq_parcela_codigo_catastral UNIQUE (codigo_catastral),
  KEY idx_parcela_productor (id_productor),
  KEY idx_parcela_ubigeo (codigo_ubigeo),
  SPATIAL INDEX idx_parcela_poligono (poligono),
  CONSTRAINT fk_parcela_productor FOREIGN KEY (id_productor)
    REFERENCES productor (id_productor),
  CONSTRAINT fk_parcela_ubigeo FOREIGN KEY (codigo_ubigeo)
    REFERENCES ubigeo (codigo_ubigeo)
) ENGINE=InnoDB;

CREATE TABLE lote_agricola (
  id_lote BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_parcela BIGINT UNSIGNED NOT NULL,
  codigo_lote VARCHAR(40) NOT NULL,
  especie VARCHAR(80) NOT NULL,
  variedad VARCHAR(80) NULL,
  fecha_siembra DATE NOT NULL,
  fecha_ultima_poda DATE NULL,
  rendimiento_estimado_tn DECIMAL(12,3) NULL,
  estado ENUM('REGISTRADO', 'EN_INSPECCION',
              'HABILITADO_PARA_COSECHA', 'BLOQUEADO')
    NOT NULL DEFAULT 'REGISTRADO',
  PRIMARY KEY (id_lote),
  CONSTRAINT uq_lote_agricola_parcela_codigo UNIQUE (id_parcela, codigo_lote),
  CONSTRAINT fk_lote_agricola_parcela FOREIGN KEY (id_parcela)
    REFERENCES parcela (id_parcela),
  CONSTRAINT ck_lote_agricola_rendimiento CHECK (
    rendimiento_estimado_tn IS NULL OR rendimiento_estimado_tn >= 0
  )
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- C. CERTIFICACION, SANIDAD E INSPECCION PRECOSECHA
-- ---------------------------------------------------------------------
CREATE TABLE certificacion (
  id_certificacion BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_parcela BIGINT UNSIGNED NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  codigo_certificacion VARCHAR(80) NOT NULL,
  entidad_certificadora VARCHAR(120) NOT NULL,
  fecha_inicio DATE NOT NULL,
  fecha_fin DATE NOT NULL,
  PRIMARY KEY (id_certificacion),
  CONSTRAINT uq_certificacion_codigo UNIQUE (codigo_certificacion),
  KEY idx_certificacion_parcela (id_parcela),
  CONSTRAINT fk_certificacion_parcela FOREIGN KEY (id_parcela)
    REFERENCES parcela (id_parcela),
  CONSTRAINT ck_certificacion_fechas CHECK (fecha_fin >= fecha_inicio)
) ENGINE=InnoDB;

CREATE TABLE inspector (
  id_inspector BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  numero_documento VARCHAR(20) NOT NULL,
  nombre_completo VARCHAR(160) NOT NULL,
  autorizado BOOLEAN NOT NULL DEFAULT TRUE,
  PRIMARY KEY (id_inspector),
  CONSTRAINT uq_inspector_documento UNIQUE (numero_documento),
  CONSTRAINT ck_inspector_autorizado CHECK (autorizado IN (0, 1))
) ENGINE=InnoDB;

CREATE TABLE tratamiento_fitosanitario (
  id_tratamiento BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_lote BIGINT UNSIGNED NOT NULL,
  id_producto_fitosanitario INT UNSIGNED NOT NULL,
  fecha_aplicacion DATETIME NOT NULL,
  periodo_carencia_dias_aplicado INT UNSIGNED NOT NULL
    COMMENT 'Copia historica de la carencia vigente al aplicar',
  observaciones VARCHAR(500) NULL,
  PRIMARY KEY (id_tratamiento),
  KEY idx_tratamiento_lote_fecha (id_lote, fecha_aplicacion),
  KEY idx_tratamiento_producto (id_producto_fitosanitario),
  CONSTRAINT fk_tratamiento_lote FOREIGN KEY (id_lote)
    REFERENCES lote_agricola (id_lote),
  CONSTRAINT fk_tratamiento_producto FOREIGN KEY (id_producto_fitosanitario)
    REFERENCES producto_fitosanitario (id_producto_fitosanitario)
) ENGINE=InnoDB;

CREATE TABLE inspeccion_pre_cosecha (
  id_inspeccion BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_lote BIGINT UNSIGNED NOT NULL,
  id_inspector BIGINT UNSIGNED NOT NULL,
  fecha_inspeccion DATETIME NOT NULL,
  resultado ENUM('PENDIENTE', 'APROBADA', 'RECHAZADA')
    NOT NULL DEFAULT 'PENDIENTE',
  observaciones VARCHAR(500) NULL,
  PRIMARY KEY (id_inspeccion),
  KEY idx_inspeccion_lote_fecha (id_lote, fecha_inspeccion),
  KEY idx_inspeccion_inspector (id_inspector),
  CONSTRAINT fk_inspeccion_lote FOREIGN KEY (id_lote)
    REFERENCES lote_agricola (id_lote),
  CONSTRAINT fk_inspeccion_inspector FOREIGN KEY (id_inspector)
    REFERENCES inspector (id_inspector)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- D. ACOPIO, CALIDAD Y LIQUIDACION
-- ---------------------------------------------------------------------
CREATE TABLE ticket_acopio (
  id_ticket BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo_ticket VARCHAR(50) NOT NULL,
  id_lote BIGINT UNSIGNED NOT NULL,
  fecha_cosecha DATE NOT NULL,
  fecha_recepcion DATETIME NOT NULL,
  placa_vehiculo VARCHAR(15) NULL,
  estado ENUM('RECIBIDO', 'EVALUADO', 'LIQUIDADO')
    NOT NULL DEFAULT 'RECIBIDO',
  PRIMARY KEY (id_ticket),
  CONSTRAINT uq_ticket_acopio_codigo UNIQUE (codigo_ticket),
  KEY idx_ticket_acopio_lote (id_lote),
  CONSTRAINT fk_ticket_acopio_lote FOREIGN KEY (id_lote)
    REFERENCES lote_agricola (id_lote),
  CONSTRAINT ck_ticket_acopio_fechas CHECK (
    fecha_cosecha <= DATE(fecha_recepcion)
  )
) ENGINE=InnoDB;

CREATE TABLE control_calidad (
  id_control_calidad BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_ticket BIGINT UNSIGNED NOT NULL,
  fecha_control DATETIME NOT NULL,
  peso_bruto_kg DECIMAL(12,3) NOT NULL,
  tara_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  descarte_kg DECIMAL(12,3) NOT NULL DEFAULT 0,
  peso_neto_pagable_kg DECIMAL(12,3)
    GENERATED ALWAYS AS (peso_bruto_kg - tara_kg - descarte_kg) STORED,
  id_calibre INT UNSIGNED NOT NULL,
  id_destino_comercial INT UNSIGNED NOT NULL,
  observaciones VARCHAR(500) NULL,
  PRIMARY KEY (id_control_calidad),
  CONSTRAINT uq_control_calidad_ticket UNIQUE (id_ticket),
  KEY idx_control_calidad_calibre (id_calibre),
  KEY idx_control_calidad_destino (id_destino_comercial),
  CONSTRAINT fk_control_calidad_ticket FOREIGN KEY (id_ticket)
    REFERENCES ticket_acopio (id_ticket),
  CONSTRAINT fk_control_calidad_calibre FOREIGN KEY (id_calibre)
    REFERENCES calibre (id_calibre),
  CONSTRAINT fk_control_calidad_destino FOREIGN KEY (id_destino_comercial)
    REFERENCES destino_comercial (id_destino_comercial),
  CONSTRAINT ck_control_calidad_pesos CHECK (
    peso_bruto_kg > 0 AND tara_kg >= 0 AND descarte_kg >= 0
    AND tara_kg + descarte_kg <= peso_bruto_kg
  )
) ENGINE=InnoDB;

CREATE TABLE tarifa (
  id_tarifa BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_calibre INT UNSIGNED NOT NULL,
  id_destino_comercial INT UNSIGNED NOT NULL,
  precio_kg_pen DECIMAL(12,4) NOT NULL,
  vigencia_desde DATE NOT NULL,
  vigencia_hasta DATE NULL,
  PRIMARY KEY (id_tarifa),
  KEY idx_tarifa_calibre_destino (id_calibre, id_destino_comercial),
  CONSTRAINT fk_tarifa_calibre FOREIGN KEY (id_calibre)
    REFERENCES calibre (id_calibre),
  CONSTRAINT fk_tarifa_destino FOREIGN KEY (id_destino_comercial)
    REFERENCES destino_comercial (id_destino_comercial),
  CONSTRAINT ck_tarifa_precio CHECK (precio_kg_pen > 0),
  CONSTRAINT ck_tarifa_vigencia CHECK (
    vigencia_hasta IS NULL OR vigencia_hasta >= vigencia_desde
  )
) ENGINE=InnoDB;

CREATE TABLE liquidacion (
  id_liquidacion BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  id_ticket BIGINT UNSIGNED NOT NULL,
  id_tarifa BIGINT UNSIGNED NOT NULL,
  fecha_liquidacion DATETIME NOT NULL,
  peso_neto_pagable_kg DECIMAL(12,3) NOT NULL,
  precio_kg_aplicado_pen DECIMAL(12,4) NOT NULL,
  importe_total_pen DECIMAL(14,2)
    GENERATED ALWAYS AS (
      ROUND(peso_neto_pagable_kg * precio_kg_aplicado_pen, 2)
    ) STORED,
  estado ENUM('PENDIENTE', 'PAGADA', 'ANULADA')
    NOT NULL DEFAULT 'PENDIENTE',
  PRIMARY KEY (id_liquidacion),
  CONSTRAINT uq_liquidacion_ticket UNIQUE (id_ticket),
  KEY idx_liquidacion_tarifa (id_tarifa),
  CONSTRAINT fk_liquidacion_ticket FOREIGN KEY (id_ticket)
    REFERENCES ticket_acopio (id_ticket),
  CONSTRAINT fk_liquidacion_tarifa FOREIGN KEY (id_tarifa)
    REFERENCES tarifa (id_tarifa),
  CONSTRAINT ck_liquidacion_peso CHECK (peso_neto_pagable_kg >= 0),
  CONSTRAINT ck_liquidacion_precio CHECK (precio_kg_aplicado_pen > 0)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- E. EMPAQUE, PALLETS, CONTENEDORES Y EMBARQUE
-- ---------------------------------------------------------------------
CREATE TABLE contenedor_maritimo (
  id_contenedor BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  numero_contenedor VARCHAR(20) NOT NULL,
  id_naviera INT UNSIGNED NULL,
  temperatura_min_c DECIMAL(5,2) NULL,
  temperatura_max_c DECIMAL(5,2) NULL,
  estado ENUM('PLANIFICADO', 'EN_CARGA', 'DESPACHADO')
    NOT NULL DEFAULT 'PLANIFICADO',
  PRIMARY KEY (id_contenedor),
  CONSTRAINT uq_contenedor_numero UNIQUE (numero_contenedor),
  KEY idx_contenedor_naviera (id_naviera),
  CONSTRAINT fk_contenedor_naviera FOREIGN KEY (id_naviera)
    REFERENCES naviera (id_naviera),
  CONSTRAINT ck_contenedor_temperatura CHECK (
    (temperatura_min_c IS NULL AND temperatura_max_c IS NULL)
    OR (temperatura_min_c IS NOT NULL AND temperatura_max_c IS NOT NULL
        AND temperatura_min_c <= temperatura_max_c)
  )
) ENGINE=InnoDB;

CREATE TABLE pallet (
  id_pallet BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo_pallet VARCHAR(80) NOT NULL COMMENT 'Codigo unico QR/GS1',
  fecha_armado DATETIME NOT NULL,
  id_contenedor BIGINT UNSIGNED NULL,
  estado ENUM('ARMADO', 'ASIGNADO', 'DESPACHADO')
    NOT NULL DEFAULT 'ARMADO',
  PRIMARY KEY (id_pallet),
  CONSTRAINT uq_pallet_codigo UNIQUE (codigo_pallet),
  KEY idx_pallet_contenedor (id_contenedor),
  CONSTRAINT fk_pallet_contenedor FOREIGN KEY (id_contenedor)
    REFERENCES contenedor_maritimo (id_contenedor),
  CONSTRAINT ck_pallet_asignacion CHECK (
    estado NOT IN ('ASIGNADO', 'DESPACHADO') OR id_contenedor IS NOT NULL
  )
) ENGINE=InnoDB;

CREATE TABLE caja (
  id_caja BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo_caja VARCHAR(80) NOT NULL COMMENT 'Codigo de trazabilidad',
  id_ticket BIGINT UNSIGNED NOT NULL,
  id_pallet BIGINT UNSIGNED NULL,
  fecha_empaque DATETIME NOT NULL,
  peso_neto_kg DECIMAL(10,3) NULL,
  PRIMARY KEY (id_caja),
  CONSTRAINT uq_caja_codigo UNIQUE (codigo_caja),
  KEY idx_caja_ticket (id_ticket),
  KEY idx_caja_pallet (id_pallet),
  CONSTRAINT fk_caja_ticket FOREIGN KEY (id_ticket)
    REFERENCES ticket_acopio (id_ticket),
  CONSTRAINT fk_caja_pallet FOREIGN KEY (id_pallet)
    REFERENCES pallet (id_pallet),
  CONSTRAINT ck_caja_peso CHECK (
    peso_neto_kg IS NULL OR peso_neto_kg > 0
  )
) ENGINE=InnoDB;

CREATE TABLE embarque_maritimo (
  id_embarque BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  codigo_embarque VARCHAR(60) NOT NULL,
  id_contenedor BIGINT UNSIGNED NOT NULL,
  id_puerto_salida INT UNSIGNED NOT NULL,
  id_puerto_destino INT UNSIGNED NOT NULL,
  fecha_programada DATETIME NOT NULL,
  fecha_despacho DATETIME NULL,
  PRIMARY KEY (id_embarque),
  CONSTRAINT uq_embarque_codigo UNIQUE (codigo_embarque),
  CONSTRAINT uq_embarque_contenedor UNIQUE (id_contenedor),
  KEY idx_embarque_puerto_salida (id_puerto_salida),
  KEY idx_embarque_puerto_destino (id_puerto_destino),
  CONSTRAINT fk_embarque_contenedor FOREIGN KEY (id_contenedor)
    REFERENCES contenedor_maritimo (id_contenedor),
  CONSTRAINT fk_embarque_puerto_salida FOREIGN KEY (id_puerto_salida)
    REFERENCES puerto (id_puerto),
  CONSTRAINT fk_embarque_puerto_destino FOREIGN KEY (id_puerto_destino)
    REFERENCES puerto (id_puerto)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- FIN: el control de habilitacion, despacho y coherencia entre tablas
-- es responsabilidad de los objetos de negocio (scripts 04 y 05).
-- No desactivar FOREIGN_KEY_CHECKS durante el uso normal.
-- ---------------------------------------------------------------------
