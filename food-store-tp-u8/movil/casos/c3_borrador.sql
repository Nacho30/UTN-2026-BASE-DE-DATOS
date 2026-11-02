PRAGMA foreign_keys = ON;
-- TP U8 · Caso C3 (tablet): borrador por 5 Hamburguesas dobles; en el servidor quedan menos.
-- Correr desde movil/:  sqlite3 foodstore_movil.db < casos/c3_borrador.sql
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b3000000-0000-4000-8000-000000000003', 'vendedor_feria_01', 'EFECTIVO');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b3000000-0000-4000-8000-000000000003', id, 5, precio_centavos FROM producto_cache
WHERE id = 2 AND disponible = 1 AND eliminado = 0;   -- Hamburguesa doble x5 (la tablet ve 9 en stock)
INSERT INTO cola_sync (solicitud_uuid, id_local)
VALUES ('53000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000003');
COMMIT;

SELECT i.producto_id, p.nombre, i.cantidad, i.precio_centavos_visto, p.stock_visto, c.estado
FROM item_borrador i
JOIN producto_cache p ON p.id = i.producto_id
JOIN cola_sync c ON c.id_local = i.id_local
WHERE i.id_local = 'b3000000-0000-4000-8000-000000000003';
