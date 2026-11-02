-- 002_lineas_de_pedido_inmutables.sql — Food Store (TP Unidad 8, code review)
-- Hallazgo: trg_pedido_producto_valida_y_descuenta_stock (001) sólo corre
-- en INSERT. Un UPDATE de pedido_producto podía cambiar la cantidad sin
-- tocar el stock (RN2) o pasar la línea a un producto dado de baja (RN1),
-- y también reescribir el precio histórico (R4).
-- Decisión: una línea de pedido no se modifica. Para corregir un pedido se
-- cancela (sp_cancelar_pedido, que repone stock) y se registra de nuevo.
-- No se bloquea DELETE: lo usan el ON DELETE CASCADE de pedido y
-- sp_cancelar_pedido, que repone el stock antes de borrar.

CREATE OR REPLACE FUNCTION fn_pedido_producto_inmutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Las líneas de pedido no se modifican (pedido %, producto %): cancelar el pedido y registrarlo de nuevo',
        OLD.id_pedido, OLD.id_producto
        USING ERRCODE = 'check_violation';
END;
$$;

CREATE TRIGGER trg_pedido_producto_inmutable
    BEFORE UPDATE OF id_pedido, id_producto, cantidad, precio_unitario ON pedido_producto
    FOR EACH ROW
    EXECUTE FUNCTION fn_pedido_producto_inmutable();
