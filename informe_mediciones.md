# Informe de mediciones — Unidad 3 / Semana 1 (índices, vistas y vista materializada)

Todo lo que sigue se corrió de verdad contra PostgreSQL 16, sobre la
base `food_store` tal como quedó al cierre de la Semana 4 (50.005
productos, 20.003 clientes, 200.002 pedidos, 499.403 líneas de
`pedido_producto`), con los índices previos ya creados
(`idx_pedido_cliente`, `idx_pedido_fecha`, `idx_producto_categoria`,
`idx_producto_stock_bajo`, `idx_pedido_producto_producto`). No hay
números simulados: cada plan y cada tiempo de esta sección es la
salida real de `EXPLAIN ANALYZE`.

## Parte A — Índices

### Índice 1 — `idx_cliente_apellido` (búsqueda de cliente por apellido)

```sql
CREATE INDEX idx_cliente_apellido ON cliente (apellido) WHERE activo = true;
```

| | Plan | Tiempo real |
|---|---|---|
| Antes | `Seq Scan on cliente` — Filter: `activo AND apellido = ...`, Rows Removed by Filter: 20.002 | 4.194 ms |
| Después | `Index Scan using idx_cliente_apellido` — Index Cond: `apellido = ...` | 0.065 ms |

**Mejora real: ~64.5x.**

### Índice 2 — `idx_producto_nombre_vig` (búsqueda de producto por nombre)

```sql
CREATE INDEX idx_producto_nombre_vig ON producto (nombre) WHERE activo = true;
```

| | Plan | Tiempo real |
|---|---|---|
| Antes | `Seq Scan on producto` — Filter: `activo AND nombre = ...`, Rows Removed by Filter: 50.004 | 3.679 ms |
| Después | `Index Scan using idx_producto_nombre_vig` — Index Cond: `nombre = ...` | 0.063 ms |

**Mejora real: ~58.4x.**

### Índice 3 — `idx_pedido_producto_precio` (líneas de venta premium)

```sql
CREATE INDEX idx_pedido_producto_precio ON pedido_producto (precio_unitario);
```

| | Plan | Tiempo real |
|---|---|---|
| Antes | `Seq Scan on pedido_producto` — Filter: `precio_unitario > 4500`, Rows Removed by Filter: 442.717 | 79.516 ms |
| Después | `Bitmap Heap Scan` + `Bitmap Index Scan on idx_pedido_producto_precio` | 21.346 ms |

**Mejora real: ~3.7x.** Es la mejora más modesta de las tres porque la
selectividad del filtro (~11%, 56.686 de 499.403 filas) obliga al
Bitmap Heap Scan a visitar 3.672 de los 3.673 bloques de la tabla:
igual se lee casi toda la tabla, solo que ordenada por punteros del
índice en vez de secuencialmente, así que la ganancia viene de evitar
la evaluación del `Filter` fila por fila, no de leer menos bloques.

### Propuesta descartada por sobreindexación — `idx_pedido_forma_pago`

```sql
-- NO incluido en indices.sql — propuesta rechazada
CREATE INDEX idx_pedido_forma_pago ON pedido (forma_pago);
```

`forma_pago` es un ENUM de 3 valores sobre 200.002 pedidos
(EFECTIVO=66.697, TARJETA=66.555, TRANSFERENCIA=66.750 — prácticamente
un tercio cada uno). Medido antes/después:

| | Plan | Tiempo real |
|---|---|---|
| Antes | `Seq Scan on pedido` — Filter: `forma_pago = 'TRANSFERENCIA'` | 17.819 ms |
| Después (con el índice) | `Bitmap Heap Scan` + `Bitmap Index Scan on idx_pedido_forma_pago` | 18.031 ms |

**Sin mejora real** (de hecho, levemente peor: el Bitmap Index Scan
agrega su propio costo de lectura sin ahorrar nada en el Heap Scan,
porque igual hay que revisar prácticamente todos los bloques de la
tabla). Se descartó: es exactamente el caso de sobreindexación que
anticipa la consigna — columna de baja cardinalidad sin condición
parcial —, y un índice así solo agrega costo de mantenimiento en cada
escritura sin aportar nada en la lectura. Ver `specs/indice_pedido_forma_pago_DESCARTADO.md`.

### Costo de los índices sobre la escritura

Se midió el tiempo real de `INSERT` de 500 líneas nuevas en
`pedido_producto` (dentro de `BEGIN; ... ROLLBACK;`, para no alterar
los datos), bajo tres estados de índices **sobre esa misma tabla**
(los 3 índices nuevos de esta semana quedaron en `producto`, `cliente`
y `pedido_producto.precio_unitario` — solo el último vive en
`pedido_producto`, así que la comparación más honesta del costo de
escritura es contra el índice que sí está en la tabla que se escribe,
incluyendo el heredado de la Semana 3):

