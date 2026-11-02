-- Food Store — TP Unidad 8 · servidor/exportar_snapshot.sql
-- Exporta la instantánea a movil/servidor_snapshot.csv. Correr desde la
-- carpeta food-store-tp-u8/ (la ruta de \copy es relativa a donde corre psql):
--   psql -X -d copia_trabajo -f servidor/exportar_snapshot.sql
\copy (SELECT * FROM v_snapshot_movil ORDER BY id) TO 'movil/servidor_snapshot.csv' CSV HEADER
