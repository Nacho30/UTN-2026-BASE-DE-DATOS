-- 001_restricciones_reglas_negocio.sql — Food Store
-- RN1: no se puede vender (insertar en pedido_producto) un producto dado de baja (producto.activo = FALSE).
-- RN2: al registrar una línea de pedido se descuenta producto.stock; si el stock no alcanza, se rechaza.
-- RN3: una categoría no puede darse de baja (categoria.activo -> FALSE) mientras tenga productos activos.

-- RN1 + RN2: un solo trigger, porque ambas reglas leen la misma fila de producto
-- y el descuento de stock tiene que hacerse con esa fila bloqueada.
CREATE OR REPLACE FUNCTION fn_pedido_producto_valida_y_descuenta_stock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_activo BOOLEAN;
    v_stock  INTEGER;
BEGIN
    SELECT activo, stock INTO v_activo, v_stock
    FROM producto
    WHERE id_producto = NEW.id_producto
    FOR UPDATE;

    IF v_activo IS FALSE THEN
        RAISE EXCEPTION 'El producto % está dado de baja y no se puede vender', NEW.id_producto
            USING ERRCODE = 'check_violation';
    END IF;

    IF v_stock < NEW.cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente para el producto %: disponible %, pedido %',
            NEW.id_producto, v_stock, NEW.cantidad
            USING ERRCODE = 'check_violation';
    END IF;

    UPDATE producto
    SET stock = stock - NEW.cantidad
    WHERE id_producto = NEW.id_producto;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_pedido_producto_valida_y_descuenta_stock
    BEFORE INSERT ON pedido_producto
    FOR EACH ROW
    EXECUTE FUNCTION fn_pedido_producto_valida_y_descuenta_stock();

-- RN3
CREATE OR REPLACE FUNCTION fn_categoria_baja_sin_productos_activos()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.activo AND NOT NEW.activo AND EXISTS (
        SELECT 1 FROM producto
        WHERE id_categoria = NEW.id_categoria AND activo
    ) THEN
        RAISE EXCEPTION 'La categoría % tiene productos activos: darlos de baja primero', NEW.id_categoria
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_categoria_baja_sin_productos_activos
    BEFORE UPDATE OF activo ON categoria
    FOR EACH ROW
    EXECUTE FUNCTION fn_categoria_baja_sin_productos_activos();
