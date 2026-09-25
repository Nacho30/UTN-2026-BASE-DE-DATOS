# Unidad 3 / Semana 1 — Índices, vistas y vista materializada

Cómo reproducir las pruebas de este trabajo.

## Requisitos

- PostgreSQL 16+.
- Base `food_store` ya creada con `schema.sql`, poblada masivamente
  como quedó al cierre de la Semana 4 (`optimizacion/carga_masiva.sql`)
  y con los índices de las Semanas 3 y 4 ya aplicados.

## 1. Aplicar los índices de esta semana

```bash
psql -h localhost -U postgres -d food_store -f indices.sql
```

Crea `idx_cliente_apellido`, `idx_producto_nombre_vig` e
`idx_pedido_producto_precio`. **No** crea `idx_pedido_forma_pago`: esa
propuesta se descartó por sobreindexación (ver `duia.md` e
`informe_mediciones.md`).

## 2. Aplicar las vistas y la vista materializada

```bash
psql -h localhost -U postgres -d food_store -f views.sql
```

Crea las 4 vistas de la Parte B (`vista_producto_vigente`,
`vista_pedido_cliente`, `vista_detalle_pedido`,
`vista_cliente_publico`) y la vista materializada de la Parte C
(`mv_facturacion_categoria_mes`) con su índice único.

## 3. Reproducir las mediciones de antes/después

Cada consulta de `informe_mediciones.md` se puede repetir con
`EXPLAIN (ANALYZE, BUFFERS)` sobre la consulta correspondiente, antes y
después de `indices.sql` (se puede volver al estado "antes" con
`DROP INDEX <nombre>;`).

Ejemplo (índice 1):

```sql
-- antes
DROP INDEX idx_cliente_apellido;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_cliente, nombre, apellido, email FROM cliente
WHERE apellido = 'Apellido15981' AND activo = true;

-- después
CREATE INDEX idx_cliente_apellido ON cliente (apellido) WHERE activo = true;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id_cliente, nombre, apellido, email FROM cliente
WHERE apellido = 'Apellido15981' AND activo = true;
```

## 4. Reproducir el benchmark de escritura

El benchmark de costo de escritura (Parte A, punto 5) inserta 500 filas
de prueba en `pedido_producto` dentro de una transacción que se
revierte, así que no altera los datos:

```sql
\timing on
BEGIN;
INSERT INTO pedido (fecha, forma_pago, id_cliente)
SELECT now(), 'EFECTIVO', 1 FROM generate_series(1, 500);

EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario)
SELECT p.id_pedido, 1 + ((p.id_pedido) % 50005), 1 + (p.id_pedido % 5),
       100.00 + (p.id_pedido % 900)
FROM pedido p
WHERE p.id_cliente = 1 AND p.fecha > now() - interval '5 seconds';

ROLLBACK;
```

Repetir bajo distintos estados de índices sobre `pedido_producto`
(`DROP`/`CREATE` de `idx_pedido_producto_producto` e
`idx_pedido_producto_precio` entre corridas) para reproducir la tabla
de costos de `informe_mediciones.md`.

## 5. Verificar la equivalencia de las vistas

```bash
psql -h localhost -U postgres -d food_store -f verificacion_vistas.sql
```

(script auxiliar, no forma parte de los objetos finales — compara cada
vista contra su consulta manual equivalente con `EXCEPT` en ambos
sentidos; debe devolver 0 en todas las filas).

## 6. Refrescar la vista materializada

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
```

Frecuencia recomendada y justificación: ver la sección final de
`informe_mediciones.md`.

## Estructura de esta entrega

```
indices.sql               (Parte A — CREATE INDEX aceptados, comentados)
views.sql                 (Partes B y C — vistas + vista materializada)
specs/                    (especificaciones, rol de Kiro)
duia.md                   (bitácora de uso de IA)
informe_mediciones.md     (EXPLAIN ANALYZE antes/después, lectura y escritura)
README_U3S1.md            (este archivo)
```
