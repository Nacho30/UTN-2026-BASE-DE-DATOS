# P2 — Respuesta completa de la IA (Parte C.4)

- **Asistente:** Claude (Anthropic), ejecutado como un agente independiente.
- **Entrada:** sólo el prompt P2 de `docs/prompts.md` y el contenido completo de `docs/log_simulacro_anonimizado.txt`. Sin acceso al repositorio, a la base, al script del simulacro ni a esta conversación, y sin ningún contexto adicional.
- **Fecha:** 2026-10-19.
- **Contraste:** `docs/informe_incidente.md`, sección 3.

---

He analizado el fragmento de log de PostgreSQL. Es un análisis forense defensivo de un intento de intrusión que fue contenido por los permisos de la base. Abajo la reconstrucción cronológica y la hipótesis de contención.

## Reconstrucción cronológica (todo ocurre en ~10 segundos, 19:58:40–50)

**1) 19:58:40.732–40.738 — PID 601: desbloqueo administrativo (local, `postgres`)**
Una sesión local se autentica como `postgres` por método `peer` (consola del servidor, app=`psql`) y ejecuta:
`UPDATE usuario SET intentos_fallidos = 0, bloqueado = FALSE WHERE id IN (U-f2c23080, U-11b9a2f8);`
Es decir, un administrador (o algo con acceso al socket local) acaba de **resetear el contador de intentos fallidos y desbloquear** justamente a las dos cuentas que después aparecen en escena. Esto deja la cuenta `U-11b9a2f8` con el candado limpio segundos antes del ataque.

**2) 19:58:40.767–40.788 — PID 603: login legítimo (ip-01, app `foodstore-web`)**
Conexión desde `host=ip-01`, usuario `app_web`, auth `scram-sha-256`, `application_name=foodstore-web`. Llama `fn_autenticar` → **EXITO** para `U-f2c23080`. Patrón normal de la aplicación: viene del servidor de la app, con el nombre de aplicación correcto, sesión de 21 ms.

**3) 19:58:43.820–47.960 — PID 609: la sesión sospechosa (ip-02, app `psql`)**
Esta es la anómala. Usa **las mismas credenciales `app_web`** pero desde **otro host (`ip-02`)** y con un **cliente interactivo `psql`**, no la aplicación. Secuencia:
- Cinco llamadas a `fn_autenticar` contra `U-11b9a2f8`, etiquetadas en los STATEMENT como `intento_1` … `intento_5_exito`, espaciadas ~1 s:
  - intentos 1–4 → **FALLO** `motivo=password_incorrecta` (contador llega a `intentos=4`)
  - intento 5 → **EXITO**
  Esto es un **ataque de fuerza bruta / adivinación de contraseña** contra una sola cuenta, claramente scripteado.
- Tras adivinarla, intenta una cadena de acciones de escalada y exfiltración, **todas rechazadas por permisos**:
  - `SELECT id, email, password_hash FROM usuario LIMIT 5;` → *permission denied for table usuario* (volcado de credenciales)
  - `GRANT admin_datos TO rol_app_lectura;` → *permission denied to grant role* (escalada de rol)
  - `SET ROLE admin_datos;` → *permission denied to set role*
  - `SELECT fn_resetear_password(U-11b9a2f8, '<redactado>');` → *permission denied for function*
  - `DELETE FROM auditoria_login WHERE usuario_id = U-11b9a2f8;` → *permission denied for table auditoria_login* (borrado de rastro / anti-forense)
- Desconecta a los ~4,1 s.

**4) 19:58:49.994–50.013 — PID 614: vuelta a la normalidad (ip-01, app `foodstore-web`)**
Login legítimo normal de nuevo desde `ip-01` con `application_name=foodstore-web`, `fn_autenticar` → EXITO para `U-f2c23080`.

## Qué pasó, en una frase
Alguien, usando la credencial compartida `app_web` desde un host no habitual (`ip-02`) y con `psql`, forzó la contraseña de la cuenta de aplicación `U-11b9a2f8` en 5 intentos y, ya "autenticado" a nivel de la función de negocio, intentó leer hashes, escalar roles, resetear contraseñas y borrar la auditoría — pero el modelo de permisos del rol `app_web` bloqueó todo eso.

## Señales clave
- **La fuerza bruta es a nivel de `fn_autenticar` (lógica de negocio), no del login de Postgres.** La conexión Postgres sí es válida (scram OK); lo que se adivina es la contraseña del usuario de la aplicación mediante llamadas repetidas a la función.
- **El bloqueo por intentos no frenó el ataque:** el contador llegó a `intentos=4` sin bloquear y el 5º fue exitoso. Además, el reset administrativo del paso 1 limpió el candado de `U-11b9a2f8` segundos antes — sea causa directa o coincidencia, hay que investigarlo (¿ingeniería social?, ¿umbral de bloqueo > 4?, ¿la función no persiste/efectiviza el bloqueo?).
- **La credencial `app_web` está comprometida y mal aislada:** la misma cuenta se usa desde el servidor de la app (`ip-01`, app `foodstore-web`) y desde un host interactivo (`ip-02`, app `psql`). El `application_name` y el host delatan el uso ilegítimo.
- **Lo que funcionó (contención por diseño):** el principio de mínimo privilegio sostuvo el ataque. `app_web` no tiene SELECT directo sobre `usuario`, ni GRANT/SET ROLE sobre `admin_datos`, ni acceso a `fn_resetear_password` ni a `auditoria_login`. Por eso no hubo exfiltración, ni escalada, ni borrado de la bitácora — y la tabla `auditoria_login` sigue intacta para el forense.

## Hipótesis de contención y recomendaciones
1. **Cortar la sesión y el origen ya:** terminar cualquier sesión viva de `app_web` desde `ip-02` (`pg_terminate_backend`) y bloquear `ip-02` en firewall.
2. **Rotar la contraseña de `app_web` de inmediato** (está comprometida) y, mejor aún, dar credenciales por servicio/host en vez de una compartida.
3. **Endurecer `pg_hba.conf`:** restringir `app_web` para que sólo pueda conectar desde las IP de los servidores de aplicación (`ip-01`), negando conexiones desde hosts como `ip-02`. Opcionalmente exigir que la app use su `application_name` esperado.
4. **Arreglar el control de intentos dentro de `fn_autenticar`:** que el bloqueo efectivamente dispare (umbral ≤ cierto número, que persista/commit el incremento) y agregar backoff/rate-limit; hoy 4 fallos no bloquean.
5. **Revisar el desbloqueo administrativo del paso 1:** por qué `postgres` limpió `intentos_fallidos`/`bloqueado` de `U-11b9a2f8` justo antes; confirmar que fue legítimo y no inducido.
6. **Preservar y revisar `auditoria_login`** (sobrevivió porque el DELETE fue denegado) para medir alcance real sobre `U-11b9a2f8`, y forzar reset de contraseña de esa cuenta.
7. **Mantener/auditar el modelo de privilegios** que contuvo el incidente: es la razón por la que esto fue un intento fallido y no una brecha.
