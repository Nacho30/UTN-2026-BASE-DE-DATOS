-- =====================================================================
-- simulacro_incidente.sql — Parte C, punto 1
-- SIMULACRO CONTROLADO. Se ejecuta SÓLO contra foodstore_u5 del entorno
-- de desarrollo propio. Lo orquesta scripts/ejecutar_simulacro.sh.
--
-- Escenario (lo conoce el equipo, NO se le da a la IA):
--   Las credenciales de app_web se filtraron (p. ej. un .env subido por
--   error). El atacante se conecta directo a la base desde otro origen
--   (127.0.0.2 en el simulacro), prueba contraseñas contra una cuenta ADMIN
--   de la aplicación, entra, vuelca los datos de contacto de todos los
--   usuarios e intenta escalar a admin_datos.
-- =====================================================================
\set ON_ERROR_STOP off
\set victima 'micaela.castro50@yahoo.com.ar'
-- Las llamadas usan parámetros enlazados (\bind), como una app real:
-- así la contraseña probada no queda copiada en el log (ver informe).

\echo '--- Paso 1: intentos fallidos contra fn_autenticar'
SELECT fn_autenticar($1, $2) AS intento_1 \bind :victima 'micaela2025' \g
SELECT pg_sleep(1);
SELECT fn_autenticar($1, $2) AS intento_2 \bind :victima 'Micaela50' \g
SELECT pg_sleep(1);
SELECT fn_autenticar($1, $2) AS intento_3 \bind :victima 'FoodStore2026' \g
SELECT pg_sleep(1);
SELECT fn_autenticar($1, $2) AS intento_4 \bind :victima 'Castro50!' \g
SELECT pg_sleep(1);

\echo '--- Paso 2: inicio de sesión exitoso (4 fallos: debajo del umbral de bloqueo de 5)'
SELECT fn_autenticar($1, $2) AS intento_5_exito \bind :victima 'Clave50!' \g

\echo '--- Paso 3: lectura masiva de la tabla usuario'
SELECT count(*) AS filas_volcadas
FROM (SELECT id, nombre, email, telefono, direccion, rol FROM usuario) volcado;
-- ...y prueba de leer también los hashes (debe fallar por el permiso de columna)
SELECT id, email, password_hash FROM usuario LIMIT 5;

\echo '--- Paso 4: intentos de escalamiento a admin_datos'
GRANT admin_datos TO rol_app_lectura;                 -- otorgarse membresía
SET ROLE admin_datos;                                  -- asumir el rol directamente
SELECT fn_resetear_password(50, 'TomaDeCuenta2026');   -- operación reservada a soporte
DELETE FROM auditoria_login WHERE usuario_id = 50;     -- borrar el rastro

\echo '--- Verificación: ¿app_web ganó algún privilegio?'
SELECT pg_has_role('app_web', 'admin_datos', 'MEMBER')           AS es_miembro_admin,
       has_table_privilege('app_web', 'auditoria_login', 'DELETE') AS puede_borrar_auditoria,
       has_function_privilege('app_web', 'fn_resetear_password(bigint,text)', 'EXECUTE') AS puede_resetear;
