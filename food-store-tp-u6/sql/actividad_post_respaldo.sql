-- =====================================================================
-- actividad_post_respaldo.sql — SÓLO LABORATORIO (TP Unidad 6)
-- Simula la operación normal de Food Store DESPUÉS del último respaldo,
-- usando los procedimientos del proyecto (programables/):
--   * 40 pedidos nuevos con sp_registrar_pedido   → se pierden al restaurar (RPO)
--   * 3.000 pedidos viejos cancelados con sp_cancelar_pedido → DELETE en
--     pedido/pedido_producto y UPDATE de stock: genera tuplas muertas
--   * aumento del 5 % en 60 productos               → UPDATE en producto
-- =====================================================================
\set ON_ERROR_STOP on
DO $$ BEGIN
    IF current_database() <> 'foodstore' THEN
        RAISE EXCEPTION 'actividad_post_respaldo.sql sólo se ejecuta sobre foodstore';
    END IF;
END $$;

-- 40 pedidos nuevos (cada CALL es una transacción, como en la app)
SELECT format('CALL sp_registrar_pedido(%s, %L, %L)',
              c.id_cliente,
              (ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA'])[1 + g % 3],
              jsonb_build_array(
                  jsonb_build_object('id_producto', p1.id_producto, 'cantidad', 1 + g % 2),
                  jsonb_build_object('id_producto', p2.id_producto, 'cantidad', 1)))
FROM generate_series(1, 40) g
JOIN LATERAL (SELECT id_cliente FROM cliente ORDER BY id_cliente OFFSET (g * 97) % 5000 LIMIT 1) c ON TRUE
JOIN LATERAL (SELECT id_producto FROM producto WHERE activo AND stock > 10
              ORDER BY id_producto OFFSET (g * 7) % 250 LIMIT 1) p1 ON TRUE
JOIN LATERAL (SELECT id_producto FROM producto WHERE activo AND stock > 10
              ORDER BY id_producto OFFSET (g * 7 + 3) % 250 LIMIT 1) p2 ON TRUE
\gexec

-- 3.000 cancelaciones de pedidos de hace más de 300 días
SELECT format('CALL sp_cancelar_pedido(%s)', id_pedido)
FROM pedido
WHERE fecha < now() - interval '300 days'
ORDER BY id_pedido
LIMIT 3000
\gexec

-- Aumento de precios (no afecta precio_unitario histórico de las líneas, R4)
UPDATE producto SET precio = round(precio * 1.05, 2)
WHERE nombre LIKE 'Producto %' AND id_producto % 5 = 0;

SELECT 'pedido' AS tabla, count(*) AS filas, max(id_pedido) AS max_id, max(fecha) AS ultimo FROM pedido
UNION ALL SELECT 'pedido_producto', count(*), NULL, NULL FROM pedido_producto;
