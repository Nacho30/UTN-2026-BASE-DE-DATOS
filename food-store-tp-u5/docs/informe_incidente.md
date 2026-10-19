# Informe de incidente — Parte C (simulacro)

> Simulacro controlado, ejecutado sólo contra `foodstore_u5` en el entorno de desarrollo propio. El "atacante" es el script `sql/simulacro_incidente.sql`, orquestado por `scripts/ejecutar_simulacro.sh`.

## 1. Qué ejecutó el equipo (la verdad de referencia)

**Escenario:** las credenciales de `app_web` se filtraron, por ejemplo por un `.env` subido por error. El atacante se conecta directo a la base desde otro equipo, prueba contraseñas contra una cuenta ADMIN de la aplicación, entra, vuelca los datos de contacto de todos los usuarios e intenta escalar a `admin_datos`. Para que el log tenga ruido realista, el script genera tráfico legítimo de la app antes y después. `scripts/origen_remoto.py` hace que el servidor vea al atacante desde `127.0.0.2` (anonimizado como `ip-02`), mientras la app legítima llega desde `127.0.0.1` (`ip-01`).

| Hora (19/10/2026) | Paso | Resultado real |
|---|---|---|
| 19:58:40.736 | **Preparación del simulacro** (no es parte del ataque): `postgres` resetea los contadores de las cuentas 1 y 50 para partir de un estado limpio | 2 filas actualizadas |
| 19:58:40.787 | Tráfico legítimo: la app autentica a un cliente | éxito |
| 19:58:43.837 – 46.861 | **Paso 1:** 4 contraseñas incorrectas contra la cuenta 50 (rol ADMIN en la app) | 4 fallos, contador en 4 |
| 19:58:47.869 | **Paso 2:** contraseña correcta | éxito, por debajo del umbral de bloqueo de 5 |
| 19:58:47.87 | **Paso 3a:** `SELECT id, nombre, email, telefono, direccion, rol FROM usuario` (volcado) | **1000 filas leídas** (`tmp/salida_simulacro.txt`) |
| 19:58:47.871 | **Paso 3b:** intento de leer también `password_hash` | denegado (permiso de columna) |
| 19:58:47.913 | **Paso 4:** `GRANT admin_datos TO rol_app_lectura` | denegado |
| 19:58:47.957 | `SET ROLE admin_datos` | denegado |
| 19:58:47.957 | `fn_resetear_password(50, …)` | denegado |
| 19:58:47.957 | `DELETE FROM auditoria_login …` (borrar el rastro) | denegado |
| 19:58:50.012 | Tráfico legítimo de la app | éxito |

## 2. ¿Falla el escalamiento? (punto 2)

**Sí, los cuatro intentos fallan.** El log lo registra con `permission denied`, y el script lo verifica al final con las funciones de privilegios del catálogo:

```
 es_miembro_admin | puede_borrar_auditoria | puede_resetear
------------------+------------------------+----------------
 f                | f                      | f
```

`GRANT` falla porque ningún rol tiene `ADMIN OPTION` sobre `admin_datos`. `SET ROLE` falla porque `app_web` no es miembro, y las otras dos acciones, porque el `EXECUTE` y el `DELETE` no están otorgados. **El esquema de la Parte A no tiene un defecto de escalamiento.**

**Hallazgo sobre el diseño de la Parte A.** El escalamiento falla, pero el volcado del paso 3a **funcionó**: `rol_app_lectura` tiene `SELECT` sobre las columnas de contacto de **todas** las filas de `usuario`. El permiso de columna protege los hashes, pero no impide extraer los datos personales de los 1000 usuarios con una sola consulta. Es un defecto de mínimo privilegio a nivel de fila, y se trata en la decisión de contención.

## 3. Contraste: reconstrucción de la IA contra lo ejecutado (punto 5)

La IA recibió sólo el log anonimizado y el pedido. Su respuesta completa está en [`respuestas_ia/P2_reconstruccion_incidente.md`](respuestas_ia/P2_reconstruccion_incidente.md).

### Qué acertó

- **Separó bien el tráfico legítimo del malicioso.** Identificó las sesiones 603 y 614 como la app normal (`ip-01`, `foodstore-web`) y la 609 como anómala por **dos** señales a la vez: otro host y un cliente interactivo `psql`, con la misma credencial.
- **Entendió que la fuerza bruta es contra `fn_autenticar`** (lógica de negocio) y no contra el login del motor, y que la credencial de `app_web` tiene que estar comprometida porque la autenticación SCRAM fue exitosa.
- **El orden y los resultados de los cuatro intentos de escalamiento son correctos**, y concluye bien que la escalada y el borrado de auditoría fracasaron.
- **Las horas son correctas** (19:58:40 a 19:58:50) y no inventó una fecha distinta.
- **Varias de sus medidas coinciden con la decisión del equipo:** rotar la credencial de `app_web`, restringir en `pg_hba.conf` el origen permitido, preservar `auditoria_login` y forzar el cambio de contraseña de la cuenta víctima.

### Qué omitió

