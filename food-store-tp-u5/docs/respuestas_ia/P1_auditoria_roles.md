# P1 — Respuesta completa de la IA (Parte A.4)

- **Asistente:** Claude (Anthropic), ejecutado como un agente independiente.
- **Entrada:** sólo el prompt P1 de `docs/prompts.md`, el contenido de `sql/roles.sql` sin la sección de pruebas y una línea con los nombres de las tablas y funciones. Sin acceso al repositorio, a `00_punto_de_partida.sql`, a la base ni a esta conversación.
- **Fecha:** 2026-10-19.
- **Validación:** [`P1_validacion.txt`](P1_validacion.txt) y entradas A-1 a A-4 de `BITACORA.md`.

---

# Auditoría de `roles.sql` (Food Store, PostgreSQL 16)

**Respuesta corta:** la base del script es buena. Hay cuatro problemas graves que corregir:
- `admin_datos` tiene permisos de más sobre `usuario`.
- Soporte puede tomar cualquier cuenta con `fn_resetear_password`.
- Las funciones SECURITY DEFINER principales no tienen `search_path` fijo.
- El script no limpia lo que ya existía en roles creados antes.

Además, a la aplicación probablemente le faltan permisos para registrar usuarios, y quizás para generar el salt de las contraseñas.

**Lo que está bien:**
- Ningún rol tiene atributos de superusuario y el dueño `foodstore_owner` no puede iniciar sesión.
- Se le quitan a PUBLIC los permisos que trae por defecto, incluido TEMP sobre la base.
- Los permisos sobre `usuario` son por columna y no exponen `password_hash`.
- Las membresías se dan sin ADMIN OPTION.
- Cada usuario de login tiene un tope de conexiones.
- Las funciones nuevas no quedan ejecutables por PUBLIC.

---

## 1. Hallazgos

### CRÍTICO

**C1. `admin_datos` puede tomar cualquier cuenta y alterar datos que deberían ser derivados.**
- La sección 8 le da `SELECT, INSERT, UPDATE, DELETE ON ALL TABLES` y solo excluye las tablas de auditoría. Eso incluye `usuario`, así que puede:
  - Leer `password_hash` de todos los usuarios y crackearlos fuera de la base.
  - Cambiar `password_hash` de cualquiera y entrar con esa cuenta.
  - Hacer `UPDATE usuario SET rol = 'admin'`, o sea, subir de nivel en la aplicación.
  - Borrar usuarios.
- También puede modificar a mano `venta_diaria_categoria`, que deberían mantener solo los disparadores, y borrar pedidos de verdad aunque el modelo usa borrado lógico (`eliminado`).
- Con `UPDATE` sobre secuencias puede hacer `setval()` y provocar colisiones de claves.
- El `ALTER DEFAULT PRIVILEGES` de la sección 11 repite el error hacia adelante: toda tabla futura, incluida una nueva tabla de auditoría o de tokens, le queda con escritura automática.
- Además, los permisos se dan directo al usuario de login y no a un rol de grupo, como sí se hace con los demás.

**C2. Soporte puede tomar cualquier cuenta con `fn_resetear_password(bigint, text)`.**
- `rol_soporte` puede ponerle la contraseña que quiera a cualquier usuario, incluidos los administradores de la aplicación, y después entrar como esa persona.
- Como la función es SECURITY DEFINER, dentro de ella `current_user` es `foodstore_owner`. Si la auditoría registra `current_user`, no queda constancia de quién hizo el reseteo; hay que usar `session_user`.

### ALTO

