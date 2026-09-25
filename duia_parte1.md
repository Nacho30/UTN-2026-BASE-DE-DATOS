# DUIA — Parte 1 (restricciones de integridad)

Proyecto Food Store — PostgreSQL 16.13. Salidas reales del motor.

### Paso 1 — Spec (escrita antes de pedirle nada a la IA)

Son reglas que hoy dependen de que la aplicación se acuerde de validarlas. Las R1–R7 del TP1 que el esquema ya garantiza (precio y stock ≥ 0, cantidad > 0, email único, FKs NOT NULL) no se repiten.

| Regla | Spec |
|---|---|
| RN1 | No se puede insertar una fila en `pedido_producto` cuyo `id_producto` corresponda a un producto con `producto.activo = FALSE`: un producto dado de baja no se vende. |
| RN2 | Al insertar una fila en `pedido_producto` se descuenta `cantidad` de `producto.stock`. Si `producto.stock` es menor que `cantidad`, la inserción se rechaza con un mensaje que indique el disponible. |
| RN3 | Una fila de `categoria` no puede pasar de `activo = TRUE` a `activo = FALSE` mientras exista algún `producto` con esa `id_categoria` y `activo = TRUE`. |

### Paso 2 — Prompt dado a la IA (modo plan: primero describir, no escribir archivos)

| Campo | Completado |
|---|---|
| Herramienta | Claude (Anthropic), modelo Claude Opus 5.5, usado por chat en lugar de OpenCode (ver nota inicial) |
| Spec o prompt utilizado | El prompt del paso 2, textual, con la spec RN1–RN3 del paso 1. |
| Qué generó | `migraciones/001_restricciones_reglas_negocio.sql` (2 funciones PL/pgSQL y 2 triggers) y `pruebas/001_pruebas_restricciones.sql` (10 casos con SAVEPOINT). |
| Qué se aceptó | Las dos funciones y los dos triggers, tal cual se generaron, incluida la decisión de unir RN1 y RN2 en un solo trigger con `FOR UPDATE`. |
| Qué se modificó o descartó, y por qué | 1) Se agregaron los casos de borde (vender exactamente el stock restante; categoría con un producto activo y otro inactivo). 2) Queda fuera de alcance, y documentado: RN2 cubre el INSERT de líneas; un UPDATE de cantidad o un DELETE de línea no devuelven stock (sería una migración 002). 3) La Parte 2 mostró que este trigger puede generar interbloqueos si dos pedidos cargan los mismos productos en distinto orden: se documenta allí, y la aplicación debe insertar las líneas ordenadas por id_producto. |
| Verificación realizada | Ensayo BEGIN … ROLLBACK con los 10 casos de la tabla del paso 4: 6 válidos aceptados y 4 inválidos rechazados con el mensaje esperado. Después, respaldo con pg_dump, aplicación con COMMIT y control en pg_trigger. |
