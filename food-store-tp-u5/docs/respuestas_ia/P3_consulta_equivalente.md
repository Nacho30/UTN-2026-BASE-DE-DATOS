# P3 — Respuesta completa de la IA (Parte D.2)

- **Asistente:** Claude (Anthropic). Lo ejecutó un agente independiente que recibió sólo el prompt de `docs/prompts.md` (P3), sin acceso al repositorio, a la base ni a esta conversación.
- **Fecha:** 2026-10-19.
- **Validación:** [`P3_validacion.txt`](P3_validacion.txt) y entrada D-1 de `BITACORA.md`.

---

Esta es la consulta equivalente sobre `usuario`:

```sql
SELECT rol,
       to_char(date_trunc('month', fecha_alta::timestamp), 'YYYY-MM') AS mes_alta,
       count(*) AS usuarios
FROM usuario
WHERE eliminado = FALSE
GROUP BY rol, date_trunc('month', fecha_alta::timestamp)
ORDER BY rol, date_trunc('month', fecha_alta::timestamp);
```

**Por qué devuelve los mismos grupos y conteos:**

1. **Agrupación por mes.** En la consulta original, `GROUP BY rol, mes_alta` agrupa por la **columna** `mes_alta` de la tabla (la fecha ya truncada al primer día del mes), no por el alias de texto. Esto pasa porque en PostgreSQL un nombre en `GROUP BY` se busca primero entre las columnas de entrada y después entre los alias del `SELECT`. En `usuario` el valor equivalente es `date_trunc('month', fecha_alta)`, así que agrupo por esa expresión.
2. **Cast a `timestamp`.** Sin el `::timestamp`, `date_trunc` sobre un `date` lo convierte implícitamente a `timestamptz`, y el resultado queda dependiendo de la zona horaria de la sesión. Con el cast a `timestamp` el resultado es determinista.
3. **Etiqueta de salida.** `to_char(..., 'YYYY-MM')` da el mismo texto que antes, porque el primer día del mes produce el mismo `YYYY-MM` que cualquier fecha de ese mes.
4. **Filtro.** `eliminado = FALSE` es idéntico: las filas con `eliminado` NULL quedan afuera en las dos consultas. Las filas con `fecha_alta` NULL forman un grupo `mes_alta` NULL por cada `rol`, igual que en la tabla anonimizada.
5. **Orden.** En la original, `ORDER BY mes_alta` usa el alias de texto (en `ORDER BY` los alias de salida van primero). Para años de 4 dígitos, ordenar ese texto da el mismo orden que ordenar por la fecha, así que ordenar por la expresión de fecha produce el mismo resultado.

**Alternativa más corta** (equivalente en la práctica, aunque menos explícita):

```sql
SELECT rol, to_char(fecha_alta, 'YYYY-MM') AS mes_alta, count(*) AS usuarios
FROM usuario WHERE eliminado = FALSE
GROUP BY 1, 2 ORDER BY 1, 2;
```

**Supuesto:** las dos consultas coinciden solo si `usuario_anon` se generó 1 a 1 desde `usuario`, sin filtrar filas y copiando `rol` y `eliminado` tal cual, con `mes_alta = date_trunc('month', fecha_alta)`.
