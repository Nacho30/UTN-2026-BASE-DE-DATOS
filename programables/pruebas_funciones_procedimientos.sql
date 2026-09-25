-- =====================================================================
-- Food Store — programables/pruebas_funciones_procedimientos.sql
-- Casos de prueba reales de funciones_procedimientos.sql (positivos y
-- negativos). Pensado para correr manualmente y revisar el resultado
-- contra lo documentado en informe_tecnico_TPI.md.
-- =====================================================================

-- Caso 1 (función escalar): facturación de un cliente conocido
SELECT fn_facturacion_cliente(10450, '2026-01-01', '2027-01-01');

-- Caso 2 (función tabla): top 5 productos más vendidos de la categoría 3
SELECT * FROM fn_top_productos_categoria(3, 5);

-- Caso 3 (procedimiento, caso exitoso): registrar un pedido con 2 líneas
-- válidas. Se puede envolver en BEGIN/ROLLBACK para no dejar rastro.
BEGIN;
CALL sp_registrar_pedido(
    10450, 'TARJETA',
    '[{"id_producto":1,"cantidad":2},{"id_producto":2,"cantidad":1}]'::jsonb,
    NULL
);
-- Verificar: stock de producto 1 y 2 bajó, la línea quedó insertada.
SELECT id_producto, stock FROM producto WHERE id_producto IN (1,2);
ROLLBACK;

-- Caso 4 (procedimiento, caso negativo: RN2 — stock insuficiente):
-- la segunda línea pide más stock del que hay; el trigger aborta TODO
-- el CALL, incluida la primera línea que por sí sola era válida.
BEGIN;
CALL sp_registrar_pedido(
    10450, 'EFECTIVO',
    '[{"id_producto":3,"cantidad":5},{"id_producto":1,"cantidad":99999}]'::jsonb,
    NULL
);
-- Nunca se llega acá: el CALL de arriba aborta la transacción.
ROLLBACK;

-- Caso 5 (procedimiento, caso negativo: RN1 — producto de baja):
-- dar de baja un producto y luego intentar venderlo.
BEGIN;
UPDATE producto SET activo = false WHERE id_producto = 5;
CALL sp_registrar_pedido(
    10450, 'EFECTIVO',
    '[{"id_producto":5,"cantidad":1}]'::jsonb,
    NULL
);
ROLLBACK;

-- Caso 6 (procedimiento inverso): cancelar un pedido existente y
-- confirmar que el stock se repone y el pedido desaparece.
BEGIN;
CALL sp_registrar_pedido(
    10450, 'TARJETA',
    '[{"id_producto":1,"cantidad":2}]'::jsonb, NULL
) \gset caso6_
SELECT stock FROM producto WHERE id_producto = 1; -- debería estar -2
CALL sp_cancelar_pedido(:'caso6_p_id_pedido');
SELECT stock FROM producto WHERE id_producto = 1; -- debería volver al original
ROLLBACK;

-- Caso 7 (procedimiento, caso negativo): cancelar un pedido que no existe.
CALL sp_cancelar_pedido(999999999);
