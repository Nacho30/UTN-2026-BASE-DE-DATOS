-- TP U8 · Caso C4 (servidor): baja lógica del Agua mineral (R7: no se borra).
\set ON_ERROR_STOP on
DO $$ BEGIN
    IF current_database() <> 'copia_trabajo' THEN
        RAISE EXCEPTION 'Sólo sobre copia_trabajo (base actual: %)', current_database();
    END IF;
END $$;
BEGIN;
UPDATE producto SET activo = FALSE WHERE id_producto = 5;
COMMIT;
SELECT id_producto, nombre, activo FROM producto WHERE id_producto = 5;