**A1. Las funciones SECURITY DEFINER principales no tienen `search_path` fijo.**
- La sección 10 lo fija solo para los disparadores `fn_vdc_*`, `fn_clr_*` y `fn_rd_*`. No lo hace para `fn_autenticar` ni para `fn_resetear_password`, que son justamente las que corren con permisos de dueño y tocan `usuario`.
- Si `pg_temp` no figura de forma explícita, PostgreSQL lo busca **primero** para tablas. Quien recupere permiso TEMP podría crear una tabla temporal `usuario` y desviar la función.
- Hoy el riesgo está tapado por el `REVOKE ALL ON DATABASE ... FROM PUBLIC`, pero depende de que nadie vuelva a dar TEMP.

**A2. El script no limpia el estado previo.** Las líneas `IF NOT EXISTS ... CREATE ROLE` no tocan un rol que ya existe. Por eso, si la base ya tenía configuración:
- Los roles de grupo y de login conservan `REPLICATION` o `BYPASSRLS`, porque esos `ALTER ROLE` no dicen `NOREPLICATION NOBYPASSRLS`. Solo el dueño los lleva.
- Se conservan todas las membresías anteriores, incluidas las de roles predefinidos peligrosos: `pg_read_all_data`, `pg_write_all_data`, `pg_execute_server_program`, `pg_read_server_files` y `pg_signal_backend`. También queda cualquier miembro inesperado de `foodstore_owner`.
- La sección 2 no les quita nada a `soporte_mesa`, `reportes_bi` ni `auditor_seg`, así que conservan permisos dados antes directamente a ellos.
- `REVOKE ... FROM PUBLIC` sobre la base y el esquema no saca permisos que se hayan dado directamente a cada rol, por ejemplo CREATE sobre `public` o TEMP sobre la base.

**A3. La aplicación puede manipular pedidos ajenos, estados y precios.**
- `rol_app_escritura` tiene INSERT en **todas** las columnas de `pedido` y `detalle_pedido`, y `UPDATE (estado)` sobre cualquier pedido.
- Si la aplicación tiene un bug o una inyección SQL, se puede crear un pedido a nombre de otro cliente, insertarlo ya como pagado o entregado, poner un precio unitario o total arbitrario, o cambiar el estado de pedidos ajenos.
- La base no aplica ninguna de estas reglas.

**A4. Quedan objetos fuera de la propiedad de `foodstore_owner`.**
- En PostgreSQL 15 y posteriores el esquema `public` pertenece a `pg_database_owner`, es decir, a quien sea dueño de la base. Ese rol puede hacer cualquier cosa en el esquema.
- El ciclo de la sección 1 omite tablas particionadas (`p`), tablas foráneas (`f`), secuencias independientes (`S`) y procedimientos.

**A5. Las contraseñas pueden quedar en los logs.**
- `ALTER ROLE ... PASSWORD :'pw'` manda la contraseña en texto plano al servidor. Con `log_statement = 'ddl'` o `'all'`, o si la sentencia falla (`log_min_error_statement`), queda en los logs.
- No se valida que la variable de entorno esté definida ni que no esté vacía. En PostgreSQL, `PASSWORD ''` deja el rol sin contraseña.
- No hay `ON_ERROR_STOP`, así que si algo falla psql sigue ejecutando y la base queda en un estado intermedio.

**A6. Cuidado con `CREATEROLE` en PostgreSQL 16.**
- Si el script lo ejecuta un usuario con `CREATEROLE` que no es superusuario, PostgreSQL 16 le da automáticamente ADMIN OPTION sobre cada rol que crea. Ese usuario puede después darse `foodstore_owner` a sí mismo.
- Conviene ejecutarlo como superusuario y revisar `pg_auth_members`.

### MEDIO: permisos que faltan para que la aplicación funcione

**M1. No hay forma de registrar usuarios ni de editar el perfil.**
- `rol_app_escritura` no tiene INSERT ni UPDATE sobre `usuario`, ni USAGE sobre `usuario_id_seq`.
- Si la aplicación permite registrarse o editar el perfil, va a fallar. Ver la sección 2.6.

