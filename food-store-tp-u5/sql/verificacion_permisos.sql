-- =====================================================================
-- verificacion_permisos.sql — Parte A, punto 3
-- Compara los privilegios reales contra la matriz de design.md.
-- Las dos consultas de diferencia deben devolver 0 filas: ni más, ni menos.
--   psql -d foodstore_u5 -f sql/verificacion_permisos.sql > docs/verificacion_permisos.txt
-- =====================================================================
\pset footer on
\echo '===== \\du ====='
\du

\echo '===== Membresías (pg_auth_members) ====='
SELECT r.rolname AS rol_grupo, m.rolname AS miembro, am.admin_option, am.inherit_option
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE m.rolname IN ('app_web','admin_datos','soporte_mesa','reportes_bi','auditor_seg')
ORDER BY 2, 1;

\echo '===== Privilegios de TABLA por rol (information_schema.role_table_grants) ====='
SELECT grantee, table_name, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privilegios
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes','rol_auditor','admin_datos','PUBLIC')
GROUP BY grantee, table_name
ORDER BY grantee, table_name;

\echo '===== Privilegios de COLUMNA sobre usuario (information_schema.column_privileges) ====='
SELECT grantee, privilege_type, string_agg(column_name, ', ' ORDER BY column_name) AS columnas
FROM information_schema.column_privileges
WHERE table_schema = 'public' AND table_name = 'usuario'
  AND grantee IN ('rol_app_lectura','rol_soporte')
GROUP BY grantee, privilege_type
ORDER BY 1, 2;

\echo '===== EXECUTE sobre funciones de credenciales ====='
SELECT routine_name, grantee
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public' AND routine_name IN ('fn_autenticar','fn_resetear_password')
ORDER BY 1, 2;

-- ---------------------------------------------------------------------
-- Matriz esperada (design.md), a nivel de tabla, para los roles de grupo
-- ---------------------------------------------------------------------
CREATE TEMP TABLE esperado (grantee TEXT, table_name TEXT, privilege_type TEXT);

INSERT INTO esperado
SELECT 'rol_app_lectura', t, 'SELECT' FROM unnest(ARRAY['categoria','producto','pedido','detalle_pedido']) t
UNION ALL
SELECT 'rol_app_escritura', t, 'INSERT' FROM unnest(ARRAY['pedido','detalle_pedido']) t
UNION ALL
SELECT 'rol_soporte', t, 'SELECT' FROM unnest(ARRAY['pedido','detalle_pedido']) t
UNION ALL
SELECT 'rol_reportes', t, 'SELECT'
FROM unnest(ARRAY['categoria','producto','pedido','detalle_pedido','venta_diaria_categoria']) t
UNION ALL
SELECT 'rol_auditor', t, 'SELECT' FROM unnest(ARRAY['auditoria_login','auditoria_password']) t
UNION ALL
-- admin_datos: DML sobre todas las tablas y vistas de negocio, sólo SELECT sobre auditoría
SELECT 'admin_datos', c.relname, p
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
     unnest(CASE WHEN c.relname LIKE 'auditoria\_%' THEN ARRAY['SELECT']
                 ELSE ARRAY['SELECT','INSERT','UPDATE','DELETE'] END) p
WHERE n.nspname = 'public' AND c.relkind IN ('r','v');

-- usuario_anon se agrega en la Parte D
INSERT INTO esperado
SELECT 'rol_reportes', 'usuario_anon', 'SELECT'
WHERE to_regclass('public.usuario_anon') IS NOT NULL;

CREATE TEMP VIEW real AS
SELECT grantee::text, table_name::text, privilege_type::text
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes','rol_auditor','admin_datos','PUBLIC');

\echo '===== SOBRAN (otorgados y no previstos en la spec) — esperado: 0 filas ====='
SELECT * FROM real EXCEPT SELECT * FROM esperado ORDER BY 1, 2, 3;

\echo '===== FALTAN (previstos en la spec y no otorgados) — esperado: 0 filas ====='
SELECT * FROM esperado EXCEPT SELECT * FROM real ORDER BY 1, 2, 3;

\echo '===== Privilegios por defecto para objetos futuros (pg_default_acl) ====='
SELECT pg_get_userbyid(d.defaclrole) AS para_objetos_de, n.nspname AS esquema,
       CASE d.defaclobjtype WHEN 'r' THEN 'tablas' WHEN 'S' THEN 'secuencias' WHEN 'f' THEN 'funciones' END AS tipo,
       d.defaclacl AS acl
FROM pg_default_acl d LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
ORDER BY tipo;
