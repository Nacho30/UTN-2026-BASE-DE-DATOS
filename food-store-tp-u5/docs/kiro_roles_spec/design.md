# Design Document — Roles y permisos de Food Store

## Overview

El modelo tiene tres capas:

1. **Dueño** (`foodstore_owner`, NOLOGIN): posee tablas, secuencias, vistas y funciones. Nadie se conecta como dueño. Las funciones `SECURITY DEFINER` corren con sus permisos, y como no es superusuario, un error en una función no expone el servidor entero.
2. **Roles de grupo** (NOLOGIN): concentran los privilegios por función de negocio.
3. **Roles de login**: no tienen privilegios propios y heredan de los grupos. Cambiar un permiso se hace en un solo lugar.

```
foodstore_owner (NOLOGIN, dueño)
│
├── rol_app_lectura ─┐
├── rol_app_escritura┴── app_web (LOGIN)
├── rol_soporte ──────── soporte_mesa (LOGIN)
├── rol_reportes ─────── reportes_bi (LOGIN)
├── rol_auditor ──────── auditor_seg (LOGIN)
└── (sin grupo) ──────── admin_datos (LOGIN, privilegios directos)
```

## Matriz de privilegios

| Objeto | app_lectura | app_escritura | soporte | reportes | auditor | admin_datos |
|---|---|---|---|---|---|---|
| categoria, producto | S | – | – | S | – | SIUD |
| pedido | S | I, U(estado, eliminado) | S | S | – | SIUD |
| detalle_pedido | S | I, U(eliminado) | S | S | – | SIUD |
| usuario | S(id, nombre, email, rol, telefono, direccion) | – | S(8 col.), U(bloqueado) | – | – | SIUD |
| usuario_anon | – | – | – | S | – | SIUD |
| venta_diaria_categoria | – | – | – | S | – | SIUD |
| auditoria_login / _password | – | – | – | – | S | **S** |
| secuencias pedido / detalle | – | USAGE | – | – | – | USAGE, SELECT, UPDATE |
| fn_autenticar | – | EXECUTE | – | – | – | – |
| fn_resetear_password | – | – | EXECUTE | – | – | – |

S = SELECT, I = INSERT, U = UPDATE, D = DELETE.

## Decisiones de diseño

- **Permiso a nivel de columna sobre `usuario`.** `rol_app_lectura` y `rol_soporte` reciben `SELECT` sólo sobre columnas enumeradas. Una columna que se agregue en el futuro, por ejemplo un DNI, no queda expuesta por accidente.
- **Credenciales sólo por función.** Ningún rol de grupo puede leer `password_hash`. `fn_autenticar` y `fn_resetear_password` son `SECURITY DEFINER` con `SET search_path = public, pg_temp`.
- **`REVOKE EXECUTE … FROM PUBLIC`.** PostgreSQL otorga `EXECUTE` a `PUBLIC` sobre toda función nueva. Si no se revoca, cualquier rol que se conecte podría invocar `fn_resetear_password`.
- **Funciones de pgcrypto.** Al revocar `EXECUTE` a `PUBLIC`, `crypt` y `gen_salt` dejan de estar disponibles para el dueño. Se le otorgan explícitamente.
- **Disparadores de la Unidad 4.** Las funciones `fn_vdc_*` mantienen `venta_diaria_categoria` cuando la app inserta detalles. Pasan a ser `SECURITY DEFINER`, así `app_web` no necesita permisos sobre la tabla redundante.
- **Auditoría inmutable para el administrador.** `admin_datos` sólo lee `auditoria_*`. Las filas las escriben las funciones, que corren como el dueño.
- **Default privileges.** `ALTER DEFAULT PRIVILEGES FOR ROLE foodstore_owner` da DML a `admin_datos` sobre toda tabla futura y nada a `PUBLIC`. Los roles de grupo **no** reciben acceso automático: cada tabla nueva requiere un `GRANT` explícito y justificado. Si la tabla futura es de auditoría, el script que la crea debe revocarle el DML a `admin_datos`.
- **Contraseñas fuera del repo.** `roles.sql` las lee de variables de entorno con `\getenv`. El archivo `.env.example` documenta las variables.
- **Escalamiento.** Ningún rol recibe `WITH ADMIN OPTION`, `CREATEROLE` ni `WITH GRANT OPTION`, así que nadie puede delegar ni otorgarse privilegios.

## Testing Strategy

- `\du` y `information_schema.role_table_grants` / `column_privileges` comparados contra la matriz → `evidencia/verificacion_permisos.txt`.
- Pruebas positivas y negativas por rol con `SET ROLE`, incluidas en `roles.sql`.
- El simulacro de la Parte C verifica en particular el criterio 6.5.