**M2. Puede faltar una variante de `gen_salt`.**
- `REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC` también les quita el permiso a las funciones de pgcrypto. Después solo se le devuelven al dueño `crypt(text,text)` y `gen_salt(text,integer)`.
- Si `fn_resetear_password` o una futura función de registro usa `gen_salt('bf')` (la variante de un argumento), `digest` o `gen_random_bytes`, va a fallar con *permission denied*.

**M3. Desbloquear no reinicia el contador de intentos.**
- `rol_soporte` puede cambiar `bloqueado`, pero no `intentos_fallidos`.
- Al desbloquear, el contador sigue alto y el usuario vuelve a quedar bloqueado en el próximo intento fallido.

**M4. Choque con el script que da permisos sobre `usuario_anon`.**
- Si ese otro script corre **antes** que este, la sección 2 (`REVOKE ALL ON ALL TABLES ... FROM rol_reportes`) borra el permiso sobre la vista.
- Lo mismo vale para cualquier permiso que den otros scripts a estos roles.

**M5. Nadie puede ejecutar migraciones como dueño.**
- `foodstore_owner` es NOLOGIN y no tiene miembros. Las migraciones se van a correr con otro usuario, y entonces:
  - Los objetos nuevos quedan a nombre de ese otro usuario.
  - El `ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner` no se aplica.

**M6. Posible falta de UPDATE sobre stock (condicional).**
- Si el flujo de pedido descuenta stock, `rol_app_escritura` no tiene `UPDATE (stock)` sobre `producto`.

### MEDIO: exposición de datos y malas prácticas

**M7. La aplicación ve datos de todos los clientes.**
- `rol_app_lectura` lee email, teléfono y dirección de **todos** los usuarios, y todos los pedidos de todos los clientes.
- Cualquier error en la aplicación que permita pedir datos de otro (IDOR) o una inyección SQL expone a toda la clientela.
- Conviene agregar RLS como segunda barrera.

**M8. La sección 10 elige funciones por nombre.**
- Con un `LIKE` sobre el nombre, una función común que se llame `fn_rd_algo` pasaría a SECURITY DEFINER sin que nadie lo note.
- Hay que filtrar además por `prorettype = 'trigger'`.

**M9. `rol_app_escritura` depende de `rol_app_lectura`.**
- `UPDATE ... WHERE id = ...` e `INSERT ... RETURNING` necesitan SELECT, que solo llega a través de `rol_app_lectura`.
- Funciona porque `app_web` tiene los dos roles, pero `rol_app_escritura` sola no alcanza.

### BAJO
- **Membresías:** se dan sin las opciones de PostgreSQL 16. Lo prolijo es `WITH INHERIT TRUE, SET FALSE` para que los usuarios de login no hagan `SET ROLE` a los grupos.
- **Límites por rol:** no hay `statement_timeout`, `idle_in_transaction_session_timeout` ni `default_transaction_read_only` para los roles que solo leen (`reportes_bi`, `auditor_seg`).
- **Vencimiento:** no hay `VALID UNTIL` para las cuentas de personas (`admin_datos`, `soporte_mesa`, `auditor_seg`).
- **Tipos:** los privilegios por defecto no le quitan a PUBLIC `USAGE ON TYPES` (impacto menor).

---

## 2. Correcciones (script listo para aplicar)

Ejecutarlo como superusuario, **después** de `roles.sql` o en su reemplazo, con `psql -v ON_ERROR_STOP=1`. Los nombres de secuencias y columnas que no aparecen en el adjunto están marcados como **SUPUESTO**.

