-- Pruebas de 002 y de la corrección de sp_registrar_pedido (Food Store, TP U8).
-- Todo dentro de BEGIN ... ROLLBACK; cada caso inválido en un SAVEPOINT.
--   psql -X -d copia_trabajo -f pruebas/002_pruebas_lineas_inmutables.sql
BEGIN;

\echo '-- 002: cambiar la cantidad de una línea (se espera error)'
SAVEPOINT s1;
UPDATE pedido_producto SET cantidad = 40 WHERE id_pedido = 4 AND id_producto = 6;
ROLLBACK TO SAVEPOINT s1;

\echo '-- 002: pasar la línea a un producto dado de baja (se espera error)'
SAVEPOINT s2;
UPDATE pedido_producto SET id_producto = 7 WHERE id_pedido = 2 AND id_producto = 3;
ROLLBACK TO SAVEPOINT s2;

\echo '-- 002: cancelar un pedido sigue funcionando (DELETE en cascada no se bloquea)'
SELECT stock AS stock_flan_antes FROM producto WHERE id_producto = 6;
CALL sp_cancelar_pedido(4);
SELECT stock AS stock_flan_despues, (SELECT count(*) FROM pedido_producto WHERE id_pedido = 4) AS lineas_pedido_4
FROM producto WHERE id_producto = 6;

\echo '-- sp_registrar_pedido con un producto inexistente (se espera error y ningún pedido nuevo)'
SELECT count(*) AS pedidos_antes FROM pedido;
SAVEPOINT s3;
CALL sp_registrar_pedido(1, 'EFECTIVO', '[{"id_producto": 4, "cantidad": 1}, {"id_producto": 999, "cantidad": 3}]');
ROLLBACK TO SAVEPOINT s3;
SELECT count(*) AS pedidos_despues FROM pedido;

\echo '-- sp_registrar_pedido con productos válidos sigue funcionando'
CALL sp_registrar_pedido(1, 'EFECTIVO', '[{"id_producto": 4, "cantidad": 1}]');
SELECT p.id_pedido, count(pp.id_producto) AS lineas
FROM pedido p JOIN pedido_producto pp USING (id_pedido)
GROUP BY p.id_pedido ORDER BY p.id_pedido DESC LIMIT 1;

ROLLBACK;
