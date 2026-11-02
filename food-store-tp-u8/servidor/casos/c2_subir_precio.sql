-- TP U8 · Caso C2 (servidor): sube el precio de la Hamburguesa clásica
-- DESPUÉS de que la tablet armó el borrador. Sólo en copia_trabajo.
\set ON_ERROR_STOP on
DO $$ BEGIN
    IF current_database() <> 'copia_trabajo' THEN
        RAISE EXCEPTION 'Sólo sobre copia_trabajo (base actual: %)', current_database();
    END IF;
END $$;
BEGIN;
UPDATE producto SET precio = 9200.00 WHERE id_producto = 1;
COMMIT;
SELECT id_producto, nombre, precio FROM producto WHERE id_producto = 1;
