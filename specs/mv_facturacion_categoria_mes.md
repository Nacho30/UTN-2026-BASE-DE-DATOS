# spec: mv_facturacion_categoria_mes (Parte C)

Objetivo: materializar el reporte de facturación por categoría y mes
(reporte agregado costoso ya identificado como QA en el TP4 — Unidad
2, Semana 4 — donde una versión sin materializar tarda del orden de
1.5 segundos sobre la base masiva).

Consulta base:
```sql
SELECT c.id_categoria, c.nombre AS categoria,
       date_trunc('month', p.fecha) AS mes,
       SUM(pp.cantidad * pp.precio_unitario) AS facturacion,
       COUNT(DISTINCT p.id_pedido) AS cantidad_pedidos
FROM categoria c
JOIN producto pr ON pr.id_categoria = c.id_categoria
JOIN pedido_producto pp ON pp.id_producto = pr.id_producto
JOIN pedido p ON p.id_pedido = pp.id_pedido
WHERE c.activo = true
GROUP BY c.id_categoria, c.nombre, date_trunc('month', p.fecha);
```

Requisitos:
- `WITH DATA` (la vista se crea ya poblada, no vacía).
- Índice único sobre `(id_categoria, mes)` — es la clave natural del
  reporte (una fila por categoría y mes) y habilita
  `REFRESH MATERIALIZED VIEW CONCURRENTLY` a futuro.

Criterio de aceptación: el resultado de la vista materializada debe
coincidir exactamente con la consulta base (verificación con `EXCEPT`
en ambos sentidos), y el tiempo de consulta contra la vista
materializada debe ser sustancialmente menor que el de la consulta
original sin materializar.
