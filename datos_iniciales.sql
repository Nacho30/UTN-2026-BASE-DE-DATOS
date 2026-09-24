-- =====================================================================
-- Food Store — datos_iniciales.sql
-- Carga inicial de prueba (datos ficticios) para el TP2 de Base de Datos II
-- =====================================================================
INSERT INTO categoria (nombre, descripcion) VALUES
 ('Hamburguesas', 'Hamburguesas y sándwiches'),   -- 1
 ('Pizzas',       'Pizzas individuales y grandes'), -- 2
 ('Bebidas',      'Gaseosas, aguas y jugos'),       -- 3
 ('Postres',      'Postres y helados'),             -- 4
 ('Ensaladas',    'Línea saludable (sin productos cargados todavía)'); -- 5

INSERT INTO producto (nombre, descripcion, precio, stock, id_categoria) VALUES
 ('Hamburguesa clásica', 'Carne, lechuga, tomate',  8500, 20, 1), -- 1
 ('Hamburguesa doble',   'Doble carne y cheddar',  11000, 10, 1), -- 2
 ('Pizza muzzarella',    'Grande, 8 porciones',    12000,  8, 2), -- 3
 ('Gaseosa 500 ml',      'Línea cola',              2500, 50, 3), -- 4
 ('Agua mineral 500 ml', 'Sin gas',                 1800, 40, 3), -- 5
 ('Flan casero',         'Con dulce de leche',      3500,  5, 4); -- 6
INSERT INTO producto (nombre, descripcion, precio, stock, id_categoria, activo) VALUES
 ('Pizza napolitana',    'Discontinuada',          13000,  0, 2, FALSE); -- 7

INSERT INTO cliente (nombre, apellido, email, telefono) VALUES
 ('Ana',   'Pérez', 'ana@example.com',   '11-5555-0001'),
 ('Bruno', 'Díaz',  'bruno@example.com', '11-5555-0002'),
 ('Carla', 'Gómez', 'carla@example.com', NULL);

INSERT INTO pedido (fecha, forma_pago, id_cliente) VALUES
 ('2026-09-20 20:15-03', 'TARJETA',       1), -- 1
 ('2026-09-21 13:02-03', 'EFECTIVO',      2), -- 2
 ('2026-09-22 21:40-03', 'TARJETA',       1), -- 3
 ('2026-09-23 12:10-03', 'TRANSFERENCIA', 3); -- 4

INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES
 (1, 1, 2, 8000), (1, 4, 2, 2500),
 (2, 3, 1, 12000),
 (3, 2, 1, 11000), (3, 5, 1, 1800),
 (4, 6, 2, 3500);
