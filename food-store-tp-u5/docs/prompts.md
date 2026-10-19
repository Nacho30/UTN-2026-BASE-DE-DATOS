# Prompts enviados a la IA

Texto exacto de cada prompt. La respuesta resumida y la validación están en `BITACORA.md`; las respuestas completas, en `docs/respuestas_ia/`.

## P1 — Parte A.4: auditoría de `roles.sql`

> Sos un DBA senior de PostgreSQL 16. Auditá el archivo `roles.sql` que te adjunto: es el esquema de roles de una base de una tienda de comida (Food Store). Señalá permisos de más, permisos que falten para que la aplicación funcione, riesgos de escalamiento y malas prácticas. Proponé las correcciones concretas como sentencias SQL listas para aplicar.
>
> *(adjunto: `sql/roles.sql`)*

## P2 — Parte C.4: reconstrucción del incidente

Se entrega el log anonimizado **sin ningún contexto adicional**:

> A continuación hay un fragmento de log de un servidor PostgreSQL. Reconstruí qué ocurrió, en orden cronológico, y proponé una hipótesis de contención.
>
> *(adjunto: `docs/log_simulacro_anonimizado.txt`, completo)*

## P3 — Parte D.2: consulta equivalente sobre la tabla real

> Tengo en PostgreSQL 16 una tabla `usuario_anon(id_anon, nombre_anon, email_anon, rol, mes_alta DATE, bloqueado, eliminado)`, donde `mes_alta` es la fecha de alta truncada al primer día del mes. Sobre ella corro esta consulta:
>
> ```sql
> SELECT rol, to_char(mes_alta, 'YYYY-MM') AS mes_alta, count(*) AS usuarios
> FROM usuario_anon WHERE eliminado = FALSE
> GROUP BY rol, mes_alta ORDER BY rol, mes_alta;
> ```
>
> La tabla real es `usuario(id, nombre, email, rol, telefono, direccion, fecha_alta DATE, password_hash, intentos_fallidos, bloqueado, eliminado)`. Escribí la consulta equivalente sobre `usuario`, que tiene que devolver exactamente los mismos grupos y conteos.
