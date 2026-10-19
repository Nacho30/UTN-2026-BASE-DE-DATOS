# Requirements Document — Roles y permisos de Food Store

## Introduction

Food Store necesita un esquema de identidades en PostgreSQL que aplique el principio de mínimo privilegio. Cada rol habilita sólo las operaciones que su función requiere. Las credenciales se resuelven dentro de funciones `SECURITY DEFINER`, y los registros de auditoría no pueden ser alterados por quienes son auditados.

**Actores:** la aplicación web (clientes y repartidores), la mesa de soporte, el área de reportes/BI, el administrador de datos y un auditor de seguridad.

## Requirements

### Requirement 1 — Lectura de la aplicación (`rol_app_lectura`)

**User Story:** Como aplicación web, quiero leer el catálogo, los pedidos y el perfil público de los usuarios, para mostrarlos en pantalla sin poder ver credenciales.

**Justificación:** habilita sólo `SELECT` sobre lo que la app muestra, porque la app nunca necesita leer `password_hash` ni el estado de bloqueo.

#### Acceptance Criteria
1. THE rol SHALL tener `SELECT` sobre `categoria`, `producto`, `pedido` y `detalle_pedido`.
2. THE rol SHALL tener `SELECT` sobre `usuario` únicamente en las columnas `id, nombre, email, rol, telefono, direccion`.
3. WHEN el rol intente leer `usuario.password_hash`, `intentos_fallidos` o `bloqueado` THE motor SHALL rechazar la consulta con `permission denied`.
4. THE rol SHALL NOT tener ningún privilegio de escritura.

### Requirement 2 — Escritura de la aplicación (`rol_app_escritura`)

**User Story:** Como aplicación web, quiero registrar pedidos y darlos de baja lógicamente, para operar el flujo de compra.

**Justificación:** habilita `INSERT` de pedidos y detalles y `UPDATE` sólo de las columnas de estado, porque la app no debe borrar físicamente ni alterar montos ya registrados.

#### Acceptance Criteria
1. THE rol SHALL tener `INSERT` sobre `pedido` y `detalle_pedido`, y `USAGE` sobre sus secuencias.
2. THE rol SHALL tener `UPDATE` sólo sobre `pedido(estado, eliminado)` y `detalle_pedido(eliminado)`.
3. THE rol SHALL tener `EXECUTE` sobre `fn_autenticar`.
4. THE rol SHALL NOT tener `DELETE`, `TRUNCATE` ni acceso de escritura a `usuario`.

### Requirement 3 — Soporte (`rol_soporte`)

**User Story:** Como operador de soporte, quiero consultar datos de contacto y pedidos, bloquear una cuenta comprometida y restablecer contraseñas, para atender reclamos.

**Justificación:** habilita el reseteo sólo a través de `fn_resetear_password`, porque así el operador nunca ve ni escribe un hash y cada reseteo queda auditado.

#### Acceptance Criteria
1. THE rol SHALL tener `SELECT` sobre `usuario(id, nombre, email, rol, telefono, fecha_alta, bloqueado, intentos_fallidos)`.
2. THE rol SHALL tener `UPDATE` sólo sobre `usuario(bloqueado)`.
3. THE rol SHALL tener `SELECT` sobre `pedido` y `detalle_pedido`.
4. THE rol SHALL tener `EXECUTE` sobre `fn_resetear_password` y no sobre ninguna otra función de credenciales.

### Requirement 4 — Reportes (`rol_reportes`)

**User Story:** Como analista de BI, quiero consultar ventas y estadísticas de usuarios, para armar tableros.

**Justificación:** habilita lectura de datos de ventas y de `usuario_anon`, porque los tableros trabajan con agregados y no necesitan identificar a ninguna persona.

#### Acceptance Criteria
1. THE rol SHALL tener `SELECT` sobre `categoria`, `producto`, `pedido`, `detalle_pedido`, `venta_diaria_categoria` y `usuario_anon`.
2. THE rol SHALL NOT tener ningún privilegio sobre `usuario`.

### Requirement 5 — Auditor (`rol_auditor`, rol adicional del equipo)

**User Story:** Como auditor de seguridad, quiero leer los registros de inicio de sesión y de reseteo de contraseñas, para investigar incidentes.

**Justificación:** separa funciones, porque soporte ejecuta los reseteos y no debe ser quien lea o controle el registro de sus propias acciones.

#### Acceptance Criteria
1. THE rol SHALL tener `SELECT` sobre `auditoria_login` y `auditoria_password`.
2. THE rol SHALL NOT tener acceso a datos de negocio ni a `usuario`.

### Requirement 6 — Roles de login

**User Story:** Como DBA, quiero que las personas y aplicaciones se conecten con roles de login sin privilegios propios, que heredan de los roles de grupo, para administrar permisos en un solo lugar.

#### Acceptance Criteria
1. THE `app_web` SHALL ser miembro de `rol_app_lectura` y `rol_app_escritura`, con límite de conexiones.
2. THE `admin_datos` SHALL tener `SELECT, INSERT, UPDATE, DELETE` sobre las tablas de negocio y sólo `SELECT` sobre las tablas de auditoría. Justificación: administra los datos, pero no puede borrar el rastro de lo que hizo.
3. THE `admin_datos` SHALL NOT ser superusuario, ni tener `CREATEROLE` o `CREATEDB`, ni ser dueño de objetos.
4. THE roles de persona `soporte_mesa`, `reportes_bi` y `auditor_seg` SHALL heredar de su rol de grupo.
5. IF un rol de bajo privilegio intenta otorgarse membresía en `admin_datos` THEN THE motor SHALL rechazarlo.

### Requirement 7 — Políticas transversales

1. THE `PUBLIC` SHALL NOT tener `CONNECT` sobre la base, `CREATE` sobre el esquema ni `EXECUTE` sobre funciones.
2. THE objetos SHALL pertenecer a `foodstore_owner`, un rol `NOLOGIN` que no es superusuario.
3. WHEN se cree una tabla futura THE motor SHALL aplicar la misma política por defecto (`ALTER DEFAULT PRIVILEGES`): `admin_datos` recibe DML y `PUBLIC` no recibe nada.
4. THE contraseñas de los roles de login SHALL NOT quedar escritas en el repositorio.
