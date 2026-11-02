-- Restaura el estado inicial entre corridas del laboratorio (solo en copia_trabajo).
-- Corrección TP U8 (code review): el comentario no impedía correrlo sobre otra
-- base; ahora se verifica antes de borrar nada. ON_ERROR_STOP es necesario:
-- sin él, psql informa el error del DO y sigue con los DELETE de abajo.
\set ON_ERROR_STOP on
DO $$ BEGIN
    IF current_database() <> 'copia_trabajo' THEN
        RAISE EXCEPTION 'reset.sql sólo corre sobre copia_trabajo (base actual: %)', current_database();
    END IF;
END $$;
DELETE FROM pedido_producto
WHERE (id_pedido, id_producto) NOT IN ((1,1),(1,4),(2,3),(3,2),(3,5),(4,6));
DELETE FROM pedido WHERE id_pedido > 4;
UPDATE producto SET precio = 8500 WHERE id_producto = 1;
UPDATE producto SET stock = CASE id_producto
    WHEN 1 THEN 20 WHEN 2 THEN 10 WHEN 3 THEN 8 WHEN 4 THEN 50
    WHEN 5 THEN 40 WHEN 6 THEN 5 ELSE 0 END;
