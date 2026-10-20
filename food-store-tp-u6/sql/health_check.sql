-- =====================================================================
-- health_check.sql — TP Unidad 6, Parte 3 (monitoreo diario)
-- Sólo lectura: puede correrse en cualquier momento sobre foodstore.
--   psql -X -h localhost -U postgres -w -d foodstore -f sql/health_check.sql
-- Cada control termina con una columna "estado" (OK / ALERTA) y el
-- resumen final junta los siete. Probado en PostgreSQL 16.
-- =====================================================================
\pset null '—'
\echo '===== Health check Food Store ====='
SELECT current_database() AS base, version() AS motor, now() AS momento;

-- ---------------------------------------------------------------------
-- 1. Tamaño de la base y de las tablas más grandes
-- ---------------------------------------------------------------------
\echo '===== 1. Tamaño ====='
SELECT pg_size_pretty(pg_database_size(current_database())) AS tamano_base;

SELECT relname AS tabla,
       pg_size_pretty(pg_total_relation_size(relid)) AS total,
       pg_size_pretty(pg_relation_size(relid))       AS datos,
       pg_size_pretty(pg_indexes_size(relid))        AS indices
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;

-- ---------------------------------------------------------------------
-- 2. Actividad de conexiones
-- ---------------------------------------------------------------------
\echo '===== 2. Conexiones ====='
SELECT d.numbackends, d.xact_commit, d.xact_rollback,
       round(100.0 * d.xact_rollback / nullif(d.xact_commit + d.xact_rollback, 0), 2) AS pct_rollback,
       s.setting::int AS max_connections,
       round(100.0 * (SELECT count(*) FROM pg_stat_activity) / s.setting::int, 1) AS pct_uso_servidor,
       CASE WHEN (SELECT count(*) FROM pg_stat_activity) > 0.8 * s.setting::int THEN 'ALERTA' ELSE 'OK' END AS estado
FROM pg_stat_database d, pg_settings s
WHERE d.datname = current_database() AND s.name = 'max_connections';

SELECT usename AS rol, application_name AS app, coalesce(state, '(proceso de fondo)') AS estado_sesion, count(*) AS sesiones
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY 1, 2, 3
ORDER BY sesiones DESC;

-- ---------------------------------------------------------------------
-- 3. Estado de las tablas: tuplas muertas, autovacuum y estadísticas
--    ALERTA si las tuplas muertas superan el umbral con el que el
--    autovacuum debería haber actuado y todavía no lo hizo.
-- ---------------------------------------------------------------------
\echo '===== 3. Estado de tablas ====='
WITH cfg AS (
    SELECT current_setting('autovacuum_vacuum_threshold')::float    AS umbral,
           current_setting('autovacuum_vacuum_scale_factor')::float AS factor
)
SELECT t.relname AS tabla, t.n_live_tup AS vivas, t.n_dead_tup AS muertas,
       round(100.0 * t.n_dead_tup / nullif(t.n_live_tup + t.n_dead_tup, 0), 1) AS pct_muertas,
       round(cfg.umbral + cfg.factor * c.reltuples) AS umbral_autovacuum,
       t.n_mod_since_analyze AS cambios_sin_analyze,
       t.last_autovacuum, t.last_vacuum, t.last_autoanalyze, t.last_analyze,
       CASE WHEN t.n_dead_tup > cfg.umbral + cfg.factor * greatest(c.reltuples, 0) THEN 'ALERTA' ELSE 'OK' END AS estado
FROM pg_stat_user_tables t
JOIN pg_class c ON c.oid = t.relid, cfg
ORDER BY t.n_dead_tup DESC;

-- ---------------------------------------------------------------------
-- 4. Consultas activas (excluye esta misma sesión)
--    ALERTA si alguna lleva más de 5 minutos o hay transacciones abiertas
--    sin actividad ("idle in transaction"), que impiden limpiar tuplas.
-- ---------------------------------------------------------------------
\echo '===== 4. Consultas activas ====='
SELECT pid, usename AS rol, state, now() - query_start AS duracion,
       now() - xact_start AS edad_transaccion, wait_event_type, left(query, 80) AS consulta,
       CASE WHEN now() - query_start > interval '5 minutes'
              OR state LIKE 'idle in transaction%' THEN 'ALERTA' ELSE 'OK' END AS estado
