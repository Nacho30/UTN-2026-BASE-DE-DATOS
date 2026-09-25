# spec: indice_pedido_producto_precio

Objetivo: acelerar el reporte de líneas de venta de productos "premium"
(precio_unitario por encima de un umbral), usado para reportes de
ventas de alta gama.

Consulta afectada:
```sql
SELECT id_pedido, id_producto, cantidad, precio_unitario
FROM pedido_producto
WHERE precio_unitario > :umbral;
```

Columnas candidatas: `precio_unitario` (selectividad media, ~11% para
el umbral de prueba de 4500; no se conoce un umbral fijo de antemano,
así que no corresponde un índice parcial con un valor constante).

Criterio de aceptación: el plan pasa de Seq Scan a Bitmap Heap Scan y
el tiempo mejora de forma medible (no necesariamente un orden de
magnitud completo, dado que la selectividad no es tan alta como en los
otros dos casos).
