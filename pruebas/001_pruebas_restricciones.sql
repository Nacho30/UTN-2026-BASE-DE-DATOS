-- Pruebas de 001 (Food Store). Cada caso inválido va en un SAVEPOINT.
INSERT INTO pedido (forma_pago, id_cliente) VALUES ('EFECTIVO', 2);
INSERT INTO pedido (forma_pago, id_cliente) VALUES ('TARJETA', 3);
-- RN1 válido: producto activo (4, Gaseosa)
INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
VALUES ((SELECT max(id_pedido) - 1 FROM pedido), 4, 1, 2500);
-- RN1 inválido: producto 7 (Pizza napolitana) dado de baja
SAVEPOINT s1;
INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
VALUES ((SELECT max(id_pedido) - 1 FROM pedido), 7, 1, 13000);
ROLLBACK TO SAVEPOINT s1;
-- RN2 válido: Flan (6) tiene stock 5, se piden 3 -> queda 2
INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
VALUES ((SELECT max(id_pedido) - 1 FROM pedido), 6, 3, 3500);
SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 6;
-- RN2 inválido: se piden 3 más y quedan 2
SAVEPOINT s2;
INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
VALUES ((SELECT max(id_pedido) FROM pedido), 6, 3, 3500);
ROLLBACK TO SAVEPOINT s2;
-- RN2 válido (borde): se piden exactamente los 2 que quedan -> stock 0
INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
VALUES ((SELECT max(id_pedido) FROM pedido), 6, 2, 3500);
SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 6;
-- RN3 inválido: Hamburguesas (1) tiene productos activos
SAVEPOINT s3;
UPDATE categoria SET activo = FALSE WHERE id_categoria = 1;
ROLLBACK TO SAVEPOINT s3;
-- RN3 válido: Ensaladas (5) no tiene productos
UPDATE categoria SET activo = FALSE WHERE id_categoria = 5;
-- RN3: Pizzas (2) tiene la muzzarella (3) activa -> rechazo; se da de baja la pizza y ahí sí
SAVEPOINT s4;
UPDATE categoria SET activo = FALSE WHERE id_categoria = 2;
ROLLBACK TO SAVEPOINT s4;
UPDATE producto SET activo = FALSE WHERE id_producto = 3;
UPDATE categoria SET activo = FALSE WHERE id_categoria = 2;
-- RN3: cambiar otra columna no dispara la validación
UPDATE categoria SET descripcion = 'Hamburguesas caseras' WHERE id_categoria = 1;
SELECT id_categoria, nombre, activo FROM categoria ORDER BY id_categoria;
