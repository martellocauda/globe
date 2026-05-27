-- =============================================================================
-- Script de migración: Soporte de Perfiles GiAM
-- Agrega la entidad Perfil y las relaciones necesarias para soportar
-- perfiles (tipo P) y excepciones (tipo E) de los feeds GiAM.
-- =============================================================================

-- Tabla principal de perfiles
CREATE TABLE IF NOT EXISTS Perfil (
    id BIGINT NOT NULL AUTO_INCREMENT,
    idPerfil VARCHAR(255),
    nivelRiesgo INTEGER,
    aplicacion_id BIGINT,
    PRIMARY KEY (id),
    CONSTRAINT FK_Perfil_Aplicacion FOREIGN KEY (aplicacion_id) REFERENCES Aplicacion(id)
) ENGINE=InnoDB;

-- Tabla de auditoría de perfiles (Hibernate Envers)
CREATE TABLE IF NOT EXISTS Perfil_AUD (
    id BIGINT NOT NULL,
    REV BIGINT NOT NULL,
    REVTYPE SMALLINT,
    idPerfil VARCHAR(255),
    nivelRiesgo INTEGER,
    aplicacion_id BIGINT,
    PRIMARY KEY (id, REV),
    CONSTRAINT FK_Perfil_AUD_REV FOREIGN KEY (REV) REFERENCES AuditRevEntity(id)
) ENGINE=InnoDB;

