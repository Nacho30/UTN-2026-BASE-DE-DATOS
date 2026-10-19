-- =====================================================================
-- auditoria_test.sql — Parte B, punto 2
-- Secuencia de prueba ejecutada como app_web (vía TCP, con contraseña).
-- La orquesta scripts/ejecutar_auditoria_test.sh, que además provoca un
-- inicio de sesión fallido del MOTOR (contraseña incorrecta) y captura
-- el fragmento de log resultante en docs/log_auditoria_prueba.txt.
-- =====================================================================

-- 1. Lectura (con log_statement = 'mod' NO debería aparecer en el log)
SELECT id, nombre, precio FROM producto WHERE id = 5;

-- 2. Inserción: un pedido nuevo con un renglón
INSERT INTO pedido (fecha, usuario_id, estado) VALUES (CURRENT_DATE, 42, 'CONFIRMADO');
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario, subtotal)
SELECT currval('pedido_id_seq'), id, 2, precio, precio * 2 FROM producto WHERE id = 5;

-- 3. Actualización: el pedido pasa a ENTREGADO
UPDATE pedido SET estado = 'ENTREGADO' WHERE id = currval('pedido_id_seq');

-- 4. Inicio de sesión fallido de la APLICACIÓN (no del motor)
SELECT fn_autenticar('camila.perez42@yahoo.com.ar', 'contraseña-equivocada') AS login_app;

-- 5. Operación no permitida para app_web (queda como ERROR en el log)
DELETE FROM pedido WHERE id = currval('pedido_id_seq');
