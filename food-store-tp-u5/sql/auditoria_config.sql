-- =====================================================================
-- auditoria_config.sql — Parte B, punto 1
-- Activa los parámetros de auditoría del servidor de DESARROLLO.
-- ALTER SYSTEM escribe en postgresql.auto.conf (no se edita a mano).
-- logging_collector requiere reiniciar el servidor; el resto, recargar.
--   psql -U postgres -f sql/auditoria_config.sql && pg_ctl restart -D $PGDATA
-- =====================================================================

-- Quién se conecta y cuándo se desconecta (con duración de la sesión)
ALTER SYSTEM SET log_connections    = on;
ALTER SYSTEM SET log_disconnections = on;

-- Qué se modifica: 'mod' registra DDL + INSERT/UPDATE/DELETE/TRUNCATE/COPY FROM
ALTER SYSTEM SET log_statement = 'mod';

-- Contexto de cada línea: cuándo, proceso, quién, en qué base, desde dónde y con qué app
ALTER SYSTEM SET log_line_prefix = '%m [%p] user=%u db=%d host=%h app=%a ';
ALTER SYSTEM SET log_timezone    = 'America/Argentina/Buenos_Aires';

-- Archivo de log propio, con permisos sólo para el usuario del sistema postgres
ALTER SYSTEM SET logging_collector = on;
ALTER SYSTEM SET log_directory     = 'log';
ALTER SYSTEM SET log_filename      = 'postgresql-%Y-%m-%d.log';
ALTER SYSTEM SET log_file_mode     = '0600';
ALTER SYSTEM SET log_rotation_age  = '1d';

-- Las órdenes de cambio de roles y permisos (GRANT/REVOKE/ALTER ROLE) son DDL
-- y ya quedan con 'mod'. Las sentencias que fallan por permisos quedan como ERROR.
ALTER SYSTEM SET log_min_error_statement = 'error';

SELECT pg_reload_conf();
