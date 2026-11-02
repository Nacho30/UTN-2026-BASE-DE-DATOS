-- TP U8 · revision/sin_pragma.sql — sobre una COPIA de la base de la tablet.
-- Mismo INSERT que el caso C7, pero SIN "PRAGMA foreign_keys = ON;".
SELECT foreign_keys AS fk_activas_en_esta_conexion FROM pragma_foreign_keys;
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('b1000000-0000-4000-8000-000000000001', 999, 1, 100000);
SELECT id_local, producto_id FROM item_borrador WHERE producto_id = 999;
.print '-- con el PRAGMA, el mismo dato aparece como violación:'
PRAGMA foreign_keys = ON;
SELECT * FROM pragma_foreign_key_check('item_borrador');
