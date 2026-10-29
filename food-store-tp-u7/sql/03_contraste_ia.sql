-- =====================================================================
-- Food Store — TP Unidad 7 · 03_contraste_ia.sql (sólo lectura)
-- Evidencia de laboratorio para contrastar afirmaciones de la IA.
-- =====================================================================
SET TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '== Afirmación 1: un pedido completo en PostgreSQL requiere unir 4 tablas'
EXPLAIN (COSTS OFF)
SELECT p.id_pedido, p.fecha, p.estado, c.nombre, c.apellido,
       pr.nombre AS producto, pp.cantidad, pp.precio_unitario
FROM pedido p
JOIN cliente c          ON c.id_cliente  = p.id_cliente
JOIN pedido_producto pp ON pp.id_pedido  = p.id_pedido
JOIN producto pr        ON pr.id_producto = pp.id_producto
WHERE p.id_pedido = 1;

\echo '== Precio histórico (R4) vs precio de lista actual'
SELECT pp.id_pedido, pr.nombre, pp.precio_unitario AS precio_historico,
       pr.precio AS precio_lista_actual,
       pp.precio_unitario <> pr.precio AS difiere
FROM pedido_producto pp
JOIN producto pr ON pr.id_producto = pp.id_producto
ORDER BY pp.id_pedido, pp.id_producto;

\echo '== Si se migrara con producto.precio en vez de precio_unitario'
SELECT p.id_pedido,
       SUM(pp.cantidad * pp.precio_unitario) AS total_correcto,
       SUM(pp.cantidad * pr.precio)          AS total_con_precio_actual
FROM pedido p
JOIN pedido_producto pp ON pp.id_pedido = p.id_pedido
JOIN producto pr        ON pr.id_producto = pp.id_producto
GROUP BY p.id_pedido
HAVING SUM(pp.cantidad * pp.precio_unitario) <> SUM(pp.cantidad * pr.precio);

\echo '== Fechas: día local (-03) vs día UTC (como queda en MongoDB)'
SELECT id_pedido, fecha::date AS dia_local,
       (fecha AT TIME ZONE 'UTC')::date AS dia_utc
FROM pedido
WHERE fecha::date <> (fecha AT TIME ZONE 'UTC')::date
ORDER BY id_pedido;

\echo '== RN2 sigue fuera del documento: stock actual tras los pedidos de prueba'
SELECT id_producto, nombre, stock FROM producto ORDER BY id_producto;