- **El volcado de datos personales.** Ni lo menciona como posibilidad. Entre el login exitoso (47.869) y el intento sobre `password_hash` (47.871) el log no muestra nada, porque `log_statement = 'mod'` no registra SELECT. La IA no advierte ese hueco, ni que el `SELECT … password_hash` fallido sugiere que el atacante estaba explorando la tabla.
- **La línea de `pg_hba.conf` usada.** El atacante entró por la regla `:10` y la app por la `:7`. Es la evidencia de que existe una regla habilitada para ese origen, que es exactamente la que hay que cerrar, y la IA no la usa.
- **Que el log no dice cómo obtuvo la contraseña.** Cuatro intentos y acierto al quinto encaja mejor con alguien que tenía una lista corta o la contraseña casi correcta que con fuerza bruta "a ciegas". La IA da por hecho que la "forzó".

### Qué afirmó sin sustento en el log (el error más significativo)

1. **"`app_web` no tiene SELECT directo sobre `usuario` … Por eso no hubo exfiltración."** Es **falso** y el log no lo sustenta. El único `permission denied` sobre `usuario` es para una consulta que pedía `password_hash`. De ahí la IA generalizó que `app_web` no puede leer la tabla, cuando en realidad lee seis columnas de todas las filas, y el paso 3a volcó las 1000. Además, la ausencia de un SELECT en un log configurado con `'mod'` **no prueba** que no hubo lectura: es ausencia de evidencia, no evidencia de ausencia. Si el equipo hubiera tomado esta conclusión como cierta, habría cerrado el incidente como "intento sin impacto" y no habría evaluado la exposición de datos de 1000 personas.
2. **El reset del paso 1 como posible causa del ataque** ("¿ingeniería social?"). Ese `UPDATE` fue la preparación del propio simulacro. La IA lo presenta con cautela ("sea causa directa o coincidencia"), pero construye una hipótesis de complicidad sólo a partir de la cercanía temporal. Investigarlo sería correcto en un caso real; tratarlo como señal del ataque, no.
3. **"¿La función no persiste o efectiviza el bloqueo?"** El log muestra `intentos=1…4` crecientes entre llamadas, o sea que el contador **sí** persiste. Lo que pasa es que el umbral es 5 y el atacante acertó antes. La IA propone "arreglar" algo que funciona como fue diseñado. El problema real es el umbral por cuenta sin límite por origen.
4. **"Opcionalmente exigir que la app use su `application_name` esperado."** `application_name` lo elige el cliente: el atacante puede enviar `foodstore-web` igual que la app. Sirve como señal de detección, no como control de acceso. Aplicada tal cual, esta recomendación daría una falsa sensación de seguridad.

## 4. Decisión de contención del equipo (punto 6)

La decisión es **del equipo**. Se tomó a partir de la evidencia: el log, la salida del simulacro y los catálogos de permisos. No se ejecutó ninguna medida de forma automática a partir de la respuesta de la IA: se adoptaron sólo las que el equipo verificó, y se descartaron las que no resistieron la verificación (sección 3).

**Inmediato (primeras horas):**

1. **Rotar la contraseña de `app_web`** y desplegar la nueva sólo en el servidor de la app, desde un gestor de secretos, nunca en un `.env` versionado. Mientras tanto, `ALTER ROLE app_web CONNECTION LIMIT 0` corta las conexiones nuevas, y `pg_terminate_backend` las sesiones que sigan abiertas desde un origen distinto del de la app.
2. **Cerrar el origen en `pg_hba.conf`:** `app_web` sólo desde la IP del servidor de la app. Se elimina la regla por la que entró el atacante (línea 10) y se recarga la configuración. La medida es por regla y no por IP en un firewall, porque el atacante podría cambiar de IP pero no de regla.
3. **Cuenta víctima `U-11b9a2f8` (ADMIN en la app):** bloquearla (`UPDATE usuario SET bloqueado = TRUE`, permitido a `rol_soporte`) y forzar el cambio de contraseña con `fn_resetear_password`, por soporte y verificando la identidad de la titular fuera de banda.
4. **Tratarlo como una posible exposición de datos personales de los 1000 usuarios** (nombre, email, teléfono, dirección), porque `app_web` podía leerlos y el log **no permite descartar** que se hayan leído. Se informa al responsable de datos de Food Store para evaluar las obligaciones de notificación. Contra lo que concluyó la IA, el incidente **no** se cierra como "sin impacto".

**Correctivo (antes de dar el incidente por cerrado):**

5. **Quitar a `rol_app_lectura` el `SELECT` directo sobre `usuario`.** La app lee el perfil del usuario autenticado mediante una función `SECURITY DEFINER` que recibe el `id` y devuelve una sola fila, o con Row Level Security. Así una credencial filtrada ya no permite volcar la tabla.
6. **Auditar las lecturas de `usuario`:** pgaudit con `pgaudit.log = 'read'` acotado a esa tabla mediante un rol auditor de objetos, o como mínimo `ALTER ROLE app_web SET log_statement = 'all'` durante la investigación. Sin esto, un incidente igual vuelve a ser invisible.
7. **Límite de intentos por origen y no sólo por cuenta.** `fn_autenticar` ya registra en `auditoria_login` la IP y la aplicación. Se agrega un rechazo cuando un mismo origen acumula fallos sobre varias cuentas, y una demora creciente entre intentos.

**Descartado:** "exigir `application_name`" (es falsificable, sección 3, punto 4) y "revisar el reset del paso 1 como posible ingeniería social" (fue la preparación del simulacro, verificado en el script).
