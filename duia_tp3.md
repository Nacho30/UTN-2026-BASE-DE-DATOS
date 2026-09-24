# DUIA — TP3 (optimización de consultas, Semana 3)

Proyecto Food Store — PostgreSQL 16. Salidas reales del motor sobre una base
poblada masivamente (50.005 productos, 20.003 clientes, 200.002 pedidos,
499.403 líneas de detalle). Herramienta de IA declarada en la consigna:
OpenCode. Este entorno usó Claude (Anthropic) en su lugar, igual que se
declaró en `duia_parte1.md` del TP2.

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| Claude (OpenCode no disponible en este entorno) | Generar el script de carga masiva (Parte 1) | Insertar 50k productos, 20k clientes, 200k pedidos + detalle, con `generate_series` | Se aceptó tras corregir un bug real detectado al validar la distribución de líneas por pedido: la primera versión evaluaba `random()` una sola vez por consulta en vez de una vez por fila (ver `optimizacion/carga_masiva.sql`, comentario en el INSERT de `pedido_producto`). |
| Claude | Proponer índices a partir de los 3 planes reales de la Parte 2 | "Acá está el plan de EXPLAIN ANALYZE de esta consulta, proponé un índice que lo mejore y explicá qué nodo ataca" | Se aceptaron los índices de Q2 y Q3 (mejora real 56x y 163x). Se descartó un índice cubriente propuesto para Q1: la medición real (10.386 ms) no mejoró el índice simple (9.321 ms). |
| Claude | Explicar en lenguaje natural el plan de Q3 con índice (Parte 3) | "Explicá este plan de EXPLAIN ANALYZE nodo por nodo", solo el texto del plan, sin más contexto | Se descartó la explicación tal cual: 3 de 4 afirmaciones eran incorrectas (confundía cost con ms, decía que no accedía a la tabla siendo un Bitmap Heap Scan, atribuía la mejora a paralelismo que no está en el plan). Se usó como material de análisis crítico, no como fuente de verdad. |
| Claude | Generar el SQL de las 2 consultas de la Parte 4 a partir de la spec | Specs precisas de agregación y de subconsulta (tablas, filtro de borrado lógico, columnas, orden, corte), sin mostrar una solución previa | Se aceptó el SQL generado en ambos casos, verificado con `EXCEPT` real (0 filas de diferencia en ambas direcciones, ver `optimizacion/parte4_consultas.sql`). Se documentó además que la subconsulta correlacionada, aunque correcta, es ~2.400x más lenta que la reescritura con JOIN a escala real (86.881 ms vs 36 ms). |
| Claude | Proponer estrategia para la consulta común de la Parte 5 | "Esta consulta es lenta a escala, proponé cómo optimizarla" + plan real adjunto | Se aceptó un índice parcial `(nombre) WHERE activo AND stock < 10` (mejora real 2.2x). Se descartó forzar `enable_seqscan`/`enable_bitmapscan` en la sesión aunque medía mejor (5.3x): no es una estrategia sostenible fuera de un diagnóstico puntual, y el criterio de aceptación de la cátedra pide algo que se pueda sostener, no un truco de sesión. |

## Nota sobre el entorno

Todo lo anterior se corrió de verdad contra PostgreSQL 16 sobre una base
`food_store` creada a partir de `schema.sql` + una carga masiva propia
(`optimizacion/carga_masiva.sql`), siguiendo el protocolo de la cátedra:
respaldo previo con `pg_dump`, carga dentro de una transacción, y
`ANALYZE` antes de medir. El desarrollo completo, con los planes de
EXPLAIN ANALYZE reales y las tablas comparativas de cada parte, está en
`docs/TP3_Semana3_Unidad2_Practica_resuelto.docx`.