```sql
\set ON_ERROR_STOP on
\getenv pw_app_web     PW_APP_WEB
\getenv pw_admin_datos PW_ADMIN_DATOS
\getenv pw_soporte     PW_SOPORTE
\getenv pw_reportes    PW_REPORTES
\getenv pw_auditor     PW_AUDITOR
\getenv pw_migrador    PW_MIGRADOR

-- 2.0 Validar contraseñas (si una variable no existe, psql falla acá por ON_ERROR_STOP)
SELECT length(:'pw_app_web') >= 16 AND length(:'pw_admin_datos') >= 16
   AND length(:'pw_soporte') >= 16 AND length(:'pw_reportes')   >= 16
   AND length(:'pw_auditor') >= 16 AND length(:'pw_migrador')   >= 16 AS pw_ok \gset
\if :pw_ok
\else
  DO $$ BEGIN RAISE EXCEPTION 'Contraseña vacía o menor a 16 caracteres'; END $$;
\endif

BEGIN;
SET LOCAL log_statement = 'none';          -- requiere superusuario; evita que las contraseñas queden en el log
SET LOCAL log_min_error_statement = 'panic';

-- 2.1 Roles nuevos: grupo para admin_datos y usuario migrador
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_admin_datos') THEN
    CREATE ROLE rol_admin_datos NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'migrador') THEN
    CREATE ROLE migrador LOGIN;
  END IF;
END $$;

-- 2.2 Atributos completos y explícitos (pisa lo que hubiera de antes)
ALTER ROLE foodstore_owner   NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;
ALTER ROLE rol_app_lectura   NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;
ALTER ROLE rol_app_escritura NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;
ALTER ROLE rol_soporte       NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;
ALTER ROLE rol_reportes      NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;
ALTER ROLE rol_auditor       NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;
ALTER ROLE rol_admin_datos   NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT;

ALTER ROLE app_web      LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT CONNECTION LIMIT 50 PASSWORD :'pw_app_web';
ALTER ROLE admin_datos  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT CONNECTION LIMIT 3  PASSWORD :'pw_admin_datos' VALID UNTIL '2027-04-30';
ALTER ROLE soporte_mesa LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT CONNECTION LIMIT 5  PASSWORD :'pw_soporte'     VALID UNTIL '2027-04-30';
ALTER ROLE reportes_bi  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT CONNECTION LIMIT 5  PASSWORD :'pw_reportes';
ALTER ROLE auditor_seg  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS INHERIT CONNECTION LIMIT 2  PASSWORD :'pw_auditor'     VALID UNTIL '2027-04-30';
ALTER ROLE migrador     LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT CONNECTION LIMIT 1 PASSWORD :'pw_migrador';

-- 2.3 Limpiar membresías que no forman parte del diseño (incluye roles predefinidos pg_*)
DO $$
DECLARE m RECORD;
BEGIN
  FOR m IN
    SELECT g.rolname AS grupo, u.rolname AS miembro, gr.rolname AS otorgante
    FROM pg_auth_members am
    JOIN pg_roles g  ON g.oid  = am.roleid
    JOIN pg_roles u  ON u.oid  = am.member
    JOIN pg_roles gr ON gr.oid = am.grantor
    WHERE (u.rolname IN ('foodstore_owner','rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
                         'rol_auditor','rol_admin_datos','app_web','admin_datos','soporte_mesa',
                         'reportes_bi','auditor_seg','migrador')
           OR g.rolname IN ('foodstore_owner','rol_app_lectura','rol_app_escritura','rol_soporte',
                            'rol_reportes','rol_auditor','rol_admin_datos'))
      AND (u.rolname, g.rolname) NOT IN (VALUES
            ('app_web','rol_app_lectura'), ('app_web','rol_app_escritura'),
            ('soporte_mesa','rol_soporte'), ('reportes_bi','rol_reportes'),
            ('auditor_seg','rol_auditor'),  ('admin_datos','rol_admin_datos'),
            ('migrador','foodstore_owner'))
  LOOP
    RAISE NOTICE 'Revocando membresía % -> % (otorgada por %)', m.miembro, m.grupo, m.otorgante;
    EXECUTE format('REVOKE %I FROM %I GRANTED BY %I CASCADE', m.grupo, m.miembro, m.otorgante);
  END LOOP;
END $$;

-- 2.4 Base de datos y esquema: el dueño es foodstore_owner; se limpian permisos directos
ALTER SCHEMA public OWNER TO foodstore_owner;

REVOKE ALL ON DATABASE foodstore_u5 FROM PUBLIC, app_web, admin_datos, soporte_mesa, reportes_bi, auditor_seg, migrador,
       rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, rol_auditor, rol_admin_datos;
REVOKE ALL ON SCHEMA public FROM PUBLIC, app_web, admin_datos, soporte_mesa, reportes_bi, auditor_seg, migrador,
       rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, rol_auditor, rol_admin_datos;

REVOKE ALL     ON ALL TABLES    IN SCHEMA public FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
               rol_auditor, rol_admin_datos, app_web, admin_datos, soporte_mesa, reportes_bi, auditor_seg, migrador;
REVOKE ALL     ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
               rol_auditor, rol_admin_datos, app_web, admin_datos, soporte_mesa, reportes_bi, auditor_seg, migrador;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
               rol_auditor, rol_admin_datos, app_web, admin_datos, soporte_mesa, reportes_bi, auditor_seg, migrador;

GRANT CONNECT ON DATABASE foodstore_u5 TO app_web, admin_datos, soporte_mesa, reportes_bi, auditor_seg, migrador;
GRANT USAGE ON SCHEMA public TO rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, rol_auditor, rol_admin_datos;

-- 2.5 Propiedad completa: tablas particionadas, tablas foráneas, secuencias independientes y procedimientos
DO $$
DECLARE o RECORD;
BEGIN
  FOR o IN
    SELECT c.oid::regclass AS obj, c.relkind
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN ('r','p','v','m','f','S')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d
                      WHERE d.classid = 'pg_class'::regclass AND d.objid = c.oid
                        AND d.deptype IN ('a','i','e'))   -- secuencias de serial/identity y objetos de extensiones
  LOOP
    EXECUTE format('ALTER %s %s OWNER TO foodstore_owner',
      CASE o.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW'
                     WHEN 'f' THEN 'FOREIGN TABLE' WHEN 'S' THEN 'SEQUENCE' ELSE 'TABLE' END, o.obj);
  END LOOP;
  FOR o IN
    SELECT p.oid::regprocedure AS firma
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind IN ('f','p')
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
  LOOP
    EXECUTE format('ALTER ROUTINE %s OWNER TO foodstore_owner', o.firma);
  END LOOP;
END $$;

-- pgcrypto: el dueño necesita todas las variantes que usan sus funciones
GRANT EXECUTE ON FUNCTION crypt(text, text), gen_salt(text), gen_salt(text, integer) TO foodstore_owner;

-- 2.6 Permisos por rol de grupo
-- rol_app_lectura (sin cambios; ver RLS en la sección 3)
GRANT SELECT ON categoria, producto, pedido, detalle_pedido TO rol_app_lectura;
GRANT SELECT (id, nombre, email, rol, telefono, direccion) ON usuario TO rol_app_lectura;

-- rol_app_escritura
GRANT INSERT ON pedido, detalle_pedido TO rol_app_escritura;          -- protegido con los disparadores de la sección 4
GRANT UPDATE (estado, eliminado) ON pedido         TO rol_app_escritura;
GRANT UPDATE (eliminado)         ON detalle_pedido TO rol_app_escritura;
GRANT USAGE ON SEQUENCE pedido_id_seq, detalle_pedido_id_seq TO rol_app_escritura;
GRANT EXECUTE ON FUNCTION fn_autenticar(text, text) TO rol_app_escritura;
-- Registro y perfil: SIN rol, bloqueado ni intentos_fallidos. Si existe, mejor una función
-- fn_registrar_usuario SECURITY DEFINER que haga el hash con crypt() dentro de la base.
GRANT INSERT (nombre, email, telefono, direccion, password_hash) ON usuario TO rol_app_escritura;
GRANT UPDATE (nombre, telefono, direccion)                       ON usuario TO rol_app_escritura;
GRANT USAGE ON SEQUENCE usuario_id_seq TO rol_app_escritura;          -- SUPUESTO: nombre de la secuencia
-- Solo si el pedido descuenta stock (SUPUESTO):
-- GRANT UPDATE (stock) ON producto TO rol_app_escritura;

-- rol_soporte
GRANT SELECT (id, nombre, email, rol, telefono, fecha_alta, bloqueado, intentos_fallidos) ON usuario TO rol_soporte;
GRANT UPDATE (bloqueado, intentos_fallidos) ON usuario TO rol_soporte;
GRANT SELECT ON pedido, detalle_pedido TO rol_soporte;
GRANT EXECUTE ON FUNCTION fn_resetear_password(bigint, text) TO rol_soporte;   -- endurecer la función: sección 5

-- rol_reportes: usuario_anon se otorga ACÁ para no depender del orden de los scripts
GRANT SELECT ON categoria, producto, pedido, detalle_pedido, venta_diaria_categoria TO rol_reportes;
DO $$ BEGIN
  IF to_regclass('public.usuario_anon') IS NOT NULL THEN
    GRANT SELECT ON public.usuario_anon TO rol_reportes;
  END IF;
END $$;

-- rol_auditor
GRANT SELECT ON auditoria_login, auditoria_password TO rol_auditor;

-- rol_admin_datos: DML de negocio, sin tocar credenciales, resúmenes ni auditoría
GRANT SELECT, INSERT, UPDATE, DELETE ON categoria, producto TO rol_admin_datos;
GRANT SELECT, INSERT, UPDATE         ON pedido, detalle_pedido TO rol_admin_datos;   -- borrado lógico vía "eliminado"
GRANT SELECT ON venta_diaria_categoria, auditoria_login, auditoria_password TO rol_admin_datos;
GRANT SELECT (id, nombre, email, rol, telefono, direccion, fecha_alta, bloqueado, intentos_fallidos) ON usuario TO rol_admin_datos;
GRANT UPDATE (nombre, telefono, direccion, bloqueado, intentos_fallidos) ON usuario TO rol_admin_datos;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO rol_admin_datos;            -- sin UPDATE: sin setval()
REVOKE USAGE, SELECT ON SEQUENCE auditoria_login_id_seq, auditoria_password_id_seq FROM rol_admin_datos;

-- 2.7 Membresías con las opciones de PostgreSQL 16
GRANT rol_app_lectura, rol_app_escritura TO app_web      WITH INHERIT TRUE, SET FALSE;
GRANT rol_soporte                        TO soporte_mesa WITH INHERIT TRUE, SET FALSE;
GRANT rol_reportes                       TO reportes_bi  WITH INHERIT TRUE, SET FALSE;
GRANT rol_auditor                        TO auditor_seg  WITH INHERIT TRUE, SET FALSE;
GRANT rol_admin_datos                    TO admin_datos  WITH INHERIT TRUE, SET FALSE;
GRANT foodstore_owner                    TO migrador     WITH INHERIT FALSE, SET TRUE;   -- solo con SET ROLE explícito
ALTER ROLE migrador SET role = 'foodstore_owner';   -- así los objetos nuevos nacen del dueño y aplican los privilegios por defecto

-- 2.8 SECURITY DEFINER: search_path fijo en TODAS, pg_temp al final
ALTER FUNCTION fn_autenticar(text, text)          SET search_path = pg_catalog, public, pg_temp;
ALTER FUNCTION fn_resetear_password(bigint, text) SET search_path = pg_catalog, public, pg_temp;
REVOKE EXECUTE ON FUNCTION fn_autenticar(text, text), fn_resetear_password(bigint, text) FROM PUBLIC;

DO $$
DECLARE f RECORD;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS firma
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prorettype = 'trigger'::regtype                       -- solo funciones de disparador
      AND (p.proname LIKE 'fn\_vdc\_%' OR p.proname LIKE 'fn\_clr\_%' OR p.proname LIKE 'fn\_rd\_%')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SECURITY DEFINER SET search_path = pg_catalog, public, pg_temp', f.firma);
  END LOOP;
END $$;

-- 2.9 Privilegios por defecto: denegar todo; cada migración otorga explícitamente
ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner IN SCHEMA public
    REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM admin_datos;
ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner IN SCHEMA public
    REVOKE USAGE, SELECT, UPDATE ON SEQUENCES FROM admin_datos;
ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner REVOKE USAGE   ON TYPES     FROM PUBLIC;

-- 2.10 Límites por rol (default_transaction_read_only es una protección, no un control: el usuario puede cambiarlo)
ALTER ROLE app_web      SET statement_timeout = '5s';
ALTER ROLE app_web      SET idle_in_transaction_session_timeout = '30s';
ALTER ROLE soporte_mesa SET statement_timeout = '15s';
ALTER ROLE reportes_bi  SET statement_timeout = '120s';
ALTER ROLE reportes_bi  SET default_transaction_read_only = on;
ALTER ROLE auditor_seg  SET default_transaction_read_only = on;

COMMIT;
```

