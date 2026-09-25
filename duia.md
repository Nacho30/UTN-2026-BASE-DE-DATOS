# DUIA — Unidad 3 / Semana 1 (índices, vistas y vista materializada)

Proyecto Food Store — PostgreSQL 16. Salidas reales del motor sobre la
base masiva heredada de la Semana 4 (50.005 productos, 20.003 clientes,
200.002 pedidos, 499.403 líneas de `pedido_producto`). Herramientas
declaradas en la consigna: Kiro (especificación) y OpenCode (agente de
codificación en terminal). Este entorno usó Claude (Anthropic) en su
lugar para ambos roles, igual que se declaró en `duia_parte1.md`,
`duia_tp3.md` y `duia_tp4.md` de las entregas anteriores: los archivos
de `specs/` cumplen el rol de las specs de Kiro (especificar antes de
generar), y la generación + ejecución del SQL cumple el rol de
OpenCode.

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| Claude (rol Kiro: especificar) | Redactar la spec de 3 candidatos a índice a partir de `queries.sql`/consultas de negocio | Se pidió identificar consultas que hoy resuelven con Seq Scan sobre una tabla considerable, con columnas de filtro, frecuencia y criterio de aceptación (ver `specs/indice_*.md`) | Se aceptaron las 3 specs tal cual, usadas después como contexto para generar los índices. |
| Claude (rol OpenCode: generar) | Proponer el índice concreto (tipo, columnas, parcial o no) para cada una de las 3 specs | "A partir de esta spec, proponé el CREATE INDEX adecuado" | Se aceptaron las 3 propuestas (`idx_cliente_apellido`, `idx_producto_nombre_vig` — ambas parciales `WHERE activo = true` — e `idx_pedido_producto_precio`, simple). Verificadas con EXPLAIN ANALYZE antes/después: mejoras reales de 64.5x, 58.4x y 3.7x respectivamente (ver `informe_mediciones.md`). |
| Claude (rol OpenCode: generar) | Proponer un 4° índice, sobre `pedido.forma_pago`, para un listado de pedidos por forma de pago | "Esta consulta también resuelve con Seq Scan, proponé un índice" | **Descartado por sobreindexación.** Se midió antes de descartarlo (no se rechazó a ciegas): `forma_pago` es un ENUM de 3 valores con ~33% de las filas cada uno; el índice cambió el plan a Bitmap Heap Scan pero el tiempo no mejoró (17.819 ms → 18.031 ms). Se documentó como el caso de sobreindexación exigido por la consigna. Ver `specs/indice_pedido_forma_pago_DESCARTADO.md`. |
| Claude (rol OpenCode: generar) | Medir el costo de escritura de los índices nuevos | "Diseñá un benchmark de INSERT en pedido_producto que compare el costo con distintos índices presentes, sin alterar los datos reales" | Se aceptó el enfoque de `BEGIN; INSERT ...; ROLLBACK;` con `EXPLAIN (ANALYZE, BUFFERS)`, corrido bajo 3 estados de índices sobre `pedido_producto`. Resultado real: el tiempo de insertar 500 filas sube de 7.125 ms (sin índices secundarios) a 10.596 ms (con los 2 índices que sí viven en esa tabla) — ver `informe_mediciones.md`. |
| Claude (rol Kiro: especificar) | Redactar la spec de las 4 vistas de la Parte B, incluida la de seguridad | Columnas a exponer, filtro de vigencia por tabla, y qué columna ocultar por seguridad (ver `specs/vistas_reportes.md`) | Se aceptó la spec, incluyendo la decisión de adaptar "ocultar contraseña" a "ocultar email/teléfono" porque este esquema no tiene columna de autenticación — documentado explícitamente como adaptación, no como omisión. |
| Claude (rol OpenCode: generar) | Generar las 4 vistas a partir de la spec | Spec de `vistas_reportes.md`, sin mostrar una solución previa | Se aceptaron las 4 (`vista_producto_vigente`, `vista_pedido_cliente`, `vista_detalle_pedido`, `vista_cliente_publico`). **Verificación de equivalencia**: cada una se contrastó contra una consulta manual equivalente escrita aparte, con `EXCEPT` en ambos sentidos — las 4 dieron 0 filas de diferencia en ambos sentidos (ver `informe_mediciones.md` para la tabla completa y `views.sql`/`informe_mediciones.md` para el detalle de `vista_cliente_publico`, que se verificó además inspeccionando con `\d` que `email` y `telefono` no aparecen entre sus columnas). |
| Claude (rol Kiro + OpenCode) | Elegir y construir la vista materializada de la Parte C | Spec en `specs/mv_facturacion_categoria_mes.md`, reutilizando la consulta de facturación por categoría/mes ya identificada como reporte costoso en el TP4 (Unidad 2, Semana 4) | Se aceptó `mv_facturacion_categoria_mes` con `WITH DATA` y un índice único `(id_categoria, mes)` para habilitar `REFRESH CONCURRENTLY`. Verificada con `EXCEPT` (0 filas de diferencia) contra la consulta original. Medición real: 1.578,513 ms (consulta original) vs. 0.178 ms (contra la vista materializada), ~8.868x. |

