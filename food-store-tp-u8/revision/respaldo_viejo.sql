PRAGMA foreign_keys = ON;
-- TP U8 · revision/respaldo_viejo.sql — sobre una COPIA de la base de la tablet.
-- Antes de correrlo, en revision/: servidor_snapshot.csv = instantánea SIN el
-- producto 3 (como la daría un PostgreSQL restaurado de un respaldo anterior
-- al alta de ese producto) y se corrió ../movil/cargar_snapshot.sql.
.print '== R1: el producto 3, que el servidor ya no informa, queda fuera de la venta (no se borra)'
SELECT id, nombre, disponible, eliminado, copiado_en FROM producto_cache WHERE id = 3;
.print '== R1: el catálogo disponible ya no lo muestra'
SELECT id, nombre FROM producto_cache WHERE disponible = 1 AND eliminado = 0 ORDER BY id;
.print '== R1: un borrador nuevo con ese producto sale rojo'
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago) VALUES ('be000000-0000-4000-8000-000000000001', 'vendedor_feria_01', 'EFECTIVO');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto) VALUES ('be000000-0000-4000-8000-000000000001', 3, 1, 1200000);
INSERT INTO cola_sync (solicitud_uuid, id_local) VALUES ('5e000000-0000-4000-8000-000000000001', 'be000000-0000-4000-8000-000000000001');
COMMIT;
