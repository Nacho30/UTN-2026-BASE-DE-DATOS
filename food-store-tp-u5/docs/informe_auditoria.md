# Informe de auditoría — Parte B

Entorno: PostgreSQL 16.15, servidor de desarrollo propio, base `foodstore_u5`.

## 1. Parámetros modificados

Se modificaron con `ALTER SYSTEM` (script `sql/auditoria_config.sql`), que escribe en `postgresql.auto.conf`. `logging_collector` requiere reiniciar el servidor; el resto sólo necesita recargar la configuración.

| Parámetro | Valor anterior | Valor nuevo | Para qué |
|---|---|---|---|
| `log_connections` | off | **on** | Registra cada conexión: origen, rol, base y método de autenticación |
| `log_disconnections` | off | **on** | Registra el fin de cada sesión y su duración |
| `log_statement` | none | **mod** | Registra DDL y toda sentencia que modifica datos (INSERT, UPDATE, DELETE, TRUNCATE, COPY FROM) |
| `log_line_prefix` | `%m [%p] ` | **`%m [%p] user=%u db=%d host=%h app=%a `** | Agrega a cada línea quién, en qué base, desde dónde y con qué aplicación |
| `log_timezone` | America/Argentina/Buenos_Aires | **America/Argentina/Buenos_Aires** (explícito) | Horas en el huso local, fijadas aunque cambie el sistema operativo |
| `logging_collector` | off | **on** | El log va a un archivo propio en lugar de la salida estándar |
| `log_directory` / `log_filename` | — | **log / postgresql-%Y-%m-%d.log** | Un archivo por día |
| `log_file_mode` | 0600 | **0600** (explícito) | Sólo el usuario `postgres` del sistema operativo puede leerlo |
| `log_rotation_age` | 1d | **1d** (explícito) | Rotación diaria |
| `log_min_error_statement` | error | **error** (explícito) | La sentencia que provocó un error queda junto al error |

Además se reemplazó el `pg_hba.conf`, que venía con `trust` para todo (`config/pg_hba.conf`). El superusuario entra sólo por socket con `peer`, los roles de la aplicación siempre con `scram-sha-256`, y cualquier otra combinación se rechaza. Sin este cambio, **un login con contraseña incorrecta no puede fallar**, porque con `trust` el motor no pide contraseña.

## 2. Secuencia de prueba y log

`scripts/ejecutar_auditoria_test.sh` ejecuta `sql/auditoria_test.sql` como `app_web`, por TCP y con contraseña. La secuencia incluye una lectura, una inserción (pedido y detalle), una actualización, un login fallido **de la aplicación** (`fn_autenticar`) y un `DELETE` no permitido. Después provoca un login fallido **del motor**. El fragmento capturado está en [`log_auditoria_prueba.txt`](log_auditoria_prueba.txt).

## 3. Qué aporta el log y qué queda afuera

**Información útil a los fines de auditoría**, presente en cada línea gracias a `log_line_prefix`:

| Pregunta | Dónde aparece | Ejemplo del fragmento |
|---|---|---|
| **Quién** | `user=` y `identity=` de la autenticación | `user=app_web`, `identity="app_web" method=scram-sha-256` |
| **Qué** | `statement:`, `ERROR:` y los `RAISE LOG` de `fn_autenticar` | `INSERT INTO pedido …`, `ERROR: permission denied for table pedido` |
| **Cuándo** | marca de tiempo al milisegundo y `session time` | `2026-10-19 19:54:30.477 -03`, `session time: 0:00:00.174` |
| **Desde dónde** | `host=`, `port=`, `app=` y la línea de `pg_hba.conf` usada | `host=127.0.0.1 port=45332 app=foodstore-web` |

El login fallido del motor queda como `FATAL: password authentication failed for user "app_web"`, con la regla de `pg_hba.conf` que se aplicó. El `[pid]` (`[389]`) permite agrupar todas las líneas de una misma sesión.

**Qué queda fuera del alcance de este mecanismo nativo:**

