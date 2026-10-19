-- =====================================================================
-- roles.sql — Food Store, Unidad 5, Parte A
-- Esquema de roles y permisos de mínimo privilegio.
-- Especificación: docs/kiro_roles_spec/ (requirements.md + design.md)
--
-- Ejecutar como superusuario, con las contraseñas en el entorno:
--   export PW_APP_WEB=... PW_ADMIN_DATOS=... PW_SOPORTE=... PW_REPORTES=... PW_AUDITOR=...
--   psql -d foodstore_u5 -v ON_ERROR_STOP=1 -f sql/roles.sql
-- Es idempotente: se puede volver a correr.
-- =====================================================================

\getenv pw_app_web     PW_APP_WEB
\getenv pw_admin_datos PW_ADMIN_DATOS
\getenv pw_soporte     PW_SOPORTE
\getenv pw_reportes    PW_REPORTES
\getenv pw_auditor     PW_AUDITOR

-- ---------------------------------------------------------------------
-- 0. Creación idempotente de roles (CREATE ROLE no tiene IF NOT EXISTS)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['foodstore_owner','rol_app_lectura','rol_app_escritura',
                             'rol_soporte','rol_reportes','rol_auditor'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;

    FOREACH r IN ARRAY ARRAY['app_web','admin_datos','soporte_mesa','reportes_bi','auditor_seg'] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I LOGIN', r);
        END IF;
    END LOOP;
END;
$$;

-- Atributos explícitos: ningún rol puede crear roles, bases ni saltear RLS
ALTER ROLE foodstore_owner   NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE rol_app_lectura   NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER ROLE rol_app_escritura NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER ROLE rol_soporte       NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER ROLE rol_reportes      NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER ROLE rol_auditor       NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;

ALTER ROLE app_web      LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 50 PASSWORD :'pw_app_web';
ALTER ROLE admin_datos  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 3  PASSWORD :'pw_admin_datos';
ALTER ROLE soporte_mesa LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 5  PASSWORD :'pw_soporte';
ALTER ROLE reportes_bi  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 5  PASSWORD :'pw_reportes';
ALTER ROLE auditor_seg  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 2  PASSWORD :'pw_auditor';

-- ---------------------------------------------------------------------
-- 1. Propiedad: todo pasa a foodstore_owner (NOLOGIN, no superusuario)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    o RECORD;
BEGIN
    FOR o IN SELECT c.relname, c.relkind
             FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = 'public' AND c.relkind IN ('r','v','m')
    LOOP
        EXECUTE format('ALTER %s public.%I OWNER TO foodstore_owner',
                       CASE o.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' ELSE 'TABLE' END,
                       o.relname);
    END LOOP;

    -- funciones propias (no las de extensiones como pgcrypto)
    FOR o IN SELECT p.oid::regprocedure AS firma
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND NOT EXISTS (SELECT 1 FROM pg_depend d
                               WHERE d.objid = p.oid AND d.deptype = 'e')
    LOOP
        EXECUTE format('ALTER FUNCTION %s OWNER TO foodstore_owner', o.firma);
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. Cerrar todo lo que PUBLIC recibe por defecto
-- ---------------------------------------------------------------------
REVOKE ALL     ON DATABASE foodstore_u5            FROM PUBLIC;
REVOKE ALL     ON SCHEMA public                     FROM PUBLIC;
REVOKE ALL     ON ALL TABLES    IN SCHEMA public    FROM PUBLIC;
REVOKE ALL     ON ALL SEQUENCES IN SCHEMA public    FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public    FROM PUBLIC;   -- ¡EXECUTE es público por defecto!

-- Punto de partida limpio para los grupos (idempotencia)
REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM rol_app_lectura, rol_app_escritura, rol_soporte,
                                                  rol_reportes, rol_auditor, admin_datos, app_web;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM rol_app_lectura, rol_app_escritura, rol_soporte,
                                                  rol_reportes, rol_auditor, admin_datos, app_web;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM rol_app_lectura, rol_app_escritura, rol_soporte,
                                                      rol_reportes, rol_auditor, admin_datos, app_web;

-- pgcrypto: sólo el dueño (sus funciones SECURITY DEFINER la usan)
GRANT EXECUTE ON FUNCTION crypt(text, text), gen_salt(text, integer) TO foodstore_owner;

-- El dueño de los objetos no es dueño del esquema: sin esto, al revocar a
-- PUBLIC, sus funciones SECURITY DEFINER dejan de "ver" las tablas.
GRANT USAGE, CREATE ON SCHEMA public TO foodstore_owner;

-- Conexión y uso del esquema
GRANT CONNECT ON DATABASE foodstore_u5 TO app_web, admin_datos, soporte_mesa, reportes_bi, auditor_seg;
GRANT USAGE   ON SCHEMA public TO rol_app_lectura, rol_app_escritura, rol_soporte,
                                  rol_reportes, rol_auditor, admin_datos;

-- ---------------------------------------------------------------------
-- 3. rol_app_lectura — Req. 1
-- ---------------------------------------------------------------------
GRANT SELECT ON categoria, producto, pedido, detalle_pedido TO rol_app_lectura;
-- Permiso a nivel de columna: nunca password_hash, intentos_fallidos ni bloqueado
GRANT SELECT (id, nombre, email, rol, telefono, direccion) ON usuario TO rol_app_lectura;

-- ---------------------------------------------------------------------
-- 4. rol_app_escritura — Req. 2
-- ---------------------------------------------------------------------
GRANT INSERT ON pedido, detalle_pedido TO rol_app_escritura;
GRANT UPDATE (estado, eliminado) ON pedido         TO rol_app_escritura;
GRANT UPDATE (eliminado)         ON detalle_pedido TO rol_app_escritura;
GRANT USAGE ON SEQUENCE pedido_id_seq, detalle_pedido_id_seq TO rol_app_escritura;
GRANT EXECUTE ON FUNCTION fn_autenticar(text, text) TO rol_app_escritura;

-- ---------------------------------------------------------------------
-- 5. rol_soporte — Req. 3
-- ---------------------------------------------------------------------
GRANT SELECT (id, nombre, email, rol, telefono, fecha_alta, bloqueado, intentos_fallidos)
      ON usuario TO rol_soporte;
GRANT UPDATE (bloqueado) ON usuario TO rol_soporte;
GRANT SELECT ON pedido, detalle_pedido TO rol_soporte;
GRANT EXECUTE ON FUNCTION fn_resetear_password(bigint, text) TO rol_soporte;

-- ---------------------------------------------------------------------
-- 6. rol_reportes — Req. 4  (usuario_anon se otorga en usuario_anon.sql)
-- ---------------------------------------------------------------------
GRANT SELECT ON categoria, producto, pedido, detalle_pedido, venta_diaria_categoria TO rol_reportes;

-- ---------------------------------------------------------------------
-- 7. rol_auditor — Req. 5 (separación de funciones)
-- ---------------------------------------------------------------------
GRANT SELECT ON auditoria_login, auditoria_password TO rol_auditor;

-- ---------------------------------------------------------------------
-- 8. admin_datos — Req. 6.2 / 6.3: DML sobre negocio, sólo lectura sobre auditoría
-- ---------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO admin_datos;
REVOKE INSERT, UPDATE, DELETE ON auditoria_login, auditoria_password FROM admin_datos;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO admin_datos;
REVOKE USAGE, SELECT, UPDATE ON SEQUENCE auditoria_login_id_seq, auditoria_password_id_seq FROM admin_datos;

-- ---------------------------------------------------------------------
-- 9. Membresías de login (sin ADMIN OPTION: nadie puede delegar)
-- ---------------------------------------------------------------------
GRANT rol_app_lectura, rol_app_escritura TO app_web;
GRANT rol_soporte  TO soporte_mesa;
GRANT rol_reportes TO reportes_bi;
GRANT rol_auditor  TO auditor_seg;

-- ---------------------------------------------------------------------
-- 10. Disparadores de la Unidad 4: corren como el dueño
--     (si no, app_web necesitaría escribir venta_diaria_categoria)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    f RECORD;
BEGIN
    FOR f IN SELECT p.oid::regprocedure AS firma
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'public'
               AND (p.proname LIKE 'fn\_vdc\_%' OR p.proname LIKE 'fn\_clr\_%' OR p.proname LIKE 'fn\_rd\_%')
    LOOP
        EXECUTE format('ALTER FUNCTION %s SECURITY DEFINER SET search_path = public, pg_temp', f.firma);
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- 11. Política para objetos futuros — Req. 7.3
-- ---------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO admin_datos;
ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner IN SCHEMA public
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO admin_datos;
-- OJO: los default privileges POR ESQUEMA sólo pueden agregar permisos;
-- quitar el EXECUTE que PUBLIC recibe por defecto exige la forma global
-- (sin IN SCHEMA). Con IN SCHEMA el REVOKE se acepta pero no tiene efecto.
ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Prueba: objetos "futuros" creados por el dueño heredan la política
\echo '===== Objetos futuros: privilegios heredados ====='
BEGIN;
SET LOCAL ROLE foodstore_owner;
CREATE TABLE tabla_futura (id int);
CREATE FUNCTION fn_futura() RETURNS int LANGUAGE sql AS 'SELECT 1';
RESET ROLE;
SELECT 'tabla_futura' AS objeto, relacl::text AS acl FROM pg_class WHERE relname = 'tabla_futura'
UNION ALL
SELECT 'fn_futura()', proacl::text FROM pg_proc WHERE proname = 'fn_futura';
-- esperado: tabla → admin_datos=arwd ; función → sólo el dueño (sin =X/ para PUBLIC)
ROLLBACK;


-- =====================================================================
-- 12. PRUEBAS POSITIVAS Y NEGATIVAS (se deshacen al final)
-- =====================================================================
\echo '===== Pruebas de permisos ====='
CREATE OR REPLACE FUNCTION pg_temp.probar(p_rol TEXT, p_sql TEXT, p_espera BOOLEAN)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    ok BOOLEAN := TRUE;
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', p_rol);
        EXECUTE p_sql;
        RESET ROLE;
        RAISE SQLSTATE 'P0099';            -- deshace lo hecho en este bloque
    EXCEPTION
        WHEN SQLSTATE 'P0099' THEN ok := TRUE;
        WHEN insufficient_privilege THEN ok := FALSE;
    END;
    RESET ROLE;
    RETURN CASE WHEN ok = p_espera THEN 'OK  ' ELSE 'FALLA' END
        || ' | ' || rpad(p_rol, 14) || ' | ' || CASE WHEN ok THEN 'permitido' ELSE 'denegado ' END
        || ' | ' || p_sql;
END;
$$;

SELECT resultado FROM (VALUES
 (pg_temp.probar('app_web',      'SELECT id, nombre, email FROM usuario LIMIT 1', TRUE)),
 (pg_temp.probar('app_web',      'SELECT password_hash FROM usuario LIMIT 1', FALSE)),
 (pg_temp.probar('app_web',      'SELECT fn_autenticar(''x@x.com'', ''x'')', TRUE)),
 (pg_temp.probar('app_web',      'INSERT INTO pedido (fecha, usuario_id) VALUES (CURRENT_DATE, 1)', TRUE)),
 (pg_temp.probar('app_web',      'INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal) VALUES (1, 1, 1, 10, 10)', TRUE)),
 (pg_temp.probar('app_web',      'UPDATE pedido SET total = 0 WHERE id = 1', FALSE)),
 (pg_temp.probar('app_web',      'DELETE FROM pedido WHERE id = 1', FALSE)),
 (pg_temp.probar('app_web',      'SELECT fn_resetear_password(1, ''NuevaClave123'')', FALSE)),
 (pg_temp.probar('soporte_mesa', 'SELECT email, bloqueado FROM usuario LIMIT 1', TRUE)),
 (pg_temp.probar('soporte_mesa', 'UPDATE usuario SET bloqueado = TRUE WHERE id = 1', TRUE)),
 (pg_temp.probar('soporte_mesa', 'UPDATE usuario SET email = ''x@x.com'' WHERE id = 1', FALSE)),
 (pg_temp.probar('soporte_mesa', 'SELECT fn_resetear_password(1, ''NuevaClave123'')', TRUE)),
 (pg_temp.probar('soporte_mesa', 'SELECT * FROM auditoria_password', FALSE)),
 (pg_temp.probar('reportes_bi',  'SELECT SUM(total) FROM pedido', TRUE)),
 (pg_temp.probar('reportes_bi',  'SELECT nombre FROM usuario LIMIT 1', FALSE)),
 (pg_temp.probar('auditor_seg',  'SELECT * FROM auditoria_login LIMIT 1', TRUE)),
 (pg_temp.probar('auditor_seg',  'SELECT * FROM pedido LIMIT 1', FALSE)),
 (pg_temp.probar('admin_datos',  'UPDATE producto SET stock = stock WHERE id = 1', TRUE)),
 (pg_temp.probar('admin_datos',  'DELETE FROM auditoria_login', FALSE)),
 (pg_temp.probar('admin_datos',  'CREATE TABLE intrusa (x int)', FALSE)),
 (pg_temp.probar('admin_datos',  'GRANT admin_datos TO app_web', FALSE)),
 (pg_temp.probar('app_web',      'GRANT admin_datos TO rol_app_lectura', FALSE))
) AS t(resultado);
