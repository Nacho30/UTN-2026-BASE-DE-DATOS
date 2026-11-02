PRAGMA foreign_keys = ON;
-- TP U8 · Caso C5 (tablet): borrador sin cambios en el servidor.
-- Correr desde movil/:  sqlite3 foodstore_movil.db < casos/c5_borrador.sql
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b5000000-0000-4000-8000-000000000005', 'vendedor_feria_01', 'EFECTIVO');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b5000000-0000-4000-8000-000000000005', id, 1, precio_centavos FROM producto_cache
WHERE id = 3 AND disponible = 1 AND eliminado = 0;   -- Pizza muzzarella x1
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b5000000-0000-4000-8000-000000000005', id, 1, precio_centavos FROM producto_cache
WHERE id = 6 AND disponible = 1 AND eliminado = 0;   -- Flan casero x1
INSERT INTO cola_sync (solicitud_uuid, id_local)
VALUES ('55000000-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000005');
COMMIT;

SELECT i.producto_id, p.nombre, i.cantidad, i.precio_centavos_visto, p.stock_visto, c.estado
FROM item_borrador i
JOIN producto_cache p ON p.id = i.producto_id
JOIN cola_sync c ON c.id_local = i.id_local
WHERE i.id_local = 'b5000000-0000-4000-8000-000000000005';
