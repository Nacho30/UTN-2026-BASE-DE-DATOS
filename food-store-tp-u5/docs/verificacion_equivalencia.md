# Verificación de equivalencia — Parte D

## 1. Construcción de `usuario_anon`

Script: [`sql/usuario_anon.sql`](../sql/usuario_anon.sql). Salida de los controles: [`salida_usuario_anon.txt`](salida_usuario_anon.txt).

| Columna de `usuario` | En `usuario_anon` | Técnica |
|---|---|---|
| `id`, `nombre`, `email` | `id_anon`, `nombre_anon`, `email_anon` | Seudonimización determinista: `U-` + 8 hex de `md5(sal ‖ id)` |
| `telefono`, `direccion` | — | Supresión |
| `fecha_alta` | `mes_alta` | Generalización al primer día del mes |
| `password_hash`, `intentos_fallidos` | — | Supresión |
| `rol`, `bloqueado`, `eliminado` | iguales | Se conservan (necesarios para los agregados) |

Es determinista porque la misma sal produce siempre el mismo seudónimo. Por eso el usuario del log anonimizado de la Parte C (`U-11b9a2f8`) es la misma fila `ADMIN` de `usuario_anon`, y las dos evidencias se pueden cruzar sin datos reales. La sal está en `.env`, fuera del repositorio. Como viaja en el texto de la sentencia, el script apaga `log_statement` sólo en su sesión, y se verificó que la sal no aparece en el log del servidor.

Controles (todos dieron el valor esperado):

- 1000 filas en `usuario` y 1000 en `usuario_anon`, con 1000 seudónimos distintos: no hay colisiones.
- 0 coincidencias de email, nombre, apellido o id entre ambas tablas.
- Al regenerar los seudónimos, los 1000 usuarios se emparejan y ninguno difiere en rol o mes.
- `reportes_bi` puede leer `usuario_anon` y no puede leer `usuario`. `admin_datos` recibió DML sobre la tabla nueva sin un `GRANT` explícito, como prueba de que los default privileges de la Parte A funcionan.

## 2. Las dos consultas

Especificación: *cantidad de usuarios activos (`eliminado = FALSE`) por rol y por mes de alta, ordenada por rol y mes*. Script: [`sql/verificacion_equivalencia.sql`](../sql/verificacion_equivalencia.sql). Salida completa: [`salida_equivalencia.txt`](salida_equivalencia.txt).

**Consulta 1 — sobre `usuario_anon`**, ejecutada como `reportes_bi`:

```sql
SELECT rol, to_char(mes_alta, 'YYYY-MM') AS mes_alta, count(*) AS usuarios
FROM usuario_anon
WHERE eliminado = FALSE
GROUP BY rol, mes_alta
ORDER BY rol, mes_alta;
```

**Consulta 2 — equivalente sobre `usuario`:**

```sql
SELECT rol, to_char(date_trunc('month', fecha_alta), 'YYYY-MM') AS mes_alta, count(*) AS usuarios
FROM usuario
WHERE eliminado = FALSE
GROUP BY rol, date_trunc('month', fecha_alta)
ORDER BY rol, mes_alta;
```

La consulta real tiene que reproducir la generalización (`date_trunc('month', …)`). Si se agrupara por `fecha_alta` sin truncar, daría otros grupos y la comparación sería inválida.

## 3. Resultados lado a lado

- Las dos diferencias (`anon EXCEPT real` y `real EXCEPT anon`) dan **0 filas**.
- Los totales son 1000 contra 1000, y la cantidad de grupos es 74 contra 74.
- Totales por rol: ADMIN 20 = 20, CLIENTE 877 = 877, LOGISTICA 4 = 4, REPARTIDOR 99 = 99.

