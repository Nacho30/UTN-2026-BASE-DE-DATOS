-- =====================================================================
-- Food Store — queries.sql
-- Consultas candidatas para el laboratorio de optimización (Parte 2)
-- =====================================================================

-- Q1: listado de productos vigentes de una categoría, ordenado por precio
SELECT id_producto, nombre, precio, stock
FROM producto
WHERE id_categoria = 3 AND activo = true
ORDER BY precio;

-- Q2: historial de pedidos de un cliente, más recientes primero
SELECT id_pedido, fecha, forma_pago
FROM pedido
WHERE id_cliente = 10450
ORDER BY fecha DESC;

-- Q3: todas las líneas de venta de un producto puntual (para saber
-- cuánto se vendió de ese producto)
SELECT pp.id_pedido, pp.cantidad, pp.precio_unitario
FROM pedido_producto pp
WHERE pp.id_producto = 27341;
