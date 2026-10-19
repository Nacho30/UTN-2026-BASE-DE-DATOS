-- =====================================================================
-- 00_punto_de_partida.sql
-- Reconstrucción de los artefactos previos a la Parte A (Clases 1 y 2):
--   * columnas de credenciales y datos personales en usuario
--   * tabla de auditoría de inicios de sesión de la aplicación
--   * fn_autenticar y fn_resetear_password
-- Se ejecuta UNA vez, como superusuario, sobre la copia de Food Store
-- poblada en las Unidades 1 a 4.  psql -d foodstore_u5 -f 00_punto_de_partida.sql
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------
-- 1. usuario: credenciales y datos personales
-- ---------------------------------------------------------------------
ALTER TABLE usuario
    ADD COLUMN IF NOT EXISTS password_hash     TEXT,
    ADD COLUMN IF NOT EXISTS telefono          VARCHAR(30),
    ADD COLUMN IF NOT EXISTS direccion         VARCHAR(200),
    ADD COLUMN IF NOT EXISTS fecha_alta        DATE,
    ADD COLUMN IF NOT EXISTS intentos_fallidos INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS bloqueado         BOOLEAN NOT NULL DEFAULT FALSE;

-- Datos personales verosímiles (todos ficticios), deterministas por id,
-- para que la anonimización de la Parte D tenga algo real que proteger.
WITH nombres AS (
    SELECT ARRAY['Martina','Juan','Sofía','Mateo','Valentina','Santiago','Camila','Benjamín',
                 'Lucía','Tomás','Julieta','Nicolás','Florencia','Agustín','Micaela','Facundo',
                 'Rocío','Lautaro','Carolina','Joaquín','Paula','Franco','Abril','Gonzalo'] AS n,
           ARRAY['González','Rodríguez','Fernández','López','Martínez','García','Pérez','Romero',
                 'Sosa','Torres','Álvarez','Ruiz','Ramírez','Flores','Benítez','Acosta',
                 'Medina','Herrera','Suárez','Aguirre','Giménez','Molina','Castro','Ortiz'] AS a,
           ARRAY['gmail.com','hotmail.com','yahoo.com.ar','outlook.com'] AS d,
           ARRAY['Av. Corrientes','San Martín','Belgrano','Rivadavia','Mitre','Sarmiento',
                 'Av. Colón','Italia','9 de Julio','Urquiza'] AS c
)
UPDATE usuario u SET
    nombre    = n[1 + (u.id * 7)  % 24] || ' ' || a[1 + (u.id * 11) % 24],
    email     = lower(translate(n[1 + (u.id * 7) % 24] || '.' || a[1 + (u.id * 11) % 24],
                                'áéíóúÁÉÍÓÚñ', 'aeiouAEIOUn'))
                || u.id || '@' || d[1 + u.id % 4],
    telefono  = '+54 9 261 ' || lpad(((u.id * 7919) % 10000000)::text, 7, '0'),
    direccion = c[1 + u.id % 10] || ' ' || (100 + (u.id * 37) % 4900),
    fecha_alta = DATE '2024-10-01' + ((u.id * 97) % 749)::int,
    rol = CASE WHEN u.id BETWEEN 801 AND 804 THEN 'LOGISTICA'
               WHEN u.id % 50 = 0             THEN 'ADMIN'
               WHEN u.id % 10 = 3             THEN 'REPARTIDOR'
               ELSE 'CLIENTE' END
FROM nombres;

-- Contraseñas: hash bcrypt (cost 6 para que la carga sea rápida en desarrollo)
UPDATE usuario SET password_hash = crypt('Clave' || id || '!', gen_salt('bf', 6));

ALTER TABLE usuario ALTER COLUMN password_hash SET NOT NULL;
ALTER TABLE usuario ALTER COLUMN fecha_alta    SET NOT NULL;

-- ---------------------------------------------------------------------
-- 2. Auditoría de inicios de sesión de la APLICACIÓN.
--    fn_autenticar es una función: un login fallido de la app no es un
--    error de autenticación del motor y no aparece con log_connections.
--    Por eso deja su propio registro (tabla + RAISE LOG al log del server).
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS auditoria_login (
    id              BIGSERIAL PRIMARY KEY,
    momento         TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    email_intentado VARCHAR(150) NOT NULL,
    usuario_id      BIGINT,
    exito           BOOLEAN     NOT NULL,
    motivo          VARCHAR(40) NOT NULL,
    rol_db          NAME        NOT NULL DEFAULT session_user,
    ip_cliente      INET                 DEFAULT inet_client_addr(),
    aplicacion      TEXT                 DEFAULT current_setting('application_name', true)
);

