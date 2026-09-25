# spec: indice_producto_nombre_vig

Objetivo: acelerar la búsqueda de un producto vigente por nombre exacto
(catálogo y checkout).

Consulta afectada:
```sql
SELECT id_producto, nombre, precio
FROM producto
WHERE nombre = :nombre AND activo = true;
```

Columnas candidatas: `nombre` (alta selectividad, nombres
prácticamente únicos), `activo` (filtro de vigencia — condición
parcial, el catálogo público nunca busca productos dados de baja).

Criterio de aceptación: el plan pasa de Seq Scan a Index Scan y el
tiempo baja al menos un orden de magnitud.
