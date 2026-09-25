# Informe técnico — TPI «Food Store» — Primera entrega parcial

Base de Datos II · Unidades 1 a 3 · PostgreSQL 16 · Proyecto integrador Food Store

Este informe consolida todo lo entregado hasta ahora en el TPI y lo
mapea contra los 9 objetivos que exige la entrega, con la evidencia
concreta (archivo, consulta o resultado) de cada uno. Todo lo medido a
continuación se corrió de verdad contra PostgreSQL 16, sobre una base
`food_store` poblada masivamente (50.005 productos, 20.003 clientes,
200.002 pedidos, 499.403 líneas de `pedido_producto`): no hay tiempos
ni resultados simulados en ningún punto de este informe ni de los
documentos que referencia.

## Checklist de los 9 objetivos

| # | Objetivo | Evidencia | Unidad |
|---|---|---|---|
| 1 | Modelo ER (entidades, atributos, claves, cardinalidad, participación) | `docs/TP1_FoodStore_ModeloER_Normalizacion_DDL.docx` (diagrama ER + justificación de cardinalidades y participación de las 5 entidades) | U1 |
| 2 | Paso de ER a relacional, 1:N y N:M con tablas intermedias | Mismo documento, Parte 2. `pedido_producto` es la tabla intermedia que resuelve la N:M entre `pedido` y `producto`; `producto→categoria` y `pedido→cliente` son las 1:N. Ver `schema.sql`. | U1 |
| 3 | Normalización 3FN/BCNF con justificación de dependencias funcionales | Mismo documento, Parte 3: dependencias funcionales de cada tabla y por qué no hay dependencias transitivas ni parciales remanentes. | U1 |
| 4 | DDL completo: tipos, PK/FK, restricciones e índices | `schema.sql` (tipos ENUM/IDENTITY/TIMESTAMPTZ, PK, FK con ON DELETE, CHECK) + `indices.sql` (9 índices: 5 heredados de Semanas 3/4 + 3 nuevos de U3S1, con su justificación). | U1, U3 |
| 5 | DML y consultas: JOIN, agregación, subconsultas, GROUP BY/HAVING, funciones de ventana | `optimizacion/queries.sql`, `optimizacion/parte4_consultas.sql`, `analitica/queries_tp4.sql`, `analitica/parte2_qc.sql`, `analitica/parte3_ranking.sql` (RANK() OVER + subconsulta correlacionada), `analitica/parte4_competencia.sql`. | U2 |
| 6 | Vistas, funciones y procedimientos almacenados en PL/pgSQL | `views.sql` (4 vistas + 1 vista materializada) + `programables/funciones_procedimientos.sql` (2 funciones, 2 procedimientos `CALL`, con JSONB). | U3 |
| 7 | Reglas de negocio con CHECK, UNIQUE y triggers | `schema.sql` (CHECK de precio/stock/cantidad no negativos, UNIQUE de `categoria.nombre`/`cliente.email`) + `migraciones/001_restricciones_reglas_negocio.sql` (2 triggers: RN1+RN2 sobre `pedido_producto`, RN3 sobre `categoria`). | U1, U2 |
| 8 | Transacciones: atomicidad, COMMIT, ROLLBACK, aislamiento, concurrencia | `informe_concurrencia.md` + `lab/` (4 escenarios de dos sesiones concurrentes verificados en el motor) + `protocolo_seguridad.md` (BEGIN/ROLLBACK como flujo de trabajo estándar) + atomicidad real de `sp_registrar_pedido`/`sp_cancelar_pedido` (ver más abajo). | U2, U3 |
| 9 | Borrado lógico (soft delete) y su impacto en consultas e índices | `activo BOOLEAN` en `categoria`/`producto`/`cliente` (regla R7 desde TP1); su impacto en índices: 2 de los 3 índices nuevos de U3S1 son parciales `WHERE activo = true` precisamente por esto (`indices.sql`, `informe_mediciones.md`). | U1, U3 |

## Qué se implementó en cada unidad

### Unidad 1 — Modelo, esquema y DDL
Diseño del modelo ER de Food Store (categoria, producto, cliente,
pedido, pedido_producto), paso a modelo relacional resolviendo la
relación N:M pedido↔producto con la tabla intermedia
`pedido_producto`, normalización justificada hasta 3FN, y el DDL
completo con 7 reglas de negocio (R1–R7) traducidas a restricciones
del motor: tipos de dato ajustados (`NUMERIC` para dinero, `ENUM` para
forma de pago, `TIMESTAMPTZ`), claves primarias `GENERATED ALWAYS AS
IDENTITY`, claves foráneas con `ON DELETE RESTRICT`/`CASCADE` según
corresponde, `CHECK` de no negatividad y baja lógica (`activo`) en vez
de `DELETE` físico (R7).

**Cómo se probó:** cada `CREATE TABLE` se ejecutó contra una base
PostgreSQL 16 real; los `CHECK` se probaron con INSERT que los violan
a propósito (deben fallar) y con INSERT válidos (deben pasar).

