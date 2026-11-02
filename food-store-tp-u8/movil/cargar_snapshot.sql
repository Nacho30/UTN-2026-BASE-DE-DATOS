PRAGMA foreign_keys = ON;
-- =====================================================================
-- Food Store — TP Unidad 8 · movil/cargar_snapshot.sql   (consigna 2.a)
-- Importa servidor_snapshot.csv en snapshot_servidor y actualiza el
-- catálogo local. Correr desde la carpeta movil/:
--   sqlite3 foodstore_movil.db < cargar_snapshot.sql
-- =====================================================================
DELETE FROM snapshot_servidor;
.import --csv --skip 1 servidor_snapshot.csv snapshot_servidor

BEGIN;

-- Upsert: altas y cambios de precio, stock, disponibilidad o baja.
INSERT INTO producto_cache (id, nombre, precio_centavos, stock_visto, disponible, eliminado, copiado_en)
SELECT id, nombre, precio_centavos, stock,
       disponible = 't', eliminado = 't', fecha_snapshot
FROM snapshot_servidor
WHERE true                         -- requerido por SQLite para un upsert desde SELECT
ON CONFLICT (id) DO UPDATE SET
    nombre          = excluded.nombre,
    precio_centavos = excluded.precio_centavos,
    stock_visto     = excluded.stock_visto,
    disponible      = excluded.disponible,
    eliminado       = excluded.eliminado,
    copiado_en      = excluded.copiado_en;

-- Productos que el servidor ya no informa (por ejemplo, tras restaurar un
-- respaldo viejo): no se borran, porque los borradores los referencian;
-- se dejan sin vender. Sólo si la importación trajo filas.
UPDATE producto_cache
SET disponible = 0,
    copiado_en = (SELECT max(fecha_snapshot) FROM snapshot_servidor)
WHERE NOT EXISTS (SELECT 1 FROM snapshot_servidor s WHERE s.id = producto_cache.id)
  AND EXISTS (SELECT 1 FROM snapshot_servidor);

COMMIT;

.print 'Instantánea cargada:'
SELECT count(*) AS filas_snapshot, max(fecha_snapshot) AS fecha_de_la_copia FROM snapshot_servidor;
SELECT id, nombre, precio_centavos, stock_visto, disponible, eliminado, copiado_en
FROM producto_cache ORDER BY id;