---

## 3. RLS como segunda barrera (opcional, recomendado)

**SUPUESTOS:**
- `pedido.usuario_id` es la columna que vincula el pedido con su cliente.
- La aplicación ejecuta `SET LOCAL app.usuario_id = '<id>'` en cada transacción.

Esto no reemplaza los controles de la aplicación, porque `app_web` puede fijar ese valor. Lo que hace es limitar el daño de una consulta mal armada. Si la aplicación también tiene un panel para el personal que usa `app_web`, hay que agregar una política para ese caso.

```sql
ALTER TABLE pedido ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_pedido_backoffice ON pedido FOR ALL
  TO rol_soporte, rol_reportes, rol_admin_datos
  USING (true) WITH CHECK (true);

CREATE POLICY p_pedido_cliente ON pedido FOR ALL
  TO rol_app_lectura, rol_app_escritura
  USING      (usuario_id = nullif(current_setting('app.usuario_id', true), '')::bigint)
  WITH CHECK (usuario_id = nullif(current_setting('app.usuario_id', true), '')::bigint);
-- Hacer lo mismo en detalle_pedido con EXISTS (SELECT 1 FROM pedido p WHERE p.id = detalle_pedido.pedido_id)
```

Los disparadores SECURITY DEFINER del dueño no se ven afectados, porque el dueño no queda sujeto a RLS mientras no se use `FORCE ROW LEVEL SECURITY`.

