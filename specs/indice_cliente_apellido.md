# spec: indice_cliente_apellido

Objetivo: acelerar la búsqueda de un cliente vigente por apellido
(pantalla de atención al cliente).

Consulta afectada:
```sql
SELECT id_cliente, nombre, apellido, email
FROM cliente
WHERE apellido = :apellido AND activo = true;
```

Columnas candidatas: `apellido` (alta selectividad, prácticamente un
apellido por cliente en los datos de prueba), `activo` (filtro de
vigencia, baja selectividad — no va como columna de índice sino como
condición parcial).

Criterio de aceptación: el plan pasa de Seq Scan a Index Scan y el
tiempo baja al menos un orden de magnitud.
