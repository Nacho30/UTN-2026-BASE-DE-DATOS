-- Verificación de equivalencia: vista vs. consulta manual equivalente
-- escrita por separado. 0 filas de diferencia en ambos sentidos = OK.

SELECT 'v1_producto_vigente' AS vista, COUNT(*) AS diferencias FROM (
    (SELECT * FROM vista_producto_vigente)
    EXCEPT
    (SELECT p.id_producto, p.nombre, p.precio, p.stock, c.id_categoria, c.nombre
     FROM producto p, categoria c
     WHERE c.id_categoria = p.id_categoria AND p.activo = true AND c.activo = true)
) x
UNION ALL
SELECT 'v1_reverso', COUNT(*) FROM (
    (SELECT p.id_producto, p.nombre, p.precio, p.stock, c.id_categoria, c.nombre
     FROM producto p, categoria c
     WHERE c.id_categoria = p.id_categoria AND p.activo = true AND c.activo = true)
    EXCEPT
    (SELECT * FROM vista_producto_vigente)
) x

UNION ALL
SELECT 'v2_pedido_cliente', COUNT(*) FROM (
    (SELECT * FROM vista_pedido_cliente)
    EXCEPT
    (SELECT p.id_pedido, p.fecha, p.forma_pago, c.id_cliente, c.nombre || ' ' || c.apellido
     FROM pedido p, cliente c
     WHERE c.id_cliente = p.id_cliente AND c.activo = true)
) x
UNION ALL
SELECT 'v2_reverso', COUNT(*) FROM (
    (SELECT p.id_pedido, p.fecha, p.forma_pago, c.id_cliente, c.nombre || ' ' || c.apellido
     FROM pedido p, cliente c
     WHERE c.id_cliente = p.id_cliente AND c.activo = true)
    EXCEPT
    (SELECT * FROM vista_pedido_cliente)
) x

UNION ALL
SELECT 'v3_detalle_pedido', COUNT(*) FROM (
    (SELECT * FROM vista_detalle_pedido)
    EXCEPT
    (SELECT pp.id_pedido, pr.id_producto, pr.nombre, pr.activo, pp.cantidad,
            pp.precio_unitario, pp.cantidad * pp.precio_unitario
     FROM pedido_producto pp, producto pr
     WHERE pr.id_producto = pp.id_producto)
) x
UNION ALL
SELECT 'v3_reverso', COUNT(*) FROM (
    (SELECT pp.id_pedido, pr.id_producto, pr.nombre, pr.activo, pp.cantidad,
            pp.precio_unitario, pp.cantidad * pp.precio_unitario
     FROM pedido_producto pp, producto pr
     WHERE pr.id_producto = pp.id_producto)
    EXCEPT
    (SELECT * FROM vista_detalle_pedido)
) x

UNION ALL
SELECT 'v4_cliente_publico', COUNT(*) FROM (
    (SELECT * FROM vista_cliente_publico)
    EXCEPT
    (SELECT id_cliente, nombre, apellido, activo, fecha_alta FROM cliente)
) x
UNION ALL
SELECT 'v4_reverso', COUNT(*) FROM (
    (SELECT id_cliente, nombre, apellido, activo, fecha_alta FROM cliente)
    EXCEPT
    (SELECT * FROM vista_cliente_publico)
) x

UNION ALL
SELECT 'mv_facturacion', COUNT(*) FROM (
    (SELECT id_categoria, categoria, mes, facturacion, cantidad_pedidos FROM mv_facturacion_categoria_mes)
    EXCEPT
    (SELECT c.id_categoria, c.nombre, date_trunc('month', p.fecha),
            SUM(pp.cantidad * pp.precio_unitario), COUNT(DISTINCT p.id_pedido)
     FROM categoria c
     JOIN producto pr ON pr.id_categoria = c.id_categoria
     JOIN pedido_producto pp ON pp.id_producto = pr.id_producto
     JOIN pedido p ON p.id_pedido = pp.id_pedido
     WHERE c.activo = true
     GROUP BY c.id_categoria, c.nombre, date_trunc('month', p.fecha))
) x
UNION ALL
SELECT 'mv_reverso', COUNT(*) FROM (
    (SELECT c.id_categoria, c.nombre, date_trunc('month', p.fecha),
            SUM(pp.cantidad * pp.precio_unitario), COUNT(DISTINCT p.id_pedido)
     FROM categoria c
     JOIN producto pr ON pr.id_categoria = c.id_categoria
     JOIN pedido_producto pp ON pp.id_producto = pr.id_producto
     JOIN pedido p ON p.id_pedido = pp.id_pedido
     WHERE c.activo = true
     GROUP BY c.id_categoria, c.nombre, date_trunc('month', p.fecha))
    EXCEPT
    (SELECT id_categoria, categoria, mes, facturacion, cantidad_pedidos FROM mv_facturacion_categoria_mes)
) x;