## 4. Proteger los INSERT de la aplicación (cierra A3)

**SUPUESTOS:** el estado inicial se llama `'pendiente'` y existen las columnas `detalle_pedido.precio_unitario`, `producto_id` y `producto.precio`. Ajustar los nombres a los reales.

```sql
CREATE OR REPLACE FUNCTION fn_guardia_pedido() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF current_user = 'app_web' THEN
    NEW.estado    := 'pendiente';
    NEW.eliminado := false;
  END IF;
  RETURN NEW;
END $$;
ALTER FUNCTION fn_guardia_pedido() OWNER TO foodstore_owner;
CREATE TRIGGER trg_guardia_pedido BEFORE INSERT ON pedido
  FOR EACH ROW EXECUTE FUNCTION fn_guardia_pedido();

CREATE OR REPLACE FUNCTION fn_guardia_detalle() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $$
BEGIN
  IF current_user = 'app_web' THEN
    SELECT p.precio INTO STRICT NEW.precio_unitario FROM producto p WHERE p.id = NEW.producto_id;
  END IF;
  RETURN NEW;
END $$;
ALTER FUNCTION fn_guardia_detalle() OWNER TO foodstore_owner;
CREATE TRIGGER trg_guardia_detalle BEFORE INSERT ON detalle_pedido
  FOR EACH ROW EXECUTE FUNCTION fn_guardia_detalle();
```