-- Join table: Perfil <-> Permiso (composición del perfil desde SMOD)
CREATE TABLE IF NOT EXISTS Perfil_Permiso (
    Perfil_id BIGINT NOT NULL,
    permisos_id BIGINT NOT NULL,
    CONSTRAINT FK_PerfilPermiso_Perfil FOREIGN KEY (Perfil_id) REFERENCES Perfil(id),
    CONSTRAINT FK_PerfilPermiso_Permiso FOREIGN KEY (permisos_id) REFERENCES Permiso(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Perfil_Permiso_AUD (
    REV BIGINT NOT NULL,
    Perfil_id BIGINT NOT NULL,
    permisos_id BIGINT NOT NULL,
    REVTYPE SMALLINT,
    PRIMARY KEY (REV, Perfil_id, permisos_id),
    CONSTRAINT FK_PerfilPermiso_AUD_REV FOREIGN KEY (REV) REFERENCES AuditRevEntity(id)
) ENGINE=InnoDB;

-- Join table: Cuenta <-> Perfil (perfiles asignados a una cuenta, tipo P del ENTL)
CREATE TABLE IF NOT EXISTS Cuenta_Perfil (
    Cuenta_id BIGINT NOT NULL,
    perfiles_id BIGINT NOT NULL,
    CONSTRAINT FK_CuentaPerfil_Cuenta FOREIGN KEY (Cuenta_id) REFERENCES Cuenta(id),
    CONSTRAINT FK_CuentaPerfil_Perfil FOREIGN KEY (perfiles_id) REFERENCES Perfil(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Cuenta_Perfil_AUD (
    REV BIGINT NOT NULL,
    Cuenta_id BIGINT NOT NULL,
    perfiles_id BIGINT NOT NULL,
    REVTYPE SMALLINT,
    PRIMARY KEY (REV, Cuenta_id, perfiles_id),
    CONSTRAINT FK_CuentaPerfil_AUD_REV FOREIGN KEY (REV) REFERENCES AuditRevEntity(id)
) ENGINE=InnoDB;

-- Join table: Aplicacion <-> Perfil (catálogo de perfiles del sistema)
CREATE TABLE IF NOT EXISTS Aplicacion_Perfil (
    Aplicacion_id BIGINT NOT NULL,
    perfiles_id BIGINT NOT NULL,
    CONSTRAINT UK_AplicacionPerfil_perfiles UNIQUE (perfiles_id),
    CONSTRAINT FK_AplicacionPerfil_Aplicacion FOREIGN KEY (Aplicacion_id) REFERENCES Aplicacion(id),
    CONSTRAINT FK_AplicacionPerfil_Perfil FOREIGN KEY (perfiles_id) REFERENCES Perfil(id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS Aplicacion_Perfil_AUD (
    REV BIGINT NOT NULL,
    Aplicacion_id BIGINT NOT NULL,
    perfiles_id BIGINT NOT NULL,
    REVTYPE SMALLINT,
    PRIMARY KEY (REV, Aplicacion_id, perfiles_id),
    CONSTRAINT FK_AplicacionPerfil_AUD_REV FOREIGN KEY (REV) REFERENCES AuditRevEntity(id)
) ENGINE=InnoDB;

-- Nuevas columnas en Perfil: campos del RISK file (GAMD v7.6)
ALTER TABLE Perfil ADD COLUMN descripcion VARCHAR(4000);

ALTER TABLE Perfil_AUD ADD COLUMN descripcion VARCHAR(4000);

-- Nuevas columnas en Permiso: campos del RISK file (GAMD v7.6)
ALTER TABLE Permiso ADD COLUMN nivelRiesgo INTEGER;

ALTER TABLE Permiso_AUD ADD COLUMN nivelRiesgo INTEGER;

-- Nuevas columnas en LineaRevision para soportar revisión de perfiles
ALTER TABLE LineaRevision ADD COLUMN idPerfil BIGINT;
ALTER TABLE LineaRevision ADD COLUMN tipoEntitlement INTEGER;

ALTER TABLE LineaRevision_AUD ADD COLUMN idPerfil BIGINT;
ALTER TABLE LineaRevision_AUD ADD COLUMN tipoEntitlement INTEGER;

-- Nueva columna en Aplicacion: indica si la app se carga por Feed (GIAM).
-- Es excluyente con cargaDesdeCSV: una app puede tener uno, el otro o ninguno
-- (la exclusividad la valida el bean en backend).
-- Las apps que ya fueron creadas por feed se identifican por tener cargaDesdeCSV=1
-- y no haber sido configuradas manualmente, por lo que se migran automáticamente.
ALTER TABLE Aplicacion ADD COLUMN cargaPorFeed TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE Aplicacion_AUD ADD COLUMN cargaPorFeed TINYINT(1);

-- Migración: las aplicaciones creadas históricamente desde feed se marcaron
-- incorrectamente con cargaDesdeCSV=1. Detectamos las apps que tienen perfiles
-- asociados (las cargadas por feed son las únicas que tienen perfiles GIAM)
-- y las migramos al nuevo flag.
UPDATE Aplicacion a
   SET a.cargaPorFeed = 1,
       a.cargaDesdeCSV = 0
 WHERE EXISTS (
       SELECT 1 FROM Aplicacion_Perfil ap WHERE ap.Aplicacion_id = a.id
 );

-- =============================================================================
-- Constraints de unicidad en join tables para uso con Set (Hibernate)
-- Al cambiar las colecciones de List a Set, Hibernate requiere que las
-- join tables tengan PKs compuestas para poder hacer INSERT/DELETE individuales
-- en lugar de DELETE ALL + RE-INSERT ALL (semántica "bag").
-- Se eliminan duplicados existentes antes de agregar las constraints.
-- =============================================================================

-- 1. Aplicacion_Permiso: ya tiene UNIQUE(permisos_id), agregar PK compuesta
DELETE t1 FROM Aplicacion_Permiso t1
  INNER JOIN Aplicacion_Permiso t2
  WHERE t1.Aplicacion_id = t2.Aplicacion_id
    AND t1.permisos_id = t2.permisos_id
    AND t1.Aplicacion_id > t2.Aplicacion_id;
ALTER TABLE Aplicacion_Permiso ADD PRIMARY KEY (Aplicacion_id, permisos_id);

-- 2. Aplicacion_Perfil: ya tiene UNIQUE(perfiles_id), agregar PK compuesta
DELETE t1 FROM Aplicacion_Perfil t1
  INNER JOIN Aplicacion_Perfil t2
  WHERE t1.Aplicacion_id = t2.Aplicacion_id
    AND t1.perfiles_id = t2.perfiles_id
    AND t1.Aplicacion_id > t2.Aplicacion_id;
ALTER TABLE Aplicacion_Perfil ADD PRIMARY KEY (Aplicacion_id, perfiles_id);

-- 3. Perfil_Permiso: sin constraints previas
DELETE t1 FROM Perfil_Permiso t1
  INNER JOIN Perfil_Permiso t2
  WHERE t1.Perfil_id = t2.Perfil_id
    AND t1.permisos_id = t2.permisos_id
    AND t1.Perfil_id > t2.Perfil_id;
ALTER TABLE Perfil_Permiso ADD PRIMARY KEY (Perfil_id, permisos_id);

-- 4. Cuenta_Permiso: sin constraints previas
DELETE t1 FROM Cuenta_Permiso t1
  INNER JOIN Cuenta_Permiso t2
  WHERE t1.Cuenta_id = t2.Cuenta_id
    AND t1.permisos_id = t2.permisos_id
    AND t1.Cuenta_id > t2.Cuenta_id;
ALTER TABLE Cuenta_Permiso ADD PRIMARY KEY (Cuenta_id, permisos_id);

-- 5. Cuenta_Perfil: sin constraints previas
DELETE t1 FROM Cuenta_Perfil t1
  INNER JOIN Cuenta_Perfil t2
  WHERE t1.Cuenta_id = t2.Cuenta_id
    AND t1.perfiles_id = t2.perfiles_id
    AND t1.Cuenta_id > t2.Cuenta_id;
ALTER TABLE Cuenta_Perfil ADD PRIMARY KEY (Cuenta_id, perfiles_id);

-- 6. Usuario_Cuenta: ya tiene UNIQUE(cuentas_id), agregar PK compuesta
DELETE t1 FROM Usuario_Cuenta t1
  INNER JOIN Usuario_Cuenta t2
  WHERE t1.Usuario_id = t2.Usuario_id
    AND t1.cuentas_id = t2.cuentas_id
    AND t1.Usuario_id > t2.Usuario_id;
ALTER TABLE Usuario_Cuenta ADD PRIMARY KEY (Usuario_id, cuentas_id);

-- =============================================================================
-- Indices de performance
-- =============================================================================
-- Las tablas _AUD creadas originalmente para DB2 usan id autoincremental como PK
-- en lugar de la PK compuesta (id, REV) que Hibernate Envers espera.
-- Las queries de Envers (find, forEntitiesAtRevision) filtran por
--   WHERE id = ? AND REV <= ? ORDER BY REV DESC
-- Sin indice (id, REV) estas queries hacen full table scan.
-- NOTA: Si la tabla ya tiene PK compuesta (id, REV), el indice es redundante
-- y MySQL lo ignora o crea un secondary index inocuo.
-- =============================================================================

-- -----------------------------------------------
-- PRIORIDAD 1: Tablas _AUD - indice (id, REV)
-- Impacto critico: cada getAR().find() ejecuta
-- WHERE id = ? AND REV <= ? ORDER BY REV DESC
-- -----------------------------------------------

CREATE INDEX idx_permiso_aud_id_rev ON Permiso_AUD(id, REV);
CREATE INDEX idx_cuenta_aud_id_rev ON Cuenta_AUD(id, REV);
CREATE INDEX idx_aplicacion_aud_id_rev ON Aplicacion_AUD(id, REV);
CREATE INDEX idx_usuario_aud_id_rev ON Usuario_AUD(id, REV);
CREATE INDEX idx_adjunto_aud_id_rev ON Adjunto_AUD(id, REV);
CREATE INDEX idx_revision_aud_id_rev ON Revision_AUD(id, REV);
CREATE INDEX idx_revisor_aud_id_rev ON Revisor_AUD(id, REV);
CREATE INDEX idx_reapertura_aud_id_rev ON Reapertura_AUD(id, REV);
CREATE INDEX idx_linearevision_aud_id_rev ON LineaRevision_AUD(id, REV);

-- Perfil_AUD y CuentaRevision_AUD ya tienen PK compuesta (id, REV), no necesitan indice.

-- -----------------------------------------------
-- PRIORIDAD 1: Tablas _AUD de join tables
-- Envers consulta por entidad padre: WHERE parent_id = ? AND REV <= ?
-- Las PKs son (REV, parent_id, child_id), no cubren busqueda por parent_id.
-- -----------------------------------------------

-- Revision_Revisor_AUD: buscar revisores de una revision en una version
CREATE INDEX idx_revision_revisor_aud_ids ON Revision_Revisor_AUD(Revision_id, revisores_id, REV);

-- Revisor_CuentaRevision_AUD: buscar cuentas de un revisor en una version
CREATE INDEX idx_revisor_cuentarevision_aud_ids ON Revisor_CuentaRevision_AUD(Revisor_id, cuentasRevision_id, REV);

-- CuentaRevision_LineaRevision_AUD: buscar lineas de una cuenta en una version
CREATE INDEX idx_cuentarev_linearev_aud_ids ON CuentaRevision_LineaRevision_AUD(CuentaRevision_id, lineasRevision_id, REV);

-- Usuario_Cuenta_AUD: buscar cuentas de un usuario en una version
CREATE INDEX idx_usuario_cuenta_aud_ids ON Usuario_Cuenta_AUD(Usuario_id, cuentas_id, REV);

-- Cuenta_Permiso_AUD: buscar permisos de una cuenta en una version
CREATE INDEX idx_cuenta_permiso_aud_ids ON Cuenta_Permiso_AUD(Cuenta_id, permisos_id, REV);

-- Cuenta_Perfil_AUD: buscar perfiles de una cuenta en una version
CREATE INDEX idx_cuenta_perfil_aud_ids ON Cuenta_Perfil_AUD(Cuenta_id, perfiles_id, REV);

-- Perfil_Permiso_AUD: buscar permisos de un perfil en una version
CREATE INDEX idx_perfil_permiso_aud_ids ON Perfil_Permiso_AUD(Perfil_id, permisos_id, REV);

-- Aplicacion_Permiso_AUD: buscar permisos de una aplicacion en una version
CREATE INDEX idx_aplicacion_permiso_aud_ids ON Aplicacion_Permiso_AUD(Aplicacion_id, permisos_id, REV);

-- Aplicacion_Perfil_AUD: buscar perfiles de una aplicacion en una version
CREATE INDEX idx_aplicacion_perfil_aud_ids ON Aplicacion_Perfil_AUD(Aplicacion_id, perfiles_id, REV);

-- AuditRevEntity: queries de auditoria filtran por rango de timestamp
CREATE INDEX idx_auditreventity_timestamp ON AuditRevEntity(timestamp);

-- -----------------------------------------------
-- PRIORIDAD 2: Tablas principales - filtros frecuentes
-- Las queries de resumen y revision hacen JOINs
-- Revision > Revisor > CuentaRevision > LineaRevision
-- y filtran por estos campos constantemente.
-- -----------------------------------------------

-- CuentaRevision: columnas de filtro en queryCuentasRevision y queryLineasRevision
CREATE INDEX idx_cuentarevision_idUsuario ON CuentaRevision(idUsuario);
CREATE INDEX idx_cuentarevision_idAplicacion ON CuentaRevision(idAplicacion);
CREATE INDEX idx_cuentarevision_idCuenta ON CuentaRevision(idCuenta);

-- Revisor: filtro por manager en getRevisionesManager, getReasignables, etc.
CREATE INDEX idx_revisor_idManager ON Revisor(idManager);

-- LineaRevision: lookup de permisos y perfiles en getRevisionUsuario
CREATE INDEX idx_linearevision_idPermiso ON LineaRevision(idPermiso);
CREATE INDEX idx_linearevision_idPerfil ON LineaRevision(idPerfil);

-- -----------------------------------------------
-- PRIORIDAD 3: Otras queries frecuentes
-- -----------------------------------------------

-- Mail: getPendientesFecha filtra por estado + envioProgramado
CREATE INDEX idx_mail_estado_envio ON Mail(estado, envioProgramado);

-- Session: vencidasUsuario filtra por idUsuario + fecha
CREATE INDEX idx_session_usuario_fecha ON Session(idUsuario, fecha);

-- Soporte para agregar managers post-inicio de revisión
ALTER TABLE Revisor ADD COLUMN agregadoPostInicio BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE Revisor ADD COLUMN fechaAgregado DATETIME NULL;
ALTER TABLE Revisor ADD COLUMN revisionEnversManager BIGINT NULL;

ALTER TABLE Revisor_AUD ADD COLUMN agregadoPostInicio BOOLEAN;
ALTER TABLE Revisor_AUD ADD COLUMN fechaAgregado DATETIME NULL;
ALTER TABLE Revisor_AUD ADD COLUMN revisionEnversManager BIGINT NULL;
