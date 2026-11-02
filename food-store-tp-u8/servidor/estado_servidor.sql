-- TP U8 · servidor/estado_servidor.sql — foto del servidor (sólo lectura).
-- Se corre al principio y al final de correr_todo.sh para compararlas.
SELECT (SELECT count(*) FROM pedido)          AS pedidos,
       (SELECT count(*) FROM pedido_producto) AS lineas,
       (SELECT sum(stock) FROM producto)      AS stock_total;
SELECT id_producto, nombre, precio, stock, activo FROM producto ORDER BY id_producto;
