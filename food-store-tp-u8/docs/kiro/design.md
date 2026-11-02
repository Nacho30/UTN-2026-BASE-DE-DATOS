# Design Document — Food Store en la feria

## Overview

Dos motores y un archivo de intercambio:

```
PostgreSQL (copia_trabajo)            CSV                       SQLite (tablet)
 producto, categoria ──► v_snapshot_movil ──\copy──► servidor_snapshot.csv ──.import──► snapshot_servidor
                                                                                     │
                                                                  cargar_snapshot.sql ▼
                                                                               producto_cache
                                                     pedido_borrador ◄── item_borrador
                                                            ▲
                                                        cola_sync ◄── semaforo.sql (compara con snapshot_servidor)
```

El flujo es de un solo sentido: del servidor a la tablet viajan datos; de la tablet al servidor no viaja nada en este TP (la sincronización se **simula**).

## Components

### Servidor (PostgreSQL)
- `v_snapshot_movil`: una fila por producto, **incluidos los dados de baja** (lápidas), con `id, nombre, precio_centavos, stock, disponible, eliminado, fecha_snapshot`.
  - `precio_centavos = (precio * 100)::bigint`: exacto porque `precio` es `NUMERIC(10,2)`.
  - `disponible = producto.activo AND categoria.activo AND stock > 0`.
  - `eliminado = NOT producto.activo` (baja lógica, R7).
- Exportación con `\copy ... CSV HEADER`; los booleanos salen como `t` / `f`.

### Tablet (SQLite 3.37+, tablas `STRICT`)
- `snapshot_servidor`: copia cruda del CSV (booleanos como texto `t`/`f`), se vacía antes de cada importación.
- `producto_cache`: catálogo local en centavos; se carga con *upsert* desde `snapshot_servidor`. Nunca se borra una fila: las bajas llegan como `eliminado = 1`, y los productos que el servidor dejó de informar quedan `disponible = 0`.
- `pedido_borrador` (UUID local, alias de vendedor, forma de pago) → `item_borrador` (FK a borrador y a `producto_cache`, `cantidad > 0`, precio visto) → `cola_sync` (UUID de solicitud como PK, estado y motivo).
- `PRAGMA foreign_keys = ON` en **cada** script: en SQLite es por conexión.

### Semáforo (`semaforo.sql`)
Un único `UPDATE ... FROM` sobre las solicitudes `PENDIENTE`, agrupando por solicitud con `LEFT JOIN item_borrador → snapshot_servidor`:

| Color | Estado | Condición (algún ítem) |
|---|---|---|
| Rojo | `RECHAZADO` | no existe en la instantánea, `eliminado = 't'`, `disponible = 'f'`, `cantidad > stock`, o borrador sin ítems |
| Amarillo | `CONFLICTO` | sin rojo, y `precio_centavos_visto <> precio_centavos` |
| Verde | `SIMULADO_APROBADO` | todo coincide |

No corre si `snapshot_servidor` está vacía (evita rechazar todo por una importación fallida).

## Data integrity decisions
- Montos en centavos enteros: sin redondeo binario en la tablet.
- Una vez evaluada, una solicitud no cambia de estado (trigger `trg_cola_sync_estado_final`): el resultado queda como historial; un reintento es otra solicitud.
- La tablet **no** valida stock al armar el borrador: el stock que ve es viejo y la decisión es del servidor.

## Protección real en producción (fuera del TP)
El servidor guardaría el `solicitud_uuid` en una tabla con `UNIQUE` y lo insertaría **en la misma transacción** que crea el pedido (`INSERT ... ON CONFLICT DO NOTHING`); si ya existía, devuelve el resultado anterior sin volver a vender.