CREATE TABLE IF NOT EXISTS auditoria_password (
    id         BIGSERIAL PRIMARY KEY,
    momento    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    usuario_id BIGINT      NOT NULL,
    rol_db     NAME        NOT NULL DEFAULT session_user,
    ip_cliente INET                 DEFAULT inet_client_addr()
);

-- ---------------------------------------------------------------------
-- 3. fn_autenticar(email, password) → id del usuario o NULL
--    SECURITY DEFINER: quien la ejecuta NO necesita leer password_hash.
--    search_path fijo para evitar secuestro de objetos (Clase 2).
--    Bloquea la cuenta al 5.º intento fallido consecutivo.
--    El log del servidor recibe sólo usuario_id (nunca el email): la
--    Parte B mostró que el log es un activo sensible. Además, quien la
--    invoque debe usar parámetros enlazados ($1, $2): con SQL literal, la
--    línea STATEMENT que acompaña al RAISE LOG copia la contraseña al log.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_autenticar(p_email TEXT, p_password TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id        BIGINT;
    v_hash      TEXT;
    v_bloqueado BOOLEAN;
BEGIN
    SELECT id, password_hash, bloqueado
      INTO v_id, v_hash, v_bloqueado
    FROM usuario
    WHERE lower(email) = lower(p_email) AND eliminado = FALSE;

    IF v_id IS NULL THEN
        INSERT INTO auditoria_login (email_intentado, exito, motivo)
        VALUES (p_email, FALSE, 'usuario_inexistente');
        RAISE LOG 'fn_autenticar: FALLO motivo=usuario_inexistente email_hash=%', left(md5(lower(p_email)), 12);
        RETURN NULL;
    END IF;

    IF v_bloqueado THEN
        INSERT INTO auditoria_login (email_intentado, usuario_id, exito, motivo)
        VALUES (p_email, v_id, FALSE, 'cuenta_bloqueada');
        RAISE LOG 'fn_autenticar: FALLO motivo=cuenta_bloqueada usuario_id=%', v_id;
        RETURN NULL;
    END IF;

    IF crypt(p_password, v_hash) = v_hash THEN
        UPDATE usuario SET intentos_fallidos = 0 WHERE id = v_id;
        INSERT INTO auditoria_login (email_intentado, usuario_id, exito, motivo)
        VALUES (p_email, v_id, TRUE, 'ok');
        RAISE LOG 'fn_autenticar: EXITO usuario_id=%', v_id;
        RETURN v_id;
    END IF;

    UPDATE usuario
       SET intentos_fallidos = intentos_fallidos + 1,
           bloqueado         = (intentos_fallidos + 1 >= 5)
     WHERE id = v_id;
    INSERT INTO auditoria_login (email_intentado, usuario_id, exito, motivo)
    VALUES (p_email, v_id, FALSE, 'password_incorrecta');
    RAISE LOG 'fn_autenticar: FALLO motivo=password_incorrecta usuario_id=% intentos=%', v_id,
              (SELECT intentos_fallidos FROM usuario WHERE id = v_id);
    RETURN NULL;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. fn_resetear_password(usuario_id, nueva) — uso exclusivo de soporte
--    Exige longitud mínima, desbloquea la cuenta y deja registro.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_resetear_password(p_usuario_id BIGINT, p_nueva TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_nueva IS NULL OR length(p_nueva) < 10 THEN
        RAISE EXCEPTION 'La nueva contraseña debe tener al menos 10 caracteres';
    END IF;

    UPDATE usuario
       SET password_hash     = crypt(p_nueva, gen_salt('bf', 10)),
           intentos_fallidos = 0,
           bloqueado         = FALSE
     WHERE id = p_usuario_id AND eliminado = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Usuario % inexistente o dado de baja', p_usuario_id;
    END IF;

    INSERT INTO auditoria_password (usuario_id) VALUES (p_usuario_id);
    RAISE LOG 'fn_resetear_password: usuario_id=% por rol=%', p_usuario_id, session_user;
END;
$$;

-- Estado resultante
SELECT rol, COUNT(*) FROM usuario GROUP BY rol ORDER BY rol;
SELECT id, nombre, email, telefono, fecha_alta, rol FROM usuario WHERE id IN (1, 42, 50, 801);