**Resultado:** esquema aplicado sin errores, base de partida para
todas las unidades siguientes.

### Unidad 2 — Reglas de negocio, transacciones, concurrencia y optimización
Se agregaron los triggers RN1 (no vender producto de baja), RN2
(descuento de stock con rechazo si no alcanza) y RN3 (no dar de baja
una categoría con productos activos), probados con casos positivos y
negativos en `pruebas/001_pruebas_restricciones.sql`. Se verificaron 4
escenarios reales de concurrencia con dos sesiones simultáneas
(`informe_concurrencia.md`), y se estableció el protocolo de trabajo
sobre `copia_trabajo` con respaldo previo y `BEGIN/ROLLBACK`
(`protocolo_seguridad.md`).

Sobre una base poblada masivamente, se identificaron y optimizaron
consultas lentas reales con `EXPLAIN ANALYZE` (detalle completo de
cada mejora en la sección "Consultas optimizadas" más abajo), y se
practicaron JOIN, subconsultas (correlacionadas y no), agregación,
`GROUP BY`/`HAVING` y funciones de ventana sobre reportes analíticos
de 3 y 4 tablas.

**Cómo se probó:** cada regla de negocio con un INSERT/UPDATE que
debía fallar y uno que debía pasar; cada consulta optimizada con
`EXPLAIN ANALYZE` antes y después del cambio; cada par de consultas
"misma pregunta, dos estructuras" con `EXCEPT` en ambos sentidos (0
filas de diferencia exigidas para aceptar la reescritura).

**Resultado:** las 3 reglas de negocio quedaron garantizadas en el
motor (no solo en la aplicación), los 4 escenarios de concurrencia se
comportaron según el nivel de aislamiento esperado, y las consultas
optimizadas bajaron de milisegundos de tres dígitos a menos de uno en
los casos más selectivos.

### Unidad 3 — Índices, vistas, vista materializada y objetos programables
Plan de indexado justificado con mediciones reales: 3 índices
aceptados (2 mejoras de ~60x por búsqueda exacta ahora indexada, 1
mejora de ~3.7x por selectividad media) y 1 descartado explícitamente
por sobreindexación (columna de baja cardinalidad, sin mejora real
medida). Se midió además el costo de esos índices sobre la escritura
(INSERT en `pedido_producto`).

4 vistas de lectura (productos vigentes con categoría, pedidos con
cliente, detalle de pedido con producto, y una vista de seguridad que
oculta los datos de contacto del cliente), cada una verificada
formalmente equivalente a su consulta manual con `EXCEPT`. Una vista
materializada del reporte de facturación por categoría y mes, con
índice único para `REFRESH CONCURRENTLY`, con una mejora real de
~8.868x contra la consulta sin materializar.

Para cerrar el objetivo 6 de esta entrega (funciones y procedimientos
almacenados en PL/pgSQL, con `CALL` y `JSONB`, que hasta la entrega
anterior no estaban cubiertos), se agregaron:
- `fn_facturacion_cliente(id_cliente, desde, hasta)`: función escalar.
- `fn_top_productos_categoria(id_categoria, limite)`: función de
  tabla (`RETURNS TABLE`).
- `sp_registrar_pedido(id_cliente, forma_pago, items JSONB, INOUT
  id_pedido)`: procedimiento invocado con `CALL` que arma un pedido
  completo a partir de un carrito en JSONB, apoyándose en los
  triggers RN1/RN2 ya existentes para la validación y el descuento de
  stock — si cualquier línea falla, el `CALL` completo se aborta
  (atomicidad real, probada).
- `sp_cancelar_pedido(id_pedido)`: procedimiento inverso, repone
  stock y borra el pedido, con su propio caso negativo (pedido
  inexistente).

**Cómo se probó:** cada índice con `EXPLAIN ANALYZE` antes/después;
cada vista con `EXCEPT` contra su consulta manual equivalente; la
vista materializada con `EXCEPT` contra la consulta original más la
medición de tiempo; cada función/procedimiento con al menos un caso
positivo y un caso negativo reales, dentro de `BEGIN/ROLLBACK` para no
alterar los datos de la base masiva (`programables/pruebas_funciones_procedimientos.sql`).

**Resultado:** ver la sección de mediciones para los números
completos. Un hallazgo real durante las pruebas: `fn_top_productos_categoria`
tenía un bug real (el `ORDER BY` por el alias de una columna de
`RETURNS TABLE` resolvía contra el parámetro de salida homónimo, no
contra el valor calculado, y el resultado salía sin ordenar) —
detectado al comparar el resultado de la función contra la consulta
equivalente manual, y corregido ordenando por la expresión en vez de
por el alias. Documentado en el propio archivo y en la sección de IA
más abajo.

## Consultas optimizadas: diferencias antes/después

