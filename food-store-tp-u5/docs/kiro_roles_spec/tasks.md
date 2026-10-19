# Implementation Plan — Roles y permisos

- [x] 1. Crear `foodstore_owner` y transferirle la propiedad de tablas, secuencias, vistas y funciones
- [x] 2. Revocar a `PUBLIC` el `CONNECT` sobre la base, el `CREATE` sobre el esquema y el `EXECUTE` sobre funciones
- [x] 3. Crear los roles de grupo y otorgar privilegios según la matriz del design (Req. 1–5)
  - [x] 3.1 Permisos de columna sobre `usuario` para `rol_app_lectura` y `rol_soporte`
- [x] 4. Crear los roles de login con contraseñas leídas del entorno (Req. 6, 7.4)
- [x] 5. Convertir en `SECURITY DEFINER` los disparadores de la Unidad 4 y otorgar pgcrypto al dueño
- [x] 6. `ALTER DEFAULT PRIVILEGES` para tablas, secuencias y funciones futuras (Req. 7.3)
- [x] 7. Verificar con `\du`, `role_table_grants` y `column_privileges` → `docs/verificacion_permisos.txt`
- [x] 8. Pruebas positivas y negativas por rol (28)
- [x] 9. Aplicar las correcciones verificadas de la auditoría de IA (ver BITACORA.md, A-1 a A-4)
