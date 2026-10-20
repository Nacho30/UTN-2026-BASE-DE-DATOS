-- =====================================================================
-- maintenance.sql — TP Unidad 6, Parte 3 (revisión semanal)
--   psql -X -h localhost -U postgres -w -d foodstore -f sql/maintenance.sql
--
-- 1. Revisa que el autovacuum esté activo y con qué parámetros.
-- 2. Calcula, tabla por tabla, si el autovacuum ya debería haber actuado
--    (umbral de VACUUM y de ANALYZE) y si las estadísticas existen.
-- 3. Ejecuta SÓLO la acción que la observación justifica:
--      * VACUUM (ANALYZE): tuplas muertas por encima del umbral y sin
--        autovacuum en la última hora (el autovacuum no está alcanzando).
--      * ANALYZE: la tabla tiene filas pero nunca tuvo estadísticas, o los
--        cambios desde el último ANALYZE superan su umbral.
--      * nada: el autovacuum está al día.
--    Ambas acciones son seguras en horario de uso: VACUUM común y ANALYZE
--    toman SHARE UPDATE EXCLUSIVE, que no bloquea lecturas ni escrituras.
--    VACUUM FULL NO se usa (ACCESS EXCLUSIVE + reescritura de la tabla).
-- 4. Muestra el estado posterior para comprobar el efecto.
-- =====================================================================
\pset null '—'
\echo '===== Mantenimiento Food Store ====='
SELECT current_database() AS base, now() AS momento;

-- ---------------------------------------------------------------------
-- 1. Configuración del autovacuum
-- ---------------------------------------------------------------------
\echo '===== 1. Configuración de autovacuum ====='
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('autovacuum', 'track_counts', 'autovacuum_naptime', 'autovacuum_max_workers',
               'autovacuum_vacuum_threshold', 'autovacuum_vacuum_scale_factor',
               'autovacuum_analyze_threshold', 'autovacuum_analyze_scale_factor',
               'autovacuum_vacuum_insert_threshold', 'autovacuum_vacuum_insert_scale_factor')
ORDER BY name;

\echo '----- Tablas con parámetros de autovacuum propios (reloptions) -----'
SELECT c.relname AS tabla, c.reloptions
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.reloptions IS NOT NULL;

-- ---------------------------------------------------------------------
-- 2. Observación y decisión por tabla
-- ---------------------------------------------------------------------
CREATE TEMP VIEW diagnostico AS
WITH cfg AS (
    SELECT current_setting('autovacuum_vacuum_threshold')::float     AS v_umbral,
           current_setting('autovacuum_vacuum_scale_factor')::float  AS v_factor,
           current_setting('autovacuum_analyze_threshold')::float    AS a_umbral,
           current_setting('autovacuum_analyze_scale_factor')::float AS a_factor
), base AS (
    SELECT t.relid, t.relname, t.n_live_tup, t.n_dead_tup, t.n_mod_since_analyze,
           greatest(t.last_vacuum, t.last_autovacuum)   AS ultimo_vacuum,
           greatest(t.last_analyze, t.last_autoanalyze) AS ultimo_analyze,
           round(cfg.v_umbral + cfg.v_factor * greatest(c.reltuples, 0)) AS umbral_vacuum,
           round(cfg.a_umbral + cfg.a_factor * greatest(c.reltuples, 0)) AS umbral_analyze
    FROM pg_stat_user_tables t JOIN pg_class c ON c.oid = t.relid, cfg
)
SELECT relname AS tabla, n_live_tup AS vivas, n_dead_tup AS muertas, umbral_vacuum,
       n_mod_since_analyze AS cambios_sin_analyze, umbral_analyze,
       ultimo_vacuum, ultimo_analyze,
       CASE
         WHEN n_dead_tup > umbral_vacuum
              AND (ultimo_vacuum IS NULL OR ultimo_vacuum < now() - interval '1 hour')
           THEN 'VACUUM (ANALYZE)'
         WHEN n_live_tup > 0 AND ultimo_analyze IS NULL
           THEN 'ANALYZE'
         WHEN n_mod_since_analyze > umbral_analyze
              AND (ultimo_analyze < now() - interval '1 hour')
           THEN 'ANALYZE'
         ELSE 'nada'
       END AS accion,
       CASE
         WHEN n_dead_tup > umbral_vacuum
              AND (ultimo_vacuum IS NULL OR ultimo_vacuum < now() - interval '1 hour')
           THEN 'muertas sobre el umbral y el autovacuum no actuó en la última hora'
         WHEN n_live_tup > 0 AND ultimo_analyze IS NULL
           THEN 'tiene filas y nunca tuvo estadísticas (no llega al umbral del autoanalyze)'
         WHEN n_mod_since_analyze > umbral_analyze
              AND (ultimo_analyze < now() - interval '1 hour')
           THEN 'cambios desde el último ANALYZE sobre el umbral'
         ELSE 'autovacuum al día'
       END AS motivo
FROM base;

\echo '===== 2. Diagnóstico y decisión por tabla ====='
SELECT * FROM diagnostico ORDER BY muertas DESC;

-- ---------------------------------------------------------------------
-- 3. Acción justificada (una sentencia por tabla que la necesita)
-- ---------------------------------------------------------------------
\echo '===== 3. Acciones ejecutadas ====='
SELECT format('%s %I', accion, tabla) AS sentencia
FROM diagnostico WHERE accion <> 'nada' ORDER BY tabla;
\timing on
SELECT format('%s %I', accion, tabla)
FROM diagnostico WHERE accion <> 'nada' ORDER BY tabla
\gexec
\timing off

-- ---------------------------------------------------------------------
-- 4. Estado posterior
-- ---------------------------------------------------------------------
\echo '===== 4. Estado posterior ====='
SELECT relname AS tabla, n_live_tup AS vivas, n_dead_tup AS muertas,
       n_mod_since_analyze AS cambios_sin_analyze, last_vacuum, last_analyze,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables ORDER BY relname;
