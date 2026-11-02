PRAGMA foreign_keys = ON;
-- TP U8 · Caso C4 (tablet): borrador con un producto que después se da de baja (Agua mineral).
-- Correr desde movil/:  sqlite3 foodstore_movil.db < casos/c4_borrador.sql
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b4000000-0000-4000-8000-000000000004', 'vendedor_feria_01', 'TRANSFERENCIA');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b4000000-0000-4000-8000-000000000004', id, 2, precio_centavos FROM producto_cache
WHERE id = 5 AND disponible = 1 AND eliminado = 0;   -- Agua mineral x2
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b4000000-0000-4000-8000-000000000004', id, 1, precio_centavos FROM producto_cache
WHERE id = 4 AND disponible = 1 AND eliminado = 0;   -- Gaseosa 500 ml x1
INSERT INTO cola_sync (solicitud_uuid, id_local)
VALUES ('54000000-0000-4000-8000-000000000001', 'b4000000-0000-4000-8000-000000000004');
COMMIT;

SELECT i.producto_id, p.nombre, i.cantidad, i.precio_centavos_visto, p.stock_visto, c.estado
FROM item_borrador i
JOIN producto_cache p ON p.id = i.producto_id
JOIN cola_sync c ON c.id_local = i.id_local
WHERE i.id_local = 'b4000000-0000-4000-8000-000000000004';
