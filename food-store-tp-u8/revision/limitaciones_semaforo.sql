PRAGMA foreign_keys = ON;
-- TP U8 · revision/limitaciones_semaforo.sql — corre sobre una COPIA de la base
-- de la tablet (revision/copia_movil.db), nunca sobre foodstore_movil.db.
.print '== L1: dos borradores de 2 flanes cada uno; en la instantánea quedan 3'
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago) VALUES
 ('bd000000-0000-4000-8000-000000000001', 'vendedor_feria_01', 'EFECTIVO'),
 ('bd000000-0000-4000-8000-000000000002', 'vendedor_feria_02', 'EFECTIVO');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT b.id_local, p.id, 2, p.precio_centavos
FROM producto_cache p, (SELECT 'bd000000-0000-4000-8000-000000000001' AS id_local
                        UNION ALL SELECT 'bd000000-0000-4000-8000-000000000002') b
WHERE p.id = 6;
INSERT INTO cola_sync (solicitud_uuid, id_local) VALUES
 ('5d000000-0000-4000-8000-000000000001', 'bd000000-0000-4000-8000-000000000001'),
 ('5d000000-0000-4000-8000-000000000002', 'bd000000-0000-4000-8000-000000000002');
COMMIT;
SELECT stock AS stock_flan_en_la_instantanea FROM snapshot_servidor WHERE id = 6;