| Claude (rol Kiro: especificar) | Redactar la spec de las funciones/procedimientos programables que faltaban para el objetivo 6 del TPI | Objetivo, firma, y qué debía validar cada uno (spec implícita en los comentarios de `programables/funciones_procedimientos.sql`) | Se aceptó el diseño: 2 funciones (una escalar, una de tabla) + 2 procedimientos `CALL` (registrar y cancelar un pedido), reutilizando los triggers RN1/RN2 ya existentes en vez de duplicar su lógica. |
| Claude (rol OpenCode: generar) | Generar `fn_top_productos_categoria` (función de tabla) | "Función que devuelva el top-N de productos más vendidos de una categoría, ordenado por unidades vendidas" | **Se aceptó tras corregir un bug real**, detectado al comparar el resultado de la función contra la consulta manual equivalente: el `ORDER BY unidades_vendidas DESC` dentro del cuerpo de la función resolvía contra el parámetro de salida homónimo de `RETURNS TABLE` (una variable PL/pgSQL, siempre NULL en ese punto) en vez de contra el valor calculado por el `SELECT`, así que el resultado salía sin ordenar. Se corrigió ordenando por la expresión `SUM(pp.cantidad)` en vez de por el alias. |
| Claude (rol OpenCode: generar) | Generar `sp_registrar_pedido` y `sp_cancelar_pedido` (procedimientos `CALL`, con `JSONB`) | "Procedimiento que reciba un carrito como JSONB y registre el pedido completo, apoyándose en los triggers existentes para validar stock y vigencia" | Se aceptaron ambos. Probados con `BEGIN/ROLLBACK` (`programables/pruebas_funciones_procedimientos.sql`): caso exitoso (stock se descuenta correctamente), caso negativo por RN2 (stock insuficiente en la segunda línea aborta *todo* el `CALL`, incluida la primera línea que por sí sola era válida — atomicidad real confirmada, no solo la línea que falla), caso negativo por RN1 (producto de baja) y caso negativo de `sp_cancelar_pedido` (pedido inexistente). Los 4 casos midieron el comportamiento esperado sin necesidad de modificar nada de la propuesta original. |

## Nota sobre el entorno

Todo lo anterior se corrió de verdad contra PostgreSQL 16, sobre la
base `food_store` tal como quedó al cierre de la Semana 4, sin
modificar el modelo de datos ni sus restricciones (solo se agregaron
índices y vistas, como pide la consigna). El desarrollo completo, con
los planes de `EXPLAIN ANALYZE` reales y el detalle de cada medición,
está en `informe_mediciones.md`.
