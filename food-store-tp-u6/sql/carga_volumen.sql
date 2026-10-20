-- =====================================================================
-- carga_volumen.sql — SÓLO LABORATORIO (TP Unidad 6)
-- Agrega volumen de datos ficticio a foodstore para que el respaldo, el
-- monitoreo y la restauración tengan algo medible. Determinista (sin
-- random()): dos ejecuciones sobre una base recién creada dan lo mismo.
--
-- Requiere, en este orden: schema.sql, migraciones/001_*.sql,
-- programables/funciones_procedimientos.sql y datos_iniciales.sql.
--   psql -d foodstore -v ON_ERROR_STOP=1 -f food-store-tp-u6/sql/carga_volumen.sql
-- =====================================================================
\set ON_ERROR_STOP on
DO $$ BEGIN
    IF current_database() <> 'foodstore' THEN
        RAISE EXCEPTION 'carga_volumen.sql sólo se ejecuta sobre foodstore (base actual: %)', current_database();
    END IF;
END $$;

BEGIN;

-- 10 categorías más (en total 15)
INSERT INTO categoria (nombre, descripcion)
SELECT n, 'Categoría de laboratorio'
FROM unnest(ARRAY['Empanadas','Sushi','Pastas','Milanesas','Wraps',
                  'Cafetería','Helados','Parrilla','Vegano','Sin TACC']) n;

-- 300 productos activos, con stock alto para que la carga de pedidos
-- no choque con RN2 (el trigger descuenta stock en cada línea)
INSERT INTO producto (nombre, descripcion, precio, stock, id_categoria)
SELECT 'Producto ' || g,
       'Generado para el laboratorio U6',
       (1500 + (g * 137) % 14000)::numeric(10,2),
       1000000,
       c.id_categoria
FROM generate_series(1, 300) g
JOIN LATERAL (SELECT id_categoria FROM categoria
              WHERE nombre <> 'Ensaladas'
              ORDER BY id_categoria OFFSET (g % 14) LIMIT 1) c ON TRUE;

-- 5.000 clientes
INSERT INTO cliente (nombre, apellido, email, telefono, fecha_alta)
SELECT 'Cliente' || g, 'Lab', 'cliente' || g || '@example.com',
       '11-5555-' || lpad((g % 10000)::text, 4, '0'),
       now() - make_interval(days => 400 + g % 300)
FROM generate_series(1, 5000) g;

-- 150.000 pedidos repartidos en el último año
INSERT INTO pedido (fecha, forma_pago, id_cliente)
SELECT now() - make_interval(days => 1 + g % 365, mins => (g * 37) % 1440),
       (ARRAY['EFECTIVO','TARJETA','TRANSFERENCIA']::forma_pago[])[1 + g % 3],
       c.min_id + (g * 7919) % 5000
FROM generate_series(1, 150000) g,
     (SELECT min(id_cliente) AS min_id FROM cliente WHERE email LIKE 'cliente%@example.com') c;

-- 1 a 4 líneas por pedido, productos distintos dentro del pedido.
-- Cada INSERT dispara trg_pedido_producto_valida_y_descuenta_stock (RN1/RN2).
INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
SELECT p.id_pedido, pr.id_producto, 1 + (p.id_pedido + k) % 3, pr.precio
FROM pedido p
CROSS JOIN LATERAL generate_series(1, 1 + p.id_pedido % 4) k
JOIN LATERAL (SELECT min(id_producto) AS base FROM producto WHERE nombre LIKE 'Producto %') b ON TRUE
JOIN producto pr ON pr.id_producto = b.base + (p.id_pedido * 7 + k * 31) % 300
WHERE p.id_pedido > 4;          -- los 4 pedidos de datos_iniciales ya tienen líneas

COMMIT;

SELECT 'categoria' AS tabla, count(*) AS filas FROM categoria
UNION ALL SELECT 'cliente', count(*) FROM cliente
UNION ALL SELECT 'producto', count(*) FROM producto
UNION ALL SELECT 'pedido', count(*) FROM pedido
UNION ALL SELECT 'pedido_producto', count(*) FROM pedido_producto;
