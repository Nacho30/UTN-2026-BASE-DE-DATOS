-- =====================================================================
-- TP U8 · servidor/verificacion_final.sql  (consigna 2.c, cierre)
-- Muestra que la simulación no tocó PostgreSQL. Sólo lectura.
-- Correr desde food-store-tp-u8/:  psql -X -d copia_trabajo -f servidor/verificacion_final.sql
-- =====================================================================
\echo '== Pedidos y líneas: los mismos 4 y 6 de datos_iniciales.sql (la tablet no crea pedidos)'
SELECT (SELECT count(*) FROM pedido)          AS pedidos,
       (SELECT count(*) FROM pedido_producto) AS lineas,
       (SELECT max(id_pedido) FROM pedido)    AS ultimo_id_pedido;

\echo '== El servidor hoy es idéntico a la última instantánea exportada (antes de C5 y C6)'
\echo '   aunque después de exportarla el semáforo dio SIMULADO_APROBADO: nada se descontó'
CREATE TEMP TABLE ultima_snapshot (
    id bigint, nombre text, precio_centavos bigint, stock int,
    disponible boolean, eliminado boolean, fecha_snapshot text);
\copy ultima_snapshot FROM 'movil/servidor_snapshot.csv' CSV HEADER
SELECT 'en el servidor y no en la instantánea' AS diferencia, *
FROM (SELECT id, nombre, precio_centavos, stock, disponible, eliminado FROM v_snapshot_movil
      EXCEPT
      SELECT id, nombre, precio_centavos, stock, disponible, eliminado FROM ultima_snapshot) a
UNION ALL
SELECT 'en la instantánea y no en el servidor', *
FROM (SELECT id, nombre, precio_centavos, stock, disponible, eliminado FROM ultima_snapshot
      EXCEPT
      SELECT id, nombre, precio_centavos, stock, disponible, eliminado FROM v_snapshot_movil) b;

\echo '== Stock y precio actuales (sólo cambiaron los tres datos preparados a mano en C2, C3 y C4)'
SELECT id_producto, nombre, precio, stock, activo FROM producto ORDER BY id_producto;
