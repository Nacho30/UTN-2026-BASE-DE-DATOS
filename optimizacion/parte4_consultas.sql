-- =====================================================================
-- Parte 4 — Consulta A: RESUMEN / AGREGACIÓN
-- Spec: "Para cada cliente activo, devolver su nombre completo (nombre +
-- apellido) y el monto total gastado (suma de cantidad * precio_unitario
-- de todas las líneas de sus pedidos), incluyendo a los clientes activos
-- que todavía no hicieron ningún pedido con monto 0. Ordenar de mayor a
-- menor monto gastado. Como criterio de corte, devolver solo los primeros
-- 20. Tablas involucradas: cliente, pedido, pedido_producto. No usar
-- SELECT *."
-- =====================================================================

-- Versión 1 (generada a partir de la spec, pedida a la IA): JOIN directo
-- de las tres tablas y agregación al final.
SELECT
    c.nombre || ' ' || c.apellido AS cliente,
    COALESCE(SUM(pp.cantidad * pp.precio_unitario), 0) AS monto_total
FROM cliente c
LEFT JOIN pedido p ON p.id_cliente = c.id_cliente
LEFT JOIN pedido_producto pp ON pp.id_pedido = p.id_pedido
WHERE c.activo = true
GROUP BY c.id_cliente, c.nombre, c.apellido
ORDER BY monto_total DESC, c.id_cliente
LIMIT 20;

-- Versión 2 (propia, estructura distinta: subconsulta agregada primero,
-- después LEFT JOIN contra cliente) — misma pregunta, otro camino.
SELECT
    c.nombre || ' ' || c.apellido AS cliente,
    COALESCE(gastos.monto_total, 0) AS monto_total
FROM cliente c
LEFT JOIN (
    SELECT pd.id_cliente, SUM(pp.cantidad * pp.precio_unitario) AS monto_total
    FROM pedido pd
    JOIN pedido_producto pp ON pp.id_pedido = pd.id_pedido
    GROUP BY pd.id_cliente
) gastos ON gastos.id_cliente = c.id_cliente
WHERE c.activo = true
ORDER BY monto_total DESC, c.id_cliente
LIMIT 20;

-- Verificación de equivalencia SOBRE EL CONJUNTO COMPLETO (sin LIMIT,
-- que es lo que realmente hay que comparar: el LIMIT solo recorta la
-- salida ya ordenada, no cambia qué fila le corresponde a qué cliente).
(
    SELECT c.nombre || ' ' || c.apellido AS cliente,
           COALESCE(SUM(pp.cantidad * pp.precio_unitario), 0) AS monto_total
    FROM cliente c
    LEFT JOIN pedido p ON p.id_cliente = c.id_cliente
    LEFT JOIN pedido_producto pp ON pp.id_pedido = p.id_pedido
    WHERE c.activo = true
    GROUP BY c.id_cliente, c.nombre, c.apellido
)
EXCEPT
(
    SELECT c.nombre || ' ' || c.apellido AS cliente,
           COALESCE(gastos.monto_total, 0) AS monto_total
    FROM cliente c
    LEFT JOIN (
        SELECT pd.id_cliente, SUM(pp.cantidad * pp.precio_unitario) AS monto_total
        FROM pedido pd
        JOIN pedido_producto pp ON pp.id_pedido = pd.id_pedido
        GROUP BY pd.id_cliente
    ) gastos ON gastos.id_cliente = c.id_cliente
    WHERE c.activo = true
);

(
    SELECT c.nombre || ' ' || c.apellido AS cliente,
           COALESCE(gastos.monto_total, 0) AS monto_total
    FROM cliente c
    LEFT JOIN (
        SELECT pd.id_cliente, SUM(pp.cantidad * pp.precio_unitario) AS monto_total
        FROM pedido pd
        JOIN pedido_producto pp ON pp.id_pedido = pd.id_pedido
        GROUP BY pd.id_cliente
    ) gastos ON gastos.id_cliente = c.id_cliente
    WHERE c.activo = true
)
EXCEPT
(
    SELECT c.nombre || ' ' || c.apellido AS cliente,
           COALESCE(SUM(pp.cantidad * pp.precio_unitario), 0) AS monto_total
    FROM cliente c
    LEFT JOIN pedido p ON p.id_cliente = c.id_cliente
    LEFT JOIN pedido_producto pp ON pp.id_pedido = p.id_pedido
    WHERE c.activo = true
    GROUP BY c.id_cliente, c.nombre, c.apellido
);


-- =====================================================================
-- Parte 4 — Consulta B: SUBCONSULTA
-- Spec: "Listar los productos activos cuyo precio sea mayor al precio
-- promedio de su propia categoría, considerando solo productos activos
-- para calcular ese promedio. Devolver id_producto, nombre, precio e
-- id_categoria. Ordenar por id_categoria y, dentro de cada categoría,
-- por precio de mayor a menor. Tablas involucradas: producto. Filtro de
-- borrado lógico: activo = true en ambos lados (el producto y el
-- universo sobre el que se calcula el promedio). No usar SELECT *."
-- =====================================================================

-- Versión 1 (generada a partir de la spec, pedida a la IA): subconsulta
-- correlacionada.
SELECT p.id_producto, p.nombre, p.precio, p.id_categoria
FROM producto p
WHERE p.activo = true
  AND p.precio > (
      SELECT AVG(p2.precio)
      FROM producto p2
      WHERE p2.id_categoria = p.id_categoria AND p2.activo = true
  )
ORDER BY p.id_categoria, p.precio DESC;

-- Versión 2 (propia, estructura distinta: JOIN contra una tabla derivada
-- de promedios por categoría, en vez de subconsulta correlacionada).
SELECT p.id_producto, p.nombre, p.precio, p.id_categoria
FROM producto p
JOIN (
    SELECT id_categoria, AVG(precio) AS precio_prom
    FROM producto
    WHERE activo = true
    GROUP BY id_categoria
) avg_cat ON avg_cat.id_categoria = p.id_categoria
WHERE p.activo = true AND p.precio > avg_cat.precio_prom
ORDER BY p.id_categoria, p.precio DESC;

-- Verificación de equivalencia
(
    SELECT p.id_producto, p.nombre, p.precio, p.id_categoria
    FROM producto p
    WHERE p.activo = true
      AND p.precio > (
          SELECT AVG(p2.precio)
          FROM producto p2
          WHERE p2.id_categoria = p.id_categoria AND p2.activo = true
      )
)
EXCEPT
(
    SELECT p.id_producto, p.nombre, p.precio, p.id_categoria
    FROM producto p
    JOIN (
        SELECT id_categoria, AVG(precio) AS precio_prom
        FROM producto
        WHERE activo = true
        GROUP BY id_categoria
    ) avg_cat ON avg_cat.id_categoria = p.id_categoria
    WHERE p.activo = true AND p.precio > avg_cat.precio_prom
);

(
    SELECT p.id_producto, p.nombre, p.precio, p.id_categoria
    FROM producto p
    JOIN (
        SELECT id_categoria, AVG(precio) AS precio_prom
        FROM producto
        WHERE activo = true
        GROUP BY id_categoria
    ) avg_cat ON avg_cat.id_categoria = p.id_categoria
    WHERE p.activo = true AND p.precio > avg_cat.precio_prom
)
EXCEPT
(
    SELECT p.id_producto, p.nombre, p.precio, p.id_categoria
    FROM producto p
    WHERE p.activo = true
      AND p.precio > (
          SELECT AVG(p2.precio)
          FROM producto p2
          WHERE p2.id_categoria = p.id_categoria AND p2.activo = true
      )
);