| Consulta | Antes | Después | Mejora | Detalle |
|---|---|---|---|---|
| Historial de pedidos de un cliente (Q2, TP3) | ver `docs/TP3_..._resuelto.docx` | — | 56x | índice `idx_pedido_cliente` |
| Líneas de venta de un producto (Q3, TP3) | ver `docs/TP3_..._resuelto.docx` | — | 163x | índice `idx_pedido_producto_producto` |
| Subconsulta correlacionada vs. JOIN (Parte 4, TP3) | 86.881 ms | 36.310 ms | ~2.400x | reescritura con JOIN a tabla derivada |
| Facturación por categoría/mes filtrada a un mes (QA, TP4) | 100.597 ms | 97.932 ms | 1.03x | `idx_pedido_fecha` (no cambia el algoritmo de join) |
| Ranking de clientes por gasto (QB, TP4) | 474.545 ms | 453.372 ms | 1.05x | `work_mem` 64MB (elimina spill del HashAggregate) |
| Ranking: función de ventana vs. subconsulta correlacionada (Parte 3, TP4) | 52.212,425 ms (subconsulta) | 673.450 ms (ventana) | ~77.5x | `RANK() OVER` en vez de subconsulta correlacionada |
| Competencia: facturación por forma de pago (Parte 4, TP4) | 726.633 ms | 623.295 ms | 1.17x | `work_mem` 32MB |
| Búsqueda de cliente por apellido (Índice 1, U3S1) | 4.194 ms | 0.065 ms | ~64.5x | `idx_cliente_apellido` (parcial) |
| Búsqueda de producto por nombre (Índice 2, U3S1) | 3.679 ms | 0.063 ms | ~58.4x | `idx_producto_nombre_vig` (parcial) |
| Líneas de venta premium (Índice 3, U3S1) | 79.516 ms | 21.346 ms | ~3.7x | `idx_pedido_producto_precio` |
| Índice descartado — pedidos por forma de pago (U3S1) | 17.819 ms | 18.031 ms | **sin mejora** (descartado) | sobreindexación: ENUM de baja cardinalidad |
| Reporte de facturación por categoría/mes (vista materializada, U3S1) | 1.578,513 ms | 0.178 ms | ~8.868x | `mv_facturacion_categoria_mes` |

El detalle completo de cada plan de `EXPLAIN ANALYZE` (antes y
después, con Buffers y el nodo de join identificado) está en
`docs/TP3_Semana3_Unidad2_Practica_resuelto.docx`,
`docs/TP4_Semana4_Unidad2_Practica_resuelto.docx` e
`informe_mediciones.md`.

## Uso de herramientas de IA

La cátedra indica Kiro (especificación) y OpenCode (agente de
codificación en terminal). Este entorno de trabajo usó **Claude
(Anthropic)** en lugar de ambas — declarado así en cada bitácora desde
la primera entrega (`duia_parte1.md`). El rol de Kiro lo cumplen los
archivos de `specs/` (especificar antes de generar, con criterio de
aceptación explícito); el rol de OpenCode lo cumple la generación y
ejecución real del SQL contra el motor.

Decisiones de aceptar/descartar más relevantes, documentadas en cada
`duia*.md` de la entrega:
- **Descartado** un índice sobre `pedido.forma_pago` por
  sobreindexación (medido: sin mejora real) — `duia.md`.
- **Descartada** una primera versión de subconsulta correlacionada
  que no terminaba en 2 minutos; aceptada la reescritura que agrega
  antes de correlacionar — `duia.md`.
- **Descartada** una explicación de un plan de `Nested Loop` generada
  por IA con 3 de 4 afirmaciones incorrectas (confundía costo
  estimado con tiempo real, invertía el rol externa/interna del
  join) — `duia_tp4.md`.
- **Aceptado tras corregir un bug real** en el script de carga masiva
  (`random()` evaluado una sola vez por consulta en vez de una vez
  por fila) — `duia_tp3.md`.
- **Aceptado tras corregir un bug real** en `fn_top_productos_categoria`
  (alias de `RETURNS TABLE` resuelto contra el parámetro de salida en
  vez de contra el valor calculado) — ver más arriba y
  `programables/funciones_procedimientos.sql`.

No se usaron herramientas de IA adicionales a Claude.

## Nota de nomenclatura y adaptaciones documentadas

Este proyecto (Food Store, TP1) usa `cliente`/`activo`/`pedido_producto`
en vez de los nombres genéricos `usuario`/`eliminado`/`detalle_pedido`
que algunos enunciados de la cátedra usan a modo de ejemplo — ver la
nota al final de `schema.sql`. Como el esquema no tiene columna de
autenticación, el criterio de seguridad "vista sin contraseña" de la
consigna de vistas se aplicó sobre los datos de contacto directo del
cliente (`email`, `telefono`) — documentado explícitamente en
`specs/vistas_reportes.md` y verificado con `\d vista_cliente_publico`.

## Estado de la entrega y qué falta

Esta es la primera entrega parcial. Cubre los 9 objetivos exigidos con
evidencia verificable para las Unidades 1 a 3. Lo que sigue —según el
propio enunciado de U3S1— son los objetos programables adicionales de
la Unidad 4 en adelante y la ampliación del proyecto hasta la entrega
final de la cursada.