| Estado de índices en `pedido_producto` | Tiempo real (500 INSERT) | Buffers dirtied / written |
|---|---|---|
| Solo PK (sin índices secundarios) | 7.125 ms | 12 / 5 |
| + `idx_pedido_producto_producto` (Semana 3) | 7.579 ms | 13 / 6 |
| + `idx_pedido_producto_precio` (esta semana) | 10.596 ms | 134 / 7 |

El costo de escritura es real y creciente: cada índice adicional
obliga al motor a mantener también su propio árbol B-tree en cada
`INSERT`, no solo la tabla. Con 2 índices secundarios el tiempo de
insertar 500 filas casi se duplica frente a no tener ninguno (de
7.125 ms a 10.596 ms), y el salto más grande de páginas sucias
(`dirtied`) se da justo al sumar el segundo índice. Ningún índice del
plan aceptado esta semana vive en `producto`/`cliente`
(`idx_cliente_apellido`, `idx_producto_nombre_vig`), así que no
agregan costo de escritura a `pedido_producto`; si se insertaran filas
en `cliente` o `producto` sí pagarían un costo equivalente por esos
índices.

## Parte B — Vistas

Las 4 vistas (`vista_producto_vigente`, `vista_pedido_cliente`,
`vista_detalle_pedido`, `vista_cliente_publico`) se verificaron contra
su consulta manual equivalente con `EXCEPT` en ambos sentidos:

| Vista | vista EXCEPT manual | manual EXCEPT vista |
|---|---|---|
| vista_producto_vigente | 0 | 0 |
| vista_pedido_cliente | 0 | 0 |
| vista_detalle_pedido | 0 | 0 |
| vista_cliente_publico | 0 | 0 |

Las 4 son formalmente equivalentes a su consulta manual. Detalle de la
verificación de `vista_cliente_publico` (la vista de seguridad): se
confirmó con `\d vista_cliente_publico` que las columnas expuestas son
`id_cliente, nombre, apellido, activo, fecha_alta`, y que **no**
aparecen `email` ni `telefono` — las dos columnas de contacto directo
que se ocultan a propósito (ver justificación de la adaptación en
`specs/vistas_reportes.md`).

## Parte C — Vista materializada

```sql
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS ... WITH DATA;
CREATE UNIQUE INDEX idx_mv_facturacion_categoria_mes
    ON mv_facturacion_categoria_mes (id_categoria, mes);
```

| | Tiempo real |
|---|---|
| Consulta original (4 JOIN + agregación, sin materializar) | 1.578,513 ms |
| Consulta contra la vista materializada (`Seq Scan` sobre 125 filas ya agregadas) | 0.178 ms |

**Mejora real: ~8.868x.** Verificado con `EXCEPT` en ambos sentidos
(0 filas de diferencia) que el contenido de la vista materializada
coincide exactamente con la consulta original.

### Frecuencia de refresco recomendada

El reporte de facturación por categoría y mes se usa para tableros
gerenciales que se consultan varias veces al día pero no necesitan el
dato al segundo: un `REFRESH MATERIALIZED VIEW CONCURRENTLY
mv_facturacion_categoria_mes` **una vez por hora** (por ejemplo, vía
`cron` o un job programado) es razonable: mantiene el reporte con una
desviación máxima de una hora contra la facturación real, y el costo
de recalcularlo (equivalente a la consulta original, ~1.58 s) es
insignificante corrido una vez por hora contra la carga total del
servidor. Se eligió `CONCURRENTLY` (habilitado por el índice único
`idx_mv_facturacion_categoria_mes`) específicamente para que el
refresco no bloquee las lecturas del tablero mientras se recalcula —
sin `CONCURRENTLY`, `REFRESH MATERIALIZED VIEW` toma un lock exclusivo
que deja la vista materializada illegible durante el recálculo.

Qué implica para los usuarios: entre un refresco y el siguiente, el
tablero puede no reflejar pedidos de la última hora. Para el caso de
uso (reporte gerencial de facturación mensual/por categoría, no un
panel operativo en tiempo real) esa demora es aceptable; si en el
futuro se necesitara ver la facturación al minuto, la vista
materializada dejaría de ser la herramienta correcta y habría que
volver a la consulta directa (o a un refresco mucho más frecuente,
evaluando entonces si el costo de recalcular cada pocos minutos
compensa contra consultarla sin materializar).
