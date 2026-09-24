-- =====================================================================
-- Food Store — carga_masiva.sql
-- Parte 1: script pedido a la IA (spec transcripta abajo) para poblar
-- masivamente la base y poder medir Seq Scan vs Index Scan a escala.
-- =====================================================================
-- Spec usada con la IA (OpenCode):
-- "Generá un script SQL para PostgreSQL que inserte 50.000 filas en
-- producto, distribuidas de forma pareja entre las categorías
-- existentes, con precios entre 500 y 5000 y stock aleatorio entre 0 y
-- 200. Sumá 20.000 filas en cliente con email único, y 200.000 filas en
-- pedido con forma_pago aleatoria y fecha en los últimos 2 años,
-- repartidas entre los clientes existentes. Para cada pedido, generá
-- entre 1 y 4 líneas en pedido_producto con productos aleatorios de los
-- ya existentes (no solo los recién creados) y cantidad entre 1 y 5.
-- Usá generate_series y evitá PL/pgSQL si no es necesario. No toques
-- categoria ni ninguna otra tabla."
--
-- Revisión manual antes de ejecutar (paso 2 del protocolo de la
-- cátedra): se verificó que
--   - no hay DROP/TRUNCATE de ninguna tabla;
--   - los INSERT respetan los CHECK (precio/stock >= 0, cantidad > 0);
--   - id_categoria e id_cliente se toman de rangos reales via
--     subconsultas (min/max), no se hardcodean IDs;
--   - el ON CONFLICT evita violar la PK compuesta de pedido_producto
--     cuando el sorteo aleatorio repite un producto dentro del mismo
--     pedido.
-- =====================================================================

BEGIN;

-- 1) 50.000 productos, repartidos parejo entre las categorías existentes
INSERT INTO producto (nombre, precio, stock, id_categoria)
SELECT
    'Producto masivo ' || s,
    round((500 + random() * 4500)::numeric, 2),
    floor(random() * 201)::int,
    c.id_categoria
FROM generate_series(1, 50000) AS s
JOIN LATERAL (
    SELECT id_categoria
    FROM categoria
    ORDER BY id_categoria
    OFFSET (s % (SELECT count(*) FROM categoria))
    LIMIT 1
) c ON true;

-- 2) 20.000 clientes con email único
INSERT INTO cliente (nombre, apellido, email)
SELECT
    'Cliente' || s,
    'Apellido' || s,
    'cliente' || s || '.masivo@foodstore.test'
FROM generate_series(1, 20000) AS s;

-- 3) 200.000 pedidos, distribuidos entre TODOS los clientes existentes
--    (seed + masivos) y con fecha en los últimos 2 años
INSERT INTO pedido (fecha, forma_pago, id_cliente)
SELECT
    now() - (random() * interval '730 days'),
    (ARRAY['EFECTIVO', 'TARJETA', 'TRANSFERENCIA']::forma_pago[])[1 + floor(random() * 3)::int],
    cb.mn + floor(random() * (cb.mx - cb.mn + 1))::bigint
FROM generate_series(1, 200000) AS s
CROSS JOIN (SELECT min(id_cliente) mn, max(id_cliente) mx FROM cliente) cb;

-- 4) Entre 1 y 4 líneas por pedido, productos aleatorios de TODO el
--    universo de productos (seed + masivos), precio_unitario tomado del
--    precio actual del producto en el momento de la "venta" simulada
-- NOTA: el término "+ (p.id_pedido - p.id_pedido)" es una correlación
-- deliberada (siempre suma 0) con la fila externa: sin ella, PostgreSQL
-- evalúa el argumento de generate_series() una sola vez para toda la
-- consulta en lugar de una vez por pedido (detectado al validar la
-- distribución real de líneas por pedido tras una primera corrida de
-- prueba, que dio "todos los pedidos con la misma cantidad de líneas").
INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
SELECT
    p.id_pedido,
    elegido.id_producto,
    1 + floor(random() * 5)::int,
    pr.precio
FROM pedido p
CROSS JOIN (SELECT min(id_producto) mn, max(id_producto) mx FROM producto) pb
CROSS JOIN LATERAL generate_series(1, 1 + floor(random() * 4)::int + (p.id_pedido - p.id_pedido)) AS linea
CROSS JOIN LATERAL (
    SELECT pb.mn + floor(random() * (pb.mx - pb.mn + 1))::bigint + (linea - linea) AS id_producto
) elegido
JOIN producto pr ON pr.id_producto = elegido.id_producto
ON CONFLICT (id_pedido, id_producto) DO NOTHING;

COMMIT;

-- 5) Actualizar estadísticas del planificador antes de medir
ANALYZE categoria;
ANALYZE producto;
ANALYZE cliente;
ANALYZE pedido;
ANALYZE pedido_producto;
