-- =====================================================================
-- Food Store — TP Unidad 7 · 01_estado_y_pedidos_prueba.sql
-- Prepara el subconjunto "pedidos y detalle" para la migración a MongoDB.
--
-- Requiere, en este orden: schema.sql, migraciones/001_*.sql,
-- programables/funciones_procedimientos.sql y datos_iniciales.sql.
--   psql -X -v ON_ERROR_STOP=1 -d foodstore -f food-store-tp-u7/sql/01_estado_y_pedidos_prueba.sql
--
-- 1) El esquema real de Food Store NO tiene estado de pedido (pedido sólo
--    guarda fecha, forma_pago e id_cliente). La consigna pide migrar y
--    filtrar por estado, así que se agrega acá, sólo para esta unidad,
--    siguiendo las convenciones del proyecto (ENUM + NOT NULL + DEFAULT).
-- 2) datos_iniciales.sql trae 4 pedidos y la consigna pide al menos 5:
--    se agregan 2 pedidos DE PRUEBA (id 5 y 6), coherentes con las reglas
--    del dominio: pasan por trg_pedido_producto_valida_y_descuenta_stock
--    (RN1 producto activo, RN2 stock suficiente) y usan el precio de lista
--    vigente como precio_unitario histórico (R4).
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TYPE estado_pedido AS ENUM ('PENDIENTE', 'EN_PREPARACION', 'ENTREGADO', 'CANCELADO');

ALTER TABLE pedido
    ADD COLUMN estado estado_pedido NOT NULL DEFAULT 'PENDIENTE';

COMMENT ON COLUMN pedido.estado IS
    'TP U7: estado del pedido, agregado para la comparación con MongoDB';

-- Estados de los 4 pedidos de datos_iniciales.sql (ficticios, del 20 al 23/09)
UPDATE pedido SET estado = 'ENTREGADO'      WHERE id_pedido IN (1, 2, 3);
UPDATE pedido SET estado = 'EN_PREPARACION' WHERE id_pedido = 4;

-- Pedidos de prueba (procedencia: TP U7, no estaban en datos_iniciales.sql)
INSERT INTO pedido (fecha, forma_pago, id_cliente, estado) VALUES
 ('2026-09-24 20:30-03', 'EFECTIVO', 2, 'PENDIENTE'),  -- 5
 ('2026-09-25 13:45-03', 'TARJETA',  3, 'ENTREGADO');  -- 6

INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
SELECT v.id_pedido, v.id_producto, v.cantidad, pr.precio
FROM (VALUES (5, 2, 2), (5, 4, 2),           -- Hamburguesa doble x2, Gaseosa x2
             (6, 3, 1), (6, 5, 1), (6, 6, 1) -- Pizza muzzarella, Agua, Flan
     ) AS v(id_pedido, id_producto, cantidad)
JOIN producto pr ON pr.id_producto = v.id_producto;

COMMIT;

-- Estado resultante
SELECT p.id_pedido, p.fecha, p.estado, p.forma_pago, p.id_cliente,
       SUM(pp.cantidad * pp.precio_unitario) AS total
FROM pedido p
JOIN pedido_producto pp ON pp.id_pedido = p.id_pedido
GROUP BY p.id_pedido
ORDER BY p.id_pedido;