FROM pg_stat_activity
WHERE datname = current_database() AND state <> 'idle' AND pid <> pg_backend_pid()
ORDER BY query_start;

-- ---------------------------------------------------------------------
-- 5. Bloqueos: sesiones esperando a otra
-- ---------------------------------------------------------------------
\echo '===== 5. Bloqueos ====='
SELECT a.pid AS bloqueada, pg_blocking_pids(a.pid) AS bloqueada_por,
       now() - a.query_start AS esperando, left(a.query, 60) AS consulta
FROM pg_stat_activity a
WHERE a.datname = current_database() AND cardinality(pg_blocking_pids(a.pid)) > 0;

-- ---------------------------------------------------------------------
-- 6. Edad de transacciones (riesgo de wraparound)
-- ---------------------------------------------------------------------
\echo '===== 6. Edad de transacciones ====='
SELECT datname, age(datfrozenxid) AS edad_xid,
       current_setting('autovacuum_freeze_max_age')::bigint AS freeze_max_age,
       round(100.0 * age(datfrozenxid) / current_setting('autovacuum_freeze_max_age')::bigint, 1) AS pct,
       CASE WHEN age(datfrozenxid) > 0.8 * current_setting('autovacuum_freeze_max_age')::bigint
            THEN 'ALERTA' ELSE 'OK' END AS estado
FROM pg_database WHERE datname = current_database();

-- ---------------------------------------------------------------------
-- 7. Aciertos de caché
-- ---------------------------------------------------------------------
\echo '===== 7. Aciertos de caché ====='
SELECT blks_hit, blks_read,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS pct_cache,
       CASE WHEN blks_hit + blks_read > 10000
             AND 100.0 * blks_hit / (blks_hit + blks_read) < 90 THEN 'ALERTA' ELSE 'OK' END AS estado
FROM pg_stat_database WHERE datname = current_database();

-- ---------------------------------------------------------------------
-- Resumen
-- ---------------------------------------------------------------------
\echo '===== Resumen ====='
WITH cfg AS (
    SELECT current_setting('autovacuum_vacuum_threshold')::float    AS umbral,
           current_setting('autovacuum_vacuum_scale_factor')::float AS factor
)
SELECT control, CASE WHEN alertas = 0 THEN 'OK' ELSE 'ALERTA (' || alertas || ')' END AS estado
FROM (VALUES
  ('2. conexiones', (SELECT count(*) FILTER (WHERE (SELECT count(*) FROM pg_stat_activity) > 0.8 * setting::int)
                     FROM pg_settings WHERE name = 'max_connections')),
  ('3. tablas sobre el umbral de autovacuum',
       (SELECT count(*) FROM pg_stat_user_tables t JOIN pg_class c ON c.oid = t.relid, cfg
        WHERE t.n_dead_tup > cfg.umbral + cfg.factor * greatest(c.reltuples, 0))),
  ('4. consultas largas o idle in transaction',
       (SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND pid <> pg_backend_pid()
          AND (now() - query_start > interval '5 minutes' AND state <> 'idle'
               OR state LIKE 'idle in transaction%'))),
  ('5. sesiones bloqueadas',
       (SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND cardinality(pg_blocking_pids(pid)) > 0)),
  ('6. wraparound',
       (SELECT count(*) FROM pg_database WHERE datname = current_database()
          AND age(datfrozenxid) > 0.8 * current_setting('autovacuum_freeze_max_age')::bigint)),
  ('7. caché',
       (SELECT count(*) FROM pg_stat_database WHERE datname = current_database()
          AND blks_hit + blks_read > 10000 AND 100.0 * blks_hit / (blks_hit + blks_read) < 90))
) AS r(control, alertas);
