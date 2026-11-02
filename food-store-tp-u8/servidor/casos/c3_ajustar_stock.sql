-- TP U8 · Caso C3 (servidor): mientras el food truck está sin señal, el
-- local vendió Hamburguesas dobles y el inventario quedó en 3. Se simula
-- con un ajuste de stock (no se crean pedidos, para que la verificación
-- final pueda mostrar que la cantidad de pedidos no cambió).
\set ON_ERROR_STOP on
DO $$ BEGIN
    IF current_database() <> 'copia_trabajo' THEN
        RAISE EXCEPTION 'Sólo sobre copia_trabajo (base actual: %)', current_database();
    END IF;
END $$;
BEGIN;
UPDATE producto SET stock = 3 WHERE id_producto = 2;
COMMIT;
SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 2;
