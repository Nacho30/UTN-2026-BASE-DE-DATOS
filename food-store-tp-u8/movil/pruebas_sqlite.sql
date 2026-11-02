PRAGMA foreign_keys = ON;
-- =====================================================================
-- Food Store — TP Unidad 8 · movil/pruebas_sqlite.sql   (consigna 1.c)
-- Requiere schema_sqlite.sql y una instantánea cargada (cargar_snapshot.sql).
--   sqlite3 foodstore_movil.db < pruebas_sqlite.sql
-- Los UUID son fijos para que la prueba sea repetible y legible.
-- Los errores que aparecen en la salida son ESPERADOS (casos negativos).
-- =====================================================================

-- ---------------------------------------------------------------------
.print '== 1a. Borrador completo (borrador + ítems + solicitud) con BEGIN ... COMMIT'
-- ---------------------------------------------------------------------
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b1000000-0000-4000-8000-000000000001', 'vendedor_feria_01', 'EFECTIVO');

-- El precio visto se toma del catálogo local, sólo si el producto se puede vender
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b1000000-0000-4000-8000-000000000001', id, 1, precio_centavos
FROM producto_cache WHERE id = 3 AND disponible = 1 AND eliminado = 0;   -- Pizza muzzarella

INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b1000000-0000-4000-8000-000000000001', id, 2, precio_centavos
FROM producto_cache WHERE id = 4 AND disponible = 1 AND eliminado = 0;   -- Gaseosa 500 ml x2

INSERT INTO cola_sync (solicitud_uuid, id_local)
VALUES ('51000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001');
COMMIT;

SELECT b.id_local, b.usuario, b.forma_pago, i.producto_id, i.cantidad, i.precio_centavos_visto,
       c.solicitud_uuid, c.estado
FROM pedido_borrador b
JOIN item_borrador i ON i.id_local = b.id_local
JOIN cola_sync c     ON c.id_local = b.id_local
WHERE b.id_local = 'b1000000-0000-4000-8000-000000000001';

-- ---------------------------------------------------------------------
.print '== 1b. Otra operación deshecha con ROLLBACK (el vendedor cancela el borrador)'
-- ---------------------------------------------------------------------
SELECT (SELECT count(*) FROM pedido_borrador) AS borradores_antes,
       (SELECT count(*) FROM item_borrador)   AS items_antes;
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b1000000-0000-4000-8000-000000000002', 'vendedor_feria_01', 'TARJETA');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT 'b1000000-0000-4000-8000-000000000002', id, 3, precio_centavos
FROM producto_cache WHERE id = 1 AND disponible = 1 AND eliminado = 0;
SELECT (SELECT count(*) FROM pedido_borrador) AS borradores_dentro_de_la_tx,
       (SELECT count(*) FROM item_borrador)   AS items_dentro_de_la_tx;
ROLLBACK;
SELECT (SELECT count(*) FROM pedido_borrador) AS borradores_despues,
       (SELECT count(*) FROM item_borrador)   AS items_despues;

-- ---------------------------------------------------------------------
.print '== 2. Caso C1: catálogo disponible, sin conectarse al servidor'
-- ---------------------------------------------------------------------
-- Sólo lee producto_cache: no hay conexión a PostgreSQL en ningún paso.
SELECT id, nombre, printf('%.2f', precio_centavos / 100.0) AS precio, stock_visto, copiado_en
FROM producto_cache
WHERE disponible = 1 AND eliminado = 0
ORDER BY nombre;

-- ---------------------------------------------------------------------
.print '== 3. Caso C7: cantidad 0 y producto inexistente dan error y no dejan filas'
-- ---------------------------------------------------------------------
SELECT (SELECT count(*) FROM pedido_borrador) AS borradores_antes,
       (SELECT count(*) FROM item_borrador)   AS items_antes,
       (SELECT count(*) FROM cola_sync)       AS solicitudes_antes;

.print '-- 3a. cantidad 0 (CHECK cantidad > 0): se espera error'
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b7000000-0000-4000-8000-000000000001', 'vendedor_feria_01', 'EFECTIVO');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('b7000000-0000-4000-8000-000000000001', 3, 0, 1200000);
ROLLBACK;   -- lo que hace la app ante cualquier error: no queda ni la cabecera

.print '-- 3b. producto 999 que no existe (FOREIGN KEY): se espera error'
BEGIN;
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b7000000-0000-4000-8000-000000000002', 'vendedor_feria_01', 'EFECTIVO');
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('b7000000-0000-4000-8000-000000000002', 999, 1, 100000);
ROLLBACK;

.print '-- 3c. lo mismo sin transacción, sobre el borrador ya guardado: se esperan dos errores'
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('b1000000-0000-4000-8000-000000000001', 6, 0, 350000);
INSERT INTO item_borrador (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES ('b1000000-0000-4000-8000-000000000001', 999, 1, 100000);

SELECT (SELECT count(*) FROM pedido_borrador) AS borradores_despues,
       (SELECT count(*) FROM item_borrador)   AS items_despues,
       (SELECT count(*) FROM cola_sync)       AS solicitudes_despues;

.print '-- 3d. y las otras reglas del esquema: forma de pago y estado fuera de dominio'
INSERT INTO pedido_borrador (id_local, usuario, forma_pago)
VALUES ('b7000000-0000-4000-8000-000000000003', 'vendedor_feria_01', 'CHEQUE');
INSERT INTO cola_sync (solicitud_uuid, id_local, estado)
VALUES ('57000000-0000-4000-8000-000000000003', 'b1000000-0000-4000-8000-000000000001', 'APROBADO');
SELECT count(*) AS borradores_finales FROM pedido_borrador;