- **Las lecturas no se registran.** El `SELECT … FROM producto` del paso 1 no aparece, porque `log_statement = 'mod'` omite los SELECT. Pasarlo a `all` registra todo, pero genera un volumen enorme y no distingue qué tabla se leyó.
- **La llamada a `fn_autenticar` sólo aparece porque la función la registra con `RAISE LOG`.** El motor no sabe que eso es un login: para él es un `SELECT`. Es un registro técnico fabricado por la aplicación, no por el mecanismo de auditoría.
- **No hay detalle por objeto ni por fila.** Se ve el texto de la sentencia, no qué filas afectó ni sus valores anteriores. El `UPDATE` muestra `WHERE id = currval(…)`, pero no qué id terminó siendo.
- **No se ve lo que ocurre dentro de funciones y disparadores.** El `INSERT` en `detalle_pedido` disparó un `INSERT … ON CONFLICT` sobre `venta_diaria_categoria` (Unidad 4), y ese efecto no figura en el log.
- **El rol de base no es la persona.** `user=app_web` dice que fue la aplicación, no qué cliente de la app. Para eso hace falta que la aplicación propague su propia identidad (por ejemplo, en `application_name`) o un registro de negocio como `auditoria_login`.

La extensión **pgaudit**, a nivel de nociones, cubre buena parte de esos huecos. Permite auditar por clase de sentencia (`READ`, `WRITE`, `ROLE`, `DDL`) y por objeto: sólo las tablas que un rol auditor tiene asignadas. Separa cada sentencia de una sentencia compuesta, incluidas las que ejecutan funciones, y produce líneas con formato estable (`AUDIT: SESSION,…,READ,SELECT,TABLE,public.usuario,…`), fáciles de procesar. Aun así, no registra valores de filas: para un historial de cambios por fila se usan disparadores de auditoría o decodificación lógica.

Esto marca la diferencia entre un **registro técnico** y un **registro con vocación de rendición de cuentas**. El log del servidor sirve para operar y diagnosticar, pero lo puede leer, rotar o borrar quien administra el servidor. `auditoria_login` y `auditoria_password` son registros de negocio que asocian la acción a una persona de Food Store y que `admin_datos` no puede alterar (Parte A).

## 4. ¿El log es, en sí mismo, un activo sensible?

Sí, y el propio fragmento capturado lo demuestra. Contiene un email en claro (`camila.perez42@yahoo.com.ar`, escrito por el `RAISE LOG` de `fn_autenticar`) y, peor, **la contraseña probada**: la línea `STATEMENT:` que PostgreSQL agrega a todo mensaje de nivel `LOG` copió la llamada completa, `fn_autenticar('…', 'contraseña-equivocada')`. También contiene nombres de roles, direcciones IP y el texto completo de las sentencias, que pueden incluir datos personales o, con `log_statement = 'all'` o `'ddl'`, contraseñas en un `ALTER ROLE … PASSWORD`. Por eso el log debe tratarse con el mismo cuidado que la tabla `usuario`.

Debería leerlo sólo el usuario `postgres` del sistema operativo y, en caso de necesidad, el equipo de seguridad, a través de una copia o un envío a un sistema de logs centralizado con acceso restringido. Del lado del sistema operativo: archivos con modo `0600` (`log_file_mode`) y directorio `0700`. Del lado del motor: no otorgar `pg_read_server_files` ni `pg_monitor`, que permiten leer archivos y ver la actividad, a roles de aplicación o de soporte. **Corrección aplicada a partir de este hallazgo** (commit `fix(seguridad)`, detectado al preparar la Parte C):

- `fn_autenticar` ahora escribe en el log sólo el `usuario_id` y la cantidad de intentos. Si el email no existe, deja un hash truncado.
- Toda llamada a `fn_autenticar` usa parámetros enlazados (`$1, $2` con `\bind` en psql; en la app, consultas parametrizadas). Así la línea `STATEMENT` queda como `SELECT fn_autenticar($1, $2)`, y con `log_parameter_max_length_on_error = 0` (valor por defecto) los valores no se escriben. Se verificó con una llamada de prueba antes de aplicarlo al simulacro.
- El fragmento `log_auditoria_prueba.txt` **se conserva tal como se capturó**, como evidencia del problema: la contraseña que figura es la de prueba, inválida, y el email es ficticio.
