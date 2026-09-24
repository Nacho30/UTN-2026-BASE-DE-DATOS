# Steering: convenciones del esquema Food Store
- Tablas en singular y minúscula (`categoria`, `producto`, `cliente`, `pedido`, `pedido_producto`).
- PK `id_<tabla> BIGINT GENERATED ALWAYS AS IDENTITY`; FK con el mismo nombre que la PK referenciada.
- Baja lógica (R7): columna `activo BOOLEAN NOT NULL DEFAULT TRUE`; FKs con `ON DELETE RESTRICT` como red de seguridad.
- ENUM del proyecto: `forma_pago` = EFECTIVO | TARJETA | TRANSFERENCIA.
- Restricciones con nombre explícito `chk_<tabla>_<regla>`; triggers `trg_<tabla>_<regla>` con función `fn_<tabla>_<regla>`.
- Montos en `NUMERIC(10,2)`; fechas en `TIMESTAMPTZ`. El subtotal de línea no se almacena (3FN).
- `pedido_producto.precio_unitario` es histórico (R4): no se recalcula al cambiar `producto.precio`.
