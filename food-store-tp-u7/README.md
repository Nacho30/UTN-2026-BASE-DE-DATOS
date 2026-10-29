# Food Store — TP Unidad 7: NoSQL y nuevas formas de almacenamiento

Bases de Datos II · Tecnicatura Universitaria en Programación · UTN · 2026
Alumno: Ignacio Martín Rodríguez

Subconjunto «pedidos y detalle de pedidos» de Food Store migrado de PostgreSQL 16 a una colección documental de MongoDB (`foodstore_nosql.pedidos`), con consultas comparadas en ambos motores.

## Entregables

| Archivo | Contenido |
|---|---|
| [`docs/informe_u7.pdf`](docs/informe_u7.pdf) | Informe (4 páginas): modelo, migración, consultas, tabla de verificación, contraste de IA y conclusión |
| [`consultas_mongodb.js`](consultas_mongodb.js) | Colección con validador `$jsonSchema`, `insertMany()` de 6 pedidos, verificaciones y consultas a–d |
| [`consultas_postgresql.sql`](consultas_postgresql.sql) | Equivalentes de b) y c) (más a y d) en PostgreSQL |
| [`sql/01_estado_y_pedidos_prueba.sql`](sql/01_estado_y_pedidos_prueba.sql) | Agrega `pedido.estado` (el esquema real no lo tenía) y los pedidos de prueba 5 y 6 |
| [`sql/02_exportar_pedidos_json.sql`](sql/02_exportar_pedidos_json.sql) + [`scripts/generar_insertmany.py`](scripts/generar_insertmany.py) | Generan los documentos desde PostgreSQL |
| [`sql/03_contraste_ia.sql`](sql/03_contraste_ia.sql) | Evidencia de laboratorio para la consigna 7 |
| [`docs/ia/consulta_ia.md`](docs/ia/consulta_ia.md) | Prompt y respuesta resumida de la IA (consigna 6) |
| [`docs/evidencia/`](docs/evidencia/) | Salidas reales de ejecución |

## Cómo reproducir

```bash
createdb foodstore
for f in ../schema.sql ../migraciones/001_restricciones_reglas_negocio.sql \
         ../programables/funciones_procedimientos.sql ../datos_iniciales.sql \
         sql/01_estado_y_pedidos_prueba.sql; do
  psql -X -v ON_ERROR_STOP=1 -d foodstore -f "$f"; done

psql -X -d foodstore -f consultas_postgresql.sql > docs/evidencia/02_consultas_postgresql.txt
psql -X -d foodstore -f sql/03_contraste_ia.sql  > docs/evidencia/03_contraste_ia_postgresql.txt

# Regenerar el insertMany (opcional, ya está en consultas_mongodb.js)
psql -X -At -d foodstore -f sql/02_exportar_pedidos_json.sql > docs/pedidos_export.jsonl
python3 scripts/generar_insertmany.py docs/pedidos_export.jsonl

# MongoDB
mongosh "mongodb://localhost:27017" --file consultas_mongodb.js > docs/evidencia/04_salida_mongodb.txt

python3 docs/generar_informe.py   # toma la salida de MongoDB si existe
```