| Rol | Mes de alta | Usuarios en `usuario_anon` | Usuarios en `usuario` | Diferencia |
|---|---|---|---|---|
| ADMIN | 2024-10 | 1 | 1 | 0 |
| ADMIN | 2024-11 | 1 | 1 | 0 |
| ADMIN | 2025-01 | 1 | 1 | 0 |
| ADMIN | 2025-02 | 1 | 1 | 0 |
| ADMIN | 2025-03 | 1 | 1 | 0 |
| ADMIN | 2025-04 | 1 | 1 | 0 |
| ADMIN | 2025-06 | 1 | 1 | 0 |
| ADMIN | 2025-07 | 1 | 1 | 0 |
| ADMIN | 2025-08 | 1 | 1 | 0 |
| ADMIN | 2025-09 | 1 | 1 | 0 |
| ADMIN | 2025-10 | 1 | 1 | 0 |
| ADMIN | 2025-11 | 1 | 1 | 0 |
| ADMIN | 2025-12 | 1 | 1 | 0 |
| ADMIN | 2026-02 | 1 | 1 | 0 |
| ADMIN | 2026-03 | 1 | 1 | 0 |
| ADMIN | 2026-04 | 1 | 1 | 0 |
| ADMIN | 2026-05 | 1 | 1 | 0 |
| ADMIN | 2026-07 | 1 | 1 | 0 |
| ADMIN | 2026-08 | 1 | 1 | 0 |
| ADMIN | 2026-09 | 1 | 1 | 0 |
| CLIENTE | 2024-10 | 37 | 37 | 0 |
| CLIENTE | 2024-11 | 34 | 34 | 0 |
| CLIENTE | 2024-12 | 38 | 38 | 0 |
| CLIENTE | 2025-01 | 35 | 35 | 0 |
| CLIENTE | 2025-02 | 33 | 33 | 0 |
| CLIENTE | 2025-03 | 36 | 36 | 0 |
| CLIENTE | 2025-04 | 37 | 37 | 0 |
| CLIENTE | 2025-05 | 35 | 35 | 0 |
| CLIENTE | 2025-06 | 36 | 36 | 0 |
| CLIENTE | 2025-07 | 37 | 37 | 0 |
| CLIENTE | 2025-08 | 36 | 36 | 0 |
| CLIENTE | 2025-09 | 34 | 34 | 0 |
| CLIENTE | 2025-10 | 39 | 39 | 0 |
| CLIENTE | 2025-11 | 34 | 34 | 0 |
| CLIENTE | 2025-12 | 36 | 36 | 0 |
| CLIENTE | 2026-01 | 36 | 36 | 0 |
| CLIENTE | 2026-02 | 33 | 33 | 0 |
| CLIENTE | 2026-03 | 37 | 37 | 0 |
| CLIENTE | 2026-04 | 31 | 31 | 0 |
| CLIENTE | 2026-05 | 39 | 39 | 0 |
| CLIENTE | 2026-06 | 36 | 36 | 0 |
| CLIENTE | 2026-07 | 34 | 34 | 0 |
| CLIENTE | 2026-08 | 36 | 36 | 0 |
| CLIENTE | 2026-09 | 37 | 37 | 0 |
| CLIENTE | 2026-10 | 21 | 21 | 0 |
| LOGISTICA | 2025-01 | 1 | 1 | 0 |
| LOGISTICA | 2026-04 | 1 | 1 | 0 |
| LOGISTICA | 2026-07 | 1 | 1 | 0 |
| LOGISTICA | 2026-10 | 1 | 1 | 0 |
| REPARTIDOR | 2024-10 | 3 | 3 | 0 |
| REPARTIDOR | 2024-11 | 5 | 5 | 0 |
| REPARTIDOR | 2024-12 | 3 | 3 | 0 |
| REPARTIDOR | 2025-01 | 5 | 5 | 0 |
| REPARTIDOR | 2025-02 | 3 | 3 | 0 |
| REPARTIDOR | 2025-03 | 5 | 5 | 0 |
| REPARTIDOR | 2025-04 | 3 | 3 | 0 |
| REPARTIDOR | 2025-05 | 5 | 5 | 0 |
| REPARTIDOR | 2025-06 | 4 | 4 | 0 |
| REPARTIDOR | 2025-07 | 5 | 5 | 0 |
| REPARTIDOR | 2025-08 | 3 | 3 | 0 |
| REPARTIDOR | 2025-09 | 5 | 5 | 0 |
| REPARTIDOR | 2025-10 | 3 | 3 | 0 |
| REPARTIDOR | 2025-11 | 4 | 4 | 0 |
| REPARTIDOR | 2025-12 | 5 | 5 | 0 |
| REPARTIDOR | 2026-01 | 5 | 5 | 0 |
| REPARTIDOR | 2026-02 | 3 | 3 | 0 |
| REPARTIDOR | 2026-03 | 4 | 4 | 0 |
| REPARTIDOR | 2026-04 | 5 | 5 | 0 |
| REPARTIDOR | 2026-05 | 2 | 2 | 0 |
| REPARTIDOR | 2026-06 | 5 | 5 | 0 |
| REPARTIDOR | 2026-07 | 4 | 4 | 0 |
| REPARTIDOR | 2026-08 | 4 | 4 | 0 |
| REPARTIDOR | 2026-09 | 3 | 3 | 0 |
| REPARTIDOR | 2026-10 | 3 | 3 | 0 |

## 4. Observación: la equivalencia no garantiza el anonimato

39 de los 74 grupos tienen menos de 5 usuarios, y todos los grupos `ADMIN` y `LOGISTICA` tienen exactamente 1. Quien sepa que una persona se volvió administradora en septiembre de 2025 la identifica en `usuario_anon` y, con eso, en el log anonimizado de la Parte C. Un reporte que vaya a salir de Food Store debería aplicar un umbral mínimo por celda (por ejemplo, suprimir o agrupar las celdas con menos de 5 usuarios, como en k-anonimato) o generalizar más, por trimestre en lugar de mes.

## 5. Qué no debe salir nunca hacia una IA sin anonimizar

No deben llegar a un asistente de IA, sin pasar antes por este proceso, los datos de contacto y de identidad de `usuario`: nombre, email, teléfono y dirección de entrega, junto con cualquier `id` que permita volver a la persona. Tampoco las credenciales y su estado (`password_hash`, intentos fallidos, bloqueos), ni los fragmentos de log o de `auditoria_login`, que unen esos identificadores con IPs, horarios y contraseñas probadas. Lo mismo vale para el historial de pedidos de una persona identificable, porque sus direcciones y hábitos de compra la describen tanto como su nombre.
