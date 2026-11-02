PRAGMA foreign_keys = ON;
-- TP U8 · Caso C2, segunda parte (tablet): el cliente acepta el precio nuevo.
-- La solicitud en CONFLICTO no se toca (su estado es final); se actualiza
-- el precio del borrador con el catálogo recién cargado y se encola una
-- solicitud NUEVA (otro UUID).
BEGIN;
UPDATE item_borrador
SET precio_centavos_visto = (SELECT p.precio_centavos FROM producto_cache p WHERE p.id = item_borrador.producto_id)
WHERE id_local = 'b2000000-0000-4000-8000-000000000002';
INSERT INTO cola_sync (solicitud_uuid, id_local)
VALUES ('52000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000002');
COMMIT;

SELECT i.producto_id, i.cantidad, i.precio_centavos_visto, p.precio_centavos AS precio_catalogo
FROM item_borrador i JOIN producto_cache p ON p.id = i.producto_id
WHERE i.id_local = 'b2000000-0000-4000-8000-000000000002';
SELECT solicitud_uuid, estado FROM cola_sync WHERE id_local = 'b2000000-0000-4000-8000-000000000002' ORDER BY creada_en, solicitud_uuid;
