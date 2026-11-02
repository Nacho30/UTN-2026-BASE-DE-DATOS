-- =====================================================================
-- Food Store — TP Unidad 8 · servidor/01_vista_snapshot.sql
-- Vista que define QUÉ viaja a la tablet (consigna 1.a y 2.a).
-- Sólo sobre la base de PRUEBAS copia_trabajo (protocolo_seguridad.md).
--   psql -X -v ON_ERROR_STOP=1 -d copia_trabajo -f servidor/01_vista_snapshot.sql
-- =====================================================================
\set ON_ERROR_STOP on
DO $$ BEGIN
    IF current_database() <> 'copia_trabajo' THEN
        RAISE EXCEPTION 'Este script sólo corre sobre copia_trabajo (base actual: %)', current_database();
    END IF;
END $$;

CREATE OR REPLACE VIEW v_snapshot_movil AS
SELECT
    p.id_producto                        AS id,
    p.nombre,
    -- NUMERIC(10,2) * 100 es exacto: no hay redondeo al pasar a centavos
    (p.precio * 100)::bigint             AS precio_centavos,
    p.stock,
    -- se puede vender hoy: producto y categoría vigentes y con stock
    (p.activo AND c.activo AND p.stock > 0) AS disponible,
    -- lápida: el producto se dio de baja (R7). Viaja igual, para que la
    -- tablet lo oculte sin borrar la fila que usan sus borradores.
    NOT p.activo                         AS eliminado,
    to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS fecha_snapshot
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria;
-- Sin WHERE a propósito: los dados de baja también viajan (lápidas).
-- No viajan: descripcion, id_categoria, created_at, ni nada de cliente,
-- pedido o pedido_producto.

COMMENT ON VIEW v_snapshot_movil IS
    'TP U8: instantánea del catálogo para la tablet (incluye lápidas de productos dados de baja)';

SELECT * FROM v_snapshot_movil ORDER BY id;
