PRAGMA foreign_keys = ON;
-- TP U8 · Caso C2 (tablet): borrador con 2 Hamburguesas clásicas; después el servidor sube el precio.
-- Correr desde movil/:  sqlite3 foodstore_movil.db < casos/c2_borrador.sql
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b2000000-0000-4000-8000-000000000002', 'vendedor_feria_01', 'TARJETA');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b2000000-0000-4000-8000-000000000002', id, 2, precio_centavos FROM producto_cache
WHERE id = 1 AND disponible = 1 AND eliminado = 0;   -- Hamburguesa clásica x2 al precio que ve la tablet
INSERT INTO cola_sync (solicitud_uuid, id_local)
VALUES ('52000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000002');
COMMIT;

SELECT i.producto_id, p.nombre, i.cantidad, i.precio_centavos_visto, p.stock_visto, c.estado
FROM item_borrador i
JOIN producto_cache p ON p.id = i.producto_id
JOIN cola_sync c ON c.id_local = i.id_local
WHERE i.id_local = 'b2000000-0000-4000-8000-000000000002';
