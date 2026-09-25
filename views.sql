-- =====================================================================
-- Food Store — views.sql
-- Unidad 3 / Semana 1 — Parte B (vistas simples) y Parte C (vista
-- materializada)
--
-- Nomenclatura: usuario→cliente, detalle_pedido→pedido_producto,
-- eliminado→activo (misma nota que en schema.sql / indices.sql). El
-- esquema Food Store no tiene columna de autenticación (no hay login),
-- así que el criterio de seguridad "ocultar contraseña" de la consigna
-- se aplica sobre los datos de contacto de cliente (email, teléfono),
-- que son el dato sensible más cercano disponible en este modelo — ver
-- vista_cliente_publico y la justificación en duia.md.
-- =====================================================================

-- -----------------------------------------------------------------
-- Vista 1 — productos vigentes con su categoría
-- -----------------------------------------------------------------
CREATE VIEW vista_producto_vigente AS
SELECT
    p.id_producto,
    p.nombre        AS producto,
    p.precio,
    p.stock,
    c.id_categoria,
    c.nombre        AS categoria
FROM producto p
JOIN categoria c ON c.id_categoria = p.id_categoria
WHERE p.activo = true
  AND c.activo = true;

-- -----------------------------------------------------------------
-- Vista 2 — pedidos con los datos del cliente
-- -----------------------------------------------------------------
CREATE VIEW vista_pedido_cliente AS
SELECT
    p.id_pedido,
    p.fecha,
    p.forma_pago,
    cl.id_cliente,
    cl.nombre || ' ' || cl.apellido AS cliente
FROM pedido p
JOIN cliente cl ON cl.id_cliente = p.id_cliente
WHERE cl.activo = true;

-- -----------------------------------------------------------------
-- Vista 3 — detalle de un pedido con el nombre del producto
-- (no se filtra por producto.activo: un pedido histórico tiene que
-- poder mostrar sus líneas aunque el producto se haya dado de baja
-- después; en cambio SÍ se expone el estado de vigencia como columna,
-- para que el consumidor de la vista decida qué hacer con eso)
-- -----------------------------------------------------------------
CREATE VIEW vista_detalle_pedido AS
SELECT
    pp.id_pedido,
    pr.id_producto,
    pr.nombre        AS producto,
    pr.activo        AS producto_vigente,
    pp.cantidad,
    pp.precio_unitario,
    (pp.cantidad * pp.precio_unitario) AS subtotal
FROM pedido_producto pp
JOIN producto pr ON pr.id_producto = pp.id_producto;

-- -----------------------------------------------------------------
-- Vista 4 — vista de seguridad: cliente sin datos de contacto
-- sensibles (equivalente a "usuario sin contraseña" de la consigna:
-- este esquema no tiene contraseña, así que el dato que se oculta es
-- el de contacto directo, email y teléfono, para poder otorgar SELECT
-- sobre esta vista a un rol que necesita ver la nómina de clientes
-- —por ejemplo, para reportes— sin exponer cómo contactarlos)
-- -----------------------------------------------------------------
CREATE VIEW vista_cliente_publico AS
SELECT
    id_cliente,
    nombre,
    apellido,
    activo,
    fecha_alta
FROM cliente;

-- =====================================================================
-- Parte C — vista materializada: facturación por categoría y mes
-- (reporte agregado costoso, ya usado como QA analítica en el TP4)
-- =====================================================================
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT
    c.id_categoria,
    c.nombre AS categoria,
    date_trunc('month', p.fecha) AS mes,
    SUM(pp.cantidad * pp.precio_unitario) AS facturacion,
    COUNT(DISTINCT p.id_pedido) AS cantidad_pedidos
FROM categoria c
JOIN producto pr ON pr.id_categoria = c.id_categoria
JOIN pedido_producto pp ON pp.id_producto = pr.id_producto
JOIN pedido p ON p.id_pedido = pp.id_pedido
WHERE c.activo = true
GROUP BY c.id_categoria, c.nombre, date_trunc('month', p.fecha)
WITH DATA;

-- Índice único: requisito de Postgres para poder usar
-- REFRESH MATERIALIZED VIEW CONCURRENTLY (que no bloquea lecturas
-- mientras se actualiza el reporte).
CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes
    ON mv_facturacion_categoria_mes (id_categoria, mes);

-- Refresco (ver informe_mediciones.md para la frecuencia recomendada):
-- REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
