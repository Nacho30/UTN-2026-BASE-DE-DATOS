-- =====================================================================
-- Food Store — programables/funciones_procedimientos.sql
-- TPI — objetivo 6: funciones y procedimientos almacenados en PL/pgSQL
--
-- Requisito previo: los triggers de migraciones/001_restricciones_
-- reglas_negocio.sql (RN1/RN2/RN3) deben estar aplicados — los
-- procedimientos de acá se apoyan en esas reglas, no las duplican.
-- =====================================================================

-- -----------------------------------------------------------------
-- Función 1 (escalar) — facturación de un cliente en un período
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_facturacion_cliente(
    p_id_cliente BIGINT,
    p_desde      TIMESTAMPTZ,
    p_hasta      TIMESTAMPTZ
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_total NUMERIC;
BEGIN
    SELECT COALESCE(SUM(pp.cantidad * pp.precio_unitario), 0)
    INTO v_total
    FROM pedido p
    JOIN pedido_producto pp ON pp.id_pedido = p.id_pedido
    WHERE p.id_cliente = p_id_cliente
      AND p.fecha >= p_desde
      AND p.fecha <  p_hasta;

    RETURN v_total;
END;
$$;

-- -----------------------------------------------------------------
-- Función 2 (tabla) — top-N productos más vendidos de una categoría
-- -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_top_productos_categoria(
    p_id_categoria BIGINT,
    p_limite       INTEGER DEFAULT 10
)
RETURNS TABLE (
    id_producto      BIGINT,
    producto         VARCHAR,
    unidades_vendidas NUMERIC,
    facturacion      NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    -- OJO (bug real encontrado y corregido durante las pruebas): los
    -- nombres de columna de RETURNS TABLE quedan disponibles como
    -- variables PL/pgSQL dentro del cuerpo de la función. Un ORDER BY
    -- que referencia el alias "unidades_vendidas" del SELECT en
    -- realidad resuelve contra esa variable (NULL), no contra la
    -- columna calculada, y el resultado sale sin ordenar. Por eso acá
    -- se ordena por la expresión repetida, no por el alias.
    RETURN QUERY
    SELECT pr.id_producto,
           pr.nombre,
           SUM(pp.cantidad)::NUMERIC,
           SUM(pp.cantidad * pp.precio_unitario)
    FROM producto pr
    JOIN pedido_producto pp ON pp.id_producto = pr.id_producto
    WHERE pr.id_categoria = p_id_categoria
      AND pr.activo = true
    GROUP BY pr.id_producto, pr.nombre
    ORDER BY SUM(pp.cantidad) DESC
    LIMIT p_limite;
END;
$$;

-- -----------------------------------------------------------------
-- Procedimiento 1 (CALL) — registrar un pedido completo a partir de un
-- carrito en JSONB: [{"id_producto": 1, "cantidad": 2}, ...]
--
-- Encapsula en una sola unidad transaccional: crear el pedido, crear
-- cada línea (lo que dispara trg_pedido_producto_valida_y_descuenta_stock,
-- que valida RN1/RN2 y descuenta stock por cada línea). Si cualquier
-- línea falla (producto de baja o sin stock), el RAISE EXCEPTION del
-- trigger aborta todo el procedimiento: no queda ni el pedido ni
-- ninguna línea a medio insertar — atomicidad real, no simulada.
-- -----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_pedido(
    p_id_cliente BIGINT,
    p_forma_pago forma_pago,
    p_items      JSONB,
    INOUT p_id_pedido BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_item JSONB;
BEGIN
    IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'p_items debe ser un array JSONB no vacío de {"id_producto","cantidad"}';
    END IF;

    INSERT INTO pedido (fecha, forma_pago, id_cliente)
    VALUES (now(), p_forma_pago, p_id_cliente)
    RETURNING id_pedido INTO p_id_pedido;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
        SELECT
            p_id_pedido,
            (v_item->>'id_producto')::BIGINT,
            (v_item->>'cantidad')::INTEGER,
            pr.precio
        FROM producto pr
        WHERE pr.id_producto = (v_item->>'id_producto')::BIGINT;
        -- El trigger RN1/RN2 valida vigencia y stock, y descuenta stock,
        -- en cada uno de estos INSERT. Si algo falla, se propaga y
        -- aborta todo el CALL (incluido el INSERT en pedido de arriba).
    END LOOP;
END;
$$;

-- -----------------------------------------------------------------
-- Procedimiento 2 (CALL) — cancelar un pedido: repone el stock de cada
-- línea y elimina el pedido (CASCADE ya borra pedido_producto). Es la
-- operación inversa de sp_registrar_pedido, y demuestra la misma
-- atomicidad: si la reposición de stock de alguna línea fallara, no
-- queda el pedido borrado con el stock a medio reponer.
-- -----------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_cancelar_pedido(p_id_pedido BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_existe BOOLEAN;
BEGIN
    SELECT EXISTS(SELECT 1 FROM pedido WHERE id_pedido = p_id_pedido) INTO v_existe;
    IF NOT v_existe THEN
        RAISE EXCEPTION 'El pedido % no existe', p_id_pedido;
    END IF;

    UPDATE producto pr
    SET stock = pr.stock + pp.cantidad
    FROM pedido_producto pp
    WHERE pp.id_pedido = p_id_pedido
      AND pp.id_producto = pr.id_producto;

    DELETE FROM pedido WHERE id_pedido = p_id_pedido;
    -- ON DELETE CASCADE de pedido_producto.id_pedido_fkey borra las líneas.
END;
$$;
