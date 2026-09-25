-- =====================================================================
-- Food Store — indices.sql
-- Unidad 3 / Semana 1 — Parte A: plan de indexado asistido por IA
--
-- Índices heredados de la Semana 3 (ya existen en schema, no se repiten
-- acá): idx_pedido_cliente, idx_pedido_fecha, idx_producto_categoria,
-- idx_producto_stock_bajo, idx_pedido_producto_producto.
--
-- Nomenclatura: este esquema (Food Store, TP1) usa cliente/activo en vez
-- de usuario/eliminado, y pedido_producto en vez de detalle_pedido (ver
-- nota de nomenclatura al final de schema.sql). Se mantiene por
-- continuidad del proyecto.
-- =====================================================================

-- -----------------------------------------------------------------
-- Índice 1 — búsqueda de cliente por apellido (atención al cliente)
-- Consulta: SELECT id_cliente, nombre, apellido, email FROM cliente
--           WHERE apellido = :apellido AND activo = true;
-- Antes: Seq Scan on cliente (20.003 filas), Execution Time 2.334 ms.
-- Índice parcial: la búsqueda de atención al cliente siempre filtra por
-- clientes vigentes, así que no tiene sentido indexar los inactivos.
-- -----------------------------------------------------------------
CREATE INDEX idx_cliente_apellido ON cliente (apellido) WHERE activo = true;

-- -----------------------------------------------------------------
-- Índice 2 — búsqueda de producto por nombre exacto (catálogo/checkout)
-- Consulta: SELECT id_producto, nombre, precio FROM producto
--           WHERE nombre = :nombre;
-- Antes: Seq Scan on producto (50.005 filas), Execution Time 3.573 ms.
-- Índice parcial sobre productos vigentes (activo = true): el catálogo
-- de cara al cliente nunca busca productos dados de baja.
-- -----------------------------------------------------------------
CREATE INDEX idx_producto_nombre_vig ON producto (nombre) WHERE activo = true;

-- -----------------------------------------------------------------
-- Índice 3 — líneas de pedido de productos premium (reporte de ventas
-- de alta gama, precio_unitario > 4500)
-- Consulta: SELECT id_pedido, id_producto, cantidad, precio_unitario
--           FROM pedido_producto WHERE precio_unitario > 4500;
-- Antes: Seq Scan on pedido_producto (499.403 filas), Execution Time
-- 48.405 ms, ~11% de selectividad.
-- Índice simple (no parcial): el umbral de "premium" no es un valor
-- fijo conocido de antemano por el motor, así que un índice simple por
-- rango es lo que permite Bitmap Index Scan para cualquier umbral.
-- -----------------------------------------------------------------
CREATE INDEX idx_pedido_producto_precio ON pedido_producto (precio_unitario);

-- -----------------------------------------------------------------
-- Propuesta DESCARTADA por sobreindexación (ver duia.md e
-- informe_mediciones.md para el detalle completo de la decisión):
--
-- CREATE INDEX idx_pedido_forma_pago ON pedido (forma_pago);
--
-- Se descartó: forma_pago es un ENUM de 3 valores sobre 200.002 filas
-- (~66.667 filas por valor en promedio) sin ninguna condición parcial
-- que lo reduzca. Un índice sobre una columna de esa cardinalidad no le
-- gana a un Seq Scan (el motor igual va a preferir escanear la tabla
-- entera o hacer Bitmap Heap Scan con un Recheck que termina leyendo
-- casi todos los bloques), y sí tiene el costo de mantenimiento en cada
-- INSERT/UPDATE de pedido. Medido y confirmado: ver informe_mediciones.md.
-- -----------------------------------------------------------------
