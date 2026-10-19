-- =====================================================================
-- usuario_anon.sql — Parte D, punto 1
-- Copia anonimizada de usuario para reportes y para trabajar con IA.
--
-- Técnicas por columna:
--   id, nombre, email → SEUDONIMIZACIÓN determinista: U-<8 hex de md5(sal||id)>
--                       (mismo criterio que scripts/anonimizar_log.py)
--   telefono, direccion → SUPRESIÓN (no se copian)
--   fecha_alta        → GENERALIZACIÓN al primer día del mes
--   rol, bloqueado, eliminado → se conservan (no identifican por sí solos)
--
-- La sal (ANON_SALT) vive en .env, fuera del repo: sin ella no se puede
-- recalcular el seudónimo a partir de un id ni de un email conocido.
--   psql -d foodstore_u5 -v ON_ERROR_STOP=1 -f sql/usuario_anon.sql
-- =====================================================================
\getenv anon_salt ANON_SALT

-- La sal viaja en el texto de las sentencias: con log_statement = 'mod'
-- quedaría escrita en el log. Se apaga el registro SÓLO en esta sesión
-- (parámetro reservado al superusuario).
SET log_statement = 'none';

BEGIN;
-- Se crea como el dueño: hereda los default privileges de la Parte A
SET LOCAL ROLE foodstore_owner;

DROP TABLE IF EXISTS usuario_anon;

CREATE TABLE usuario_anon (
    id_anon        CHAR(10)    PRIMARY KEY,
    nombre_anon    VARCHAR(30) NOT NULL,
    email_anon     VARCHAR(60) NOT NULL UNIQUE,
    rol            VARCHAR(20) NOT NULL,
    mes_alta       DATE        NOT NULL CHECK (mes_alta = date_trunc('month', mes_alta)::date),
    bloqueado      BOOLEAN     NOT NULL,
    eliminado      BOOLEAN     NOT NULL,
    generado_el    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE usuario_anon IS
  'Datos sintéticos deterministas derivados de usuario. Sin teléfono ni dirección; '
  'fecha de alta generalizada al mes. Regenerar con sql/usuario_anon.sql.';

INSERT INTO usuario_anon (id_anon, nombre_anon, email_anon, rol, mes_alta, bloqueado, eliminado)
SELECT s.seud,
       'Usuario ' || s.seud,
       lower(s.seud) || '@anon.foodstore.test',
       u.rol,
       date_trunc('month', u.fecha_alta)::date,
       u.bloqueado,
       u.eliminado
FROM usuario u
CROSS JOIN LATERAL (SELECT 'U-' || left(md5(:'anon_salt' || u.id::text), 8) AS seud) s;

RESET ROLE;

-- Reportes lee la versión anónima y nunca la real (Req. 4 de la spec)
GRANT SELECT ON usuario_anon TO rol_reportes;
COMMIT;

RESET log_statement;

-- ---------------------------------------------------------------------
-- Controles de la anonimización
-- ---------------------------------------------------------------------
\echo '===== Muestra de usuario_anon ====='
SELECT id_anon, nombre_anon, email_anon, rol, mes_alta FROM usuario_anon ORDER BY id_anon LIMIT 5;

\echo '===== Cardinalidad y seudónimos únicos (sin colisiones) ====='
SELECT (SELECT count(*) FROM usuario)                  AS filas_usuario,
       (SELECT count(*) FROM usuario_anon)             AS filas_anon,
       (SELECT count(DISTINCT id_anon) FROM usuario_anon) AS seudonimos_distintos;

\echo '===== Ningún dato identificable de usuario aparece en usuario_anon (esperado: 0) ====='
SELECT count(*) AS coincidencias
FROM usuario u
JOIN usuario_anon a
  ON a.email_anon = u.email
  OR a.nombre_anon = u.nombre
  OR a.id_anon = u.id::text
  OR a.nombre_anon LIKE '%' || split_part(u.nombre, ' ', 2) || '%';

\echo '===== Determinismo: regenerar da los mismos seudónimos (esperado: 1000 emparejados, 0 distintos) ====='
SET log_statement = 'none';
SELECT count(*) AS emparejados,          -- esperado: 1000
       count(*) FILTER (WHERE a.rol <> u.rol
                           OR a.mes_alta <> date_trunc('month', u.fecha_alta)::date) AS distintos
FROM usuario u
JOIN usuario_anon a ON a.id_anon = 'U-' || left(md5(:'anon_salt' || u.id::text), 8);
RESET log_statement;

\echo '===== Permisos: reportes lee usuario_anon y no usuario ====='
SELECT has_table_privilege('reportes_bi', 'usuario_anon', 'SELECT') AS reportes_lee_anon,
       has_table_privilege('reportes_bi', 'usuario', 'SELECT')      AS reportes_lee_usuario,
       has_table_privilege('admin_datos', 'usuario_anon', 'DELETE') AS admin_heredo_dml;
