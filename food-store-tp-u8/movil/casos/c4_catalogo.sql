PRAGMA foreign_keys = ON;
-- TP U8 · Caso C4, después de recargar el catálogo (tablet):
-- el Agua mineral ya no aparece para vender, pero su fila sigue (lápida)
-- y el borrador que la usa sigue siendo válido para la FK.
.print '-- Catálogo disponible (la consulta de C1):'
SELECT id, nombre, printf('%.2f', precio_centavos / 100.0) AS precio, stock_visto
FROM producto_cache WHERE disponible = 1 AND eliminado = 0 ORDER BY nombre;
.print '-- La fila del producto 5 sigue en producto_cache:'
SELECT id, nombre, disponible, eliminado, copiado_en FROM producto_cache WHERE id = 5;
.print '-- El borrador que lo usa sigue intacto:'
SELECT id_local, producto_id, cantidad FROM item_borrador WHERE producto_id = 5;
.print '-- Y la tablet ya no puede agregarlo a un borrador nuevo (0 filas insertadas):'
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b4000000-0000-4000-8000-0000000000ff', 'vendedor_feria_01', 'EFECTIVO');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b4000000-0000-4000-8000-0000000000ff', id, 1, precio_centavos
FROM producto_cache WHERE id = 5 AND disponible = 1 AND eliminado = 0;
SELECT changes() AS items_insertados;
ROLLBACK;
