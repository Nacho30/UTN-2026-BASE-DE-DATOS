-- =====================================================================
-- Food Store — TP Unidad 7 · consultas_postgresql.sql
-- Equivalentes en PostgreSQL de las consultas b) y c) de MongoDB, más a)
-- y d) para completar la comparación. Sólo lectura.
-- Requiere sql/01_estado_y_pedidos_prueba.sql aplicado.
--   psql -X -d foodstore -f food-store-tp-u7/consultas_postgresql.sql
-- =====================================================================
SET TIME ZONE 'America/Argentina/Buenos_Aires';

\echo '== a) Todos los pedidos'
SELECT id_pedido, estado
FROM pedido
ORDER BY id_pedido;

-- -----------------------------------------------------------------
-- b) Pedidos en estado ENTREGADO  (Mongo: find({ estado: "ENTREGADO" }))
-- -----------------------------------------------------------------
\echo '== b) Pedidos ENTREGADO'
SELECT id_pedido, estado, fecha
FROM pedido
WHERE estado = 'ENTREGADO'
ORDER BY id_pedido;

SELECT COUNT(*) AS cantidad, string_agg(id_pedido::text, ', ' ORDER BY id_pedido) AS ids
FROM pedido
WHERE estado = 'ENTREGADO';

-- -----------------------------------------------------------------
-- c) Pedidos que contienen el producto 4 "Gaseosa 500 ml"
--    (Mongo: find({ "lineas.id_producto": 4 }))
--    EXISTS y no JOIN directo: como PK(id_pedido, id_producto) impide
--    repetir el producto en un pedido, ambos darían lo mismo hoy, pero
--    EXISTS expresa "contiene" y no duplica pedidos si eso cambiara.
-- -----------------------------------------------------------------
\echo '== c) Pedidos con el producto 4'
SELECT p.id_pedido, p.estado, pp.cantidad, pp.precio_unitario
FROM pedido p
JOIN pedido_producto pp ON pp.id_pedido = p.id_pedido AND pp.id_producto = 4
ORDER BY p.id_pedido;

SELECT COUNT(*) AS cantidad, string_agg(p.id_pedido::text, ', ' ORDER BY p.id_pedido) AS ids
FROM pedido p
WHERE EXISTS (SELECT 1 FROM pedido_producto pp
              WHERE pp.id_pedido = p.id_pedido AND pp.id_producto = 4);

-- -----------------------------------------------------------------
-- d) Total > 16000 (el total no se almacena en PostgreSQL: 3FN)
-- -----------------------------------------------------------------
\echo '== d) Ticket promedio y pedidos con total > 16000'
SELECT ROUND(AVG(total), 2) AS promedio
FROM (SELECT SUM(cantidad * precio_unitario) AS total
      FROM pedido_producto GROUP BY id_pedido) t;

SELECT p.id_pedido, p.estado, SUM(pp.cantidad * pp.precio_unitario) AS total
FROM pedido p
JOIN pedido_producto pp ON pp.id_pedido = p.id_pedido
GROUP BY p.id_pedido, p.estado
HAVING SUM(pp.cantidad * pp.precio_unitario) > 16000
ORDER BY p.id_pedido;
