# spec: indice_pedido_forma_pago (DESCARTADO — sobreindexación)

Objetivo original propuesto por la IA: acelerar un listado de pedidos
filtrado por forma de pago.

Consulta:
```sql
SELECT id_pedido, fecha FROM pedido WHERE forma_pago = :forma_pago;
```

Columna candidata: `forma_pago` (ENUM de 3 valores sobre 200.002 filas,
~66.667 filas por valor — baja cardinalidad, sin condición parcial que
la reduzca).

Criterio de aceptación que se le pidió a la propuesta: el plan debía
pasar de Seq Scan a Index/Bitmap Scan con una mejora real medible. **No
se cumplió**: medido, el plan pasó a Bitmap Heap Scan pero el tiempo no
mejoró (17.819 ms → 18.031 ms, prácticamente igual, incluso levemente
peor) porque el Recheck del Bitmap Heap Scan termina leyendo casi los
mismos bloques que un Seq Scan cuando cada valor cubre ~33% de la
tabla. Se descartó por sobreindexación: el índice no aporta valor de
lectura y sí tiene costo de mantenimiento en cada INSERT/UPDATE de
`pedido`. Detalle completo de la medición en
`informe_mediciones.md`.
