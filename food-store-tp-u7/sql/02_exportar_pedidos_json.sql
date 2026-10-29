-- =====================================================================
-- Food Store — TP Unidad 7 · 02_exportar_pedidos_json.sql
-- Arma, desde PostgreSQL, un documento JSON por pedido con la misma
-- forma que la colección "pedidos" de MongoDB. Sólo lectura.
--   psql -X -At -d foodstore -f food-store-tp-u7/sql/02_exportar_pedidos_json.sql > docs/pedidos_export.jsonl
-- scripts/generar_insertmany.py convierte esa salida en el insertMany()
-- de consultas_mongodb.js (montos como Decimal128, fechas como Date).
-- =====================================================================
SELECT json_build_object(
         '_id',        p.id_pedido,                         -- id de origen conservado
         'fecha',      to_char(p.fecha AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
         'estado',     p.estado,
         'forma_pago', p.forma_pago,
         'cliente',    json_build_object('id_cliente', c.id_cliente,
                                         'nombre',     c.nombre,
                                         'apellido',   c.apellido),
         'lineas',     (SELECT json_agg(json_build_object(
                                   'id_producto',     pp.id_producto,
                                   'nombre',          pr.nombre,
                                   'cantidad',        pp.cantidad,
                                   'precio_unitario', pp.precio_unitario::text)
                                 ORDER BY pp.id_producto)
                        FROM pedido_producto pp
                        JOIN producto pr ON pr.id_producto = pp.id_producto
                        WHERE pp.id_pedido = p.id_pedido),
         'total',      (SELECT SUM(pp.cantidad * pp.precio_unitario)::text
                        FROM pedido_producto pp
                        WHERE pp.id_pedido = p.id_pedido)
       )
FROM pedido p
JOIN cliente c ON c.id_cliente = p.id_cliente
ORDER BY p.id_pedido;