Para los UPDATE de `estado`, conviene agregar un disparador `BEFORE UPDATE` que solo deje pasar las transiciones válidas para `app_web`, por ejemplo pendiente → cancelado. Otra opción es reemplazar `GRANT UPDATE (estado)` por una función `fn_cancelar_pedido(bigint)`.

## 5. Endurecer `fn_resetear_password` (cierra C2)

No tengo el cuerpo de la función, así que va la guarda que debería tener al principio:

```sql
-- dentro de fn_resetear_password(p_id bigint, p_nueva text), antes de cambiar el hash:
IF EXISTS (SELECT 1 FROM usuario WHERE id = p_id AND rol = 'admin') THEN
  RAISE EXCEPTION 'Soporte no puede resetear cuentas administrativas' USING ERRCODE = '42501';
END IF;
-- registrar quién lo hizo con session_user (dentro de SECURITY DEFINER, current_user es el dueño):
INSERT INTO auditoria_password (usuario_id, ejecutado_por, fecha) VALUES (p_id, session_user, now());
```

Lo ideal es que la función no reciba la contraseña nueva. Que genere una temporal con `gen_random_bytes`, marque al usuario para que la cambie en el próximo ingreso y la devuelva una sola vez.

## 6. Consultas de verificación

```sql
-- Funciones SECURITY DEFINER sin search_path fijo (debe devolver 0 filas)
SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef
  AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) c WHERE c LIKE 'search_path=%');

-- Atributos peligrosos (debe devolver 0 filas)
SELECT rolname FROM pg_roles
WHERE rolname IN ('foodstore_owner','rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes','rol_auditor',
                  'rol_admin_datos','app_web','admin_datos','soporte_mesa','reportes_bi','auditor_seg','migrador')
  AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls);

-- Membresías completas, con sus opciones de PostgreSQL 16
SELECT g.rolname AS grupo, u.rolname AS miembro, am.admin_option, am.inherit_option, am.set_option, gr.rolname AS otorgante
FROM pg_auth_members am JOIN pg_roles g ON g.oid = am.roleid
JOIN pg_roles u ON u.oid = am.member JOIN pg_roles gr ON gr.oid = am.grantor
ORDER BY 1, 2;

-- Prueba puntual: admin_datos ya no puede tocar credenciales (debe dar false, false)
SELECT has_column_privilege('admin_datos', 'usuario', 'password_hash', 'SELECT'),
       has_column_privilege('admin_datos', 'usuario', 'rol', 'UPDATE');

-- Objetos de public que no son de foodstore_owner (debe devolver 0 filas, salvo los de extensiones)
SELECT c.oid::regclass, pg_get_userbyid(c.relowner) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relowner <> 'foodstore_owner'::regrole;
```

## 7. Recomendaciones operativas
- **Contraseñas:** mejor cargar en `PASSWORD` un hash SCRAM ya calculado (`SCRAM-SHA-256$...`) en vez del texto plano. Así ni el log ni el tráfico ven la contraseña. Confirmar `password_encryption = 'scram-sha-256'` y que `pg_hba.conf` use `scram-sha-256`.
- **Migraciones:** correrlas siempre con `migrador`, que al entrar asume `foodstore_owner`. Cada migración que cree una tabla debe incluir sus `GRANT` explícitos, porque con la política de denegar todo por defecto no hay permisos automáticos.
- **pgcrypto (opcional):** se puede mover a un esquema `extensiones` (`ALTER EXTENSION pgcrypto SET SCHEMA extensiones`) e incluirlo en el `search_path` de las funciones SECURITY DEFINER. Así no queda mezclado con los objetos de negocio.
