# Informe de concurrencia (Parte 2)

Proyecto Food Store — PostgreSQL 16.13. Salidas reales del motor.

**Estado inicial de cada experimento** (restaurado con `lab/reset.sql` antes de cada corrida): Hamburguesa clásica (1) con precio 8500 y stock 20; Hamburguesa doble (2) con stock 10; la Gaseosa (4) aparece en 1 línea de pedido con 2 unidades. «T» es el orden temporal real en que se enviaron los comandos. Las sentencias sin BEGIN corren en modo autocommit. Los triggers de la Parte 1 están activos.

**Pedido a la IA (igual para los cuatro escenarios):** «Te paso la transcripción de dos sesiones psql concurrentes sobre PostgreSQL 16 (esquema Food Store), con los comandos en orden y la salida real. Explicá qué pasó y qué nivel de aislamiento o qué mecanismo de bloqueo lo evitaría, y cómo lo verifico en el motor.»

## Escenario 1 — Lectura no repetible

**Escenario**

Lectura no repetible sobre `producto.precio`: la sesión A (READ COMMITTED) arma un ticket y lee dos veces el precio de la Hamburguesa clásica, mientras la sesión B aplica un aumento de lista (8500 → 9000) y confirma.

**Cómo se reprodujo (comandos exactos, en orden)**

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` |  |
| 2 | `SET TRANSACTION ISOLATION LEVEL READ COMMITTED;` |  |
| 3 | `SELECT id_producto, nombre, precio FROM producto WHERE id_producto = 1;` |  |
| 4 |  | `UPDATE producto SET precio = 9000 WHERE id_producto = 1;  -- autocommit` |
| 5 | `SELECT id_producto, nombre, precio FROM producto WHERE id_producto = 1;` |  |
| 6 | `COMMIT;` |  |
| 7 | `SELECT id_producto, nombre, precio FROM producto WHERE id_producto = 1;` |  |

**Qué se observó (salida real)**

*Salida real de cada comando*

```
-- T1 · Sesión A
   BEGIN
-- T2 · Sesión A
   SET
-- T3 · Sesión A
    id_producto |       nombre        | precio  
   -------------+---------------------+---------
              1 | Hamburguesa clásica | 8500.00
   (1 row)
-- T4 · Sesión B
   UPDATE 1
-- T5 · Sesión A
    id_producto |       nombre        | precio  
   -------------+---------------------+---------
              1 | Hamburguesa clásica | 9000.00
   (1 row)
-- T6 · Sesión A
   COMMIT
-- T7 · Sesión A
    id_producto |       nombre        | precio  
   -------------+---------------------+---------
              1 | Hamburguesa clásica | 9000.00
   (1 row)
```

Dentro de la **misma transacción**, A leyó 8500 en T3 y 9000 en T5. Si A usara esos valores para calcular el total del ticket, mezclaría dos precios distintos.

**Explicación de la IA (copiada tal cual)**

> **Herramienta: Claude (Anthropic), Claude Opus 5.5**
>
> Es una lectura no repetible. En READ COMMITTED, PostgreSQL toma un snapshot nuevo al comienzo de cada sentencia, no de la transacción. Por eso el segundo SELECT de A ya ve el UPDATE que B confirmó entre las dos lecturas (8500 → 9000).
>
> Para evitarlo, la transacción A tiene que correr en REPEATABLE READ (o SERIALIZABLE). En esos niveles el snapshot se toma en la primera sentencia de la transacción y se mantiene hasta el COMMIT, así que las dos lecturas devuelven 8500. Después del COMMIT, una consulta nueva sí ve 9000.
>
> En Food Store esto importa menos para el precio cobrado, porque `pedido_producto.precio_unitario` guarda el precio histórico (R4). Pero cualquier cálculo dentro de la transacción (total, validaciones) tiene que ver una foto consistente. Si A intentara actualizar esa fila en REPEATABLE READ, fallaría con 40001 y habría que reintentar.
>

**Verificación en el motor**

Se repitió exactamente el mismo experimento con `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ` en la sesión A:

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` |  |
| 2 | `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;` |  |
| 3 | `SELECT id_producto, nombre, precio FROM producto WHERE id_producto = 1;` |  |
| 4 |  | `UPDATE producto SET precio = 9000 WHERE id_producto = 1;  -- autocommit` |
| 5 | `SELECT id_producto, nombre, precio FROM producto WHERE id_producto = 1;` |  |
| 6 | `COMMIT;` |  |
| 7 | `SELECT id_producto, nombre, precio FROM producto WHERE id_producto = 1;` |  |

*Salida real con REPEATABLE READ*

```
-- T1 · Sesión A
   BEGIN
-- T2 · Sesión A
   SET
-- T3 · Sesión A
    id_producto |       nombre        | precio  
   -------------+---------------------+---------
              1 | Hamburguesa clásica | 8500.00
   (1 row)
-- T4 · Sesión B
   UPDATE 1
-- T5 · Sesión A
    id_producto |       nombre        | precio  
   -------------+---------------------+---------
              1 | Hamburguesa clásica | 8500.00
   (1 row)
-- T6 · Sesión A
   COMMIT
-- T7 · Sesión A
    id_producto |       nombre        | precio  
   -------------+---------------------+---------
              1 | Hamburguesa clásica | 9000.00
   (1 row)
```

Con REPEATABLE READ, A leyó **8500 en T3 y 8500 en T5**, aunque B ya había confirmado el aumento. Recién en T7, fuera de la transacción, ve 9000.

**Conclusión**

**La explicación de la IA se confirmó en el motor.** La lectura no repetible aparece en READ COMMITTED y desaparece con REPEATABLE READ.

## Escenario 2 — Lectura fantasma

**Escenario**

Lectura fantasma con COUNT y SUM sobre `pedido_producto`: A arma un reporte de ventas de la Gaseosa (producto 4) mientras B registra una venta nueva de 3 gaseosas en el pedido 2.

**Cómo se reprodujo (comandos exactos, en orden)**

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` |  |
| 2 | `SET TRANSACTION ISOLATION LEVEL READ COMMITTED;` |  |
| 3 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |
| 4 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 4, 3, 2500);  -- autocommit` |
| 5 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |
| 6 | `COMMIT;` |  |
| 7 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |

**Qué se observó (salida real)**

*Salida real de cada comando*

```
-- T1 · Sesión A
   BEGIN
-- T2 · Sesión A
   SET
-- T3 · Sesión A
    lineas | unidades 
   --------+----------
         1 |        2
   (1 row)
-- T4 · Sesión B
   INSERT 0 1
-- T5 · Sesión A
    lineas | unidades 
   --------+----------
         2 |        5
   (1 row)
-- T6 · Sesión A
   COMMIT
-- T7 · Sesión A
    lineas | unidades 
   --------+----------
         2 |        5
   (1 row)
```

Dentro de la misma transacción, el reporte pasó de **1 línea / 2 unidades** (T3) a **2 líneas / 5 unidades** (T5): apareció una fila «fantasma». La inserción de B también pasó por el trigger de la Parte 1, que descontó el stock.

**Explicación de la IA (copiada tal cual)**

> **Herramienta: Claude (Anthropic), Claude Opus 5.5**
>
> Es una lectura fantasma: el COUNT/SUM de A cambia (1/2 → 2/5) porque B insertó y confirmó una fila nueva que cumple el WHERE, y en READ COMMITTED cada sentencia ve lo confirmado hasta ese momento.
>
> Según el estándar SQL, REPEATABLE READ solo garantiza que no cambien las filas ya leídas y todavía admite fantasmas; el nivel que los prohíbe es SERIALIZABLE. En PostgreSQL, sin embargo, REPEATABLE READ se implementa con snapshot isolation (MVCC): la transacción no ve ninguna fila confirmada después de su snapshot, ni modificada ni nueva. Por eso, **en este motor, REPEATABLE READ ya evita el fantasma**.
>
> SERIALIZABLE también lo evita y además detecta anomalías de escritura sesgada (write skew). Para verificarlo, repetí en REPEATABLE READ y en SERIALIZABLE: en los dos casos la segunda lectura debería seguir dando 1/2.
>

**Verificación en el motor**

Repetición con REPEATABLE READ en la sesión A:

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` |  |
| 2 | `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;` |  |
| 3 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |
| 4 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 4, 3, 2500);  -- autocommit` |
| 5 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |
| 6 | `COMMIT;` |  |
| 7 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |

*Salida real con REPEATABLE READ*

```
-- T1 · Sesión A
   BEGIN
-- T2 · Sesión A
   SET
-- T3 · Sesión A
    lineas | unidades 
   --------+----------
         1 |        2
   (1 row)
-- T4 · Sesión B
   INSERT 0 1
-- T5 · Sesión A
    lineas | unidades 
   --------+----------
         1 |        2
   (1 row)
-- T6 · Sesión A
   COMMIT
-- T7 · Sesión A
    lineas | unidades 
   --------+----------
         2 |        5
   (1 row)
```

Repetición con SERIALIZABLE en la sesión A:

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` |  |
| 2 | `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;` |  |
| 3 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |
| 4 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 4, 3, 2500);  -- autocommit` |
| 5 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |
| 6 | `COMMIT;` |  |
| 7 | `SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;` |  |

*Salida real con SERIALIZABLE*

```
-- T1 · Sesión A
   BEGIN
-- T2 · Sesión A
   SET
-- T3 · Sesión A
    lineas | unidades 
   --------+----------
         1 |        2
   (1 row)
-- T4 · Sesión B
   INSERT 0 1
-- T5 · Sesión A
    lineas | unidades 
   --------+----------
         1 |        2
   (1 row)
-- T6 · Sesión A
   COMMIT
-- T7 · Sesión A
    lineas | unidades 
   --------+----------
         2 |        5
   (1 row)
```

En los dos niveles, A leyó **1 / 2 en T3 y en T5**: el fantasma no apareció. Recién después del COMMIT (T7) ve 2 / 5.

**Conclusión**

**La explicación de la IA se confirmó.** El dato importante es la diferencia entre el estándar y el motor: una respuesta basada solo en el estándar («para evitar fantasmas hace falta SERIALIZABLE») habría sido imprecisa para PostgreSQL, donde REPEATABLE READ ya los evita. Solo el experimento en el motor permite afirmarlo.

## Escenario 3 — Espera por bloqueo (FOR UPDATE)

**Escenario**

Espera por bloqueo: dos cajeros (sesiones A y B) quieren vender la Hamburguesa doble y piden `SELECT ... FOR UPDATE` sobre la misma fila de `producto`. La sesión C observa la espera con pg_stat_activity.

**Cómo se reprodujo (comandos exactos, en orden)**

| T | Sesión A | Sesión B | Sesión C (diagnóstico) |
|---|---|---|---|
| 1 | `SELECT pg_backend_pid();` |  |  |
| 2 |  | `SELECT pg_backend_pid();` |  |
| 3 | `BEGIN;` |  |  |
| 4 | `SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 2 FOR UPDATE;` |  |  |
| 5 |  | `BEGIN;` |  |
| 6 |  | `SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 2 FOR UPDATE;` |  |
| 7 |  |  | `SELECT pid, pg_blocking_pids(pid) AS bloqueado_por, wait_event_type, wait_event, state FROM pg_stat_activity WHERE datname = 'copia_trabajo' AND pid <> pg_backend_pid() ORDER BY pid;` |
| 8 | `UPDATE producto SET stock = stock - 1 WHERE id_producto = 2;` |  |  |
| 9 | `COMMIT;` |  |  |
| 10 |  | `(se destraba lo pedido en T6)` |  |
| 11 |  | `COMMIT;` |  |

**Qué se observó (salida real)**

*Salida real de cada comando*

```
-- T1 · Sesión A
    pg_backend_pid 
   ----------------
               592
   (1 row)
-- T2 · Sesión B
    pg_backend_pid 
   ----------------
               595
   (1 row)
-- T3 · Sesión A
   BEGIN
-- T4 · Sesión A
    id_producto |      nombre       | stock 
   -------------+-------------------+-------
              2 | Hamburguesa doble |    10
   (1 row)
-- T5 · Sesión B
   BEGIN
-- T6 · Sesión B
   -- (la sesión queda BLOQUEADA, sin devolver resultado)
-- T7 · Sesión C
    pid | bloqueado_por | wait_event_type |  wait_event   |        state        
   -----+---------------+-----------------+---------------+---------------------
    592 | {}            | Client          | ClientRead    | idle in transaction
    595 | {592}         | Lock            | transactionid | active
   (2 rows)
-- T8 · Sesión A
   UPDATE 1
-- T9 · Sesión A
   COMMIT
-- T10 · Sesión B (vuelve la respuesta de T6)
    id_producto |      nombre       | stock 
   -------------+-------------------+-------
              2 | Hamburguesa doble |     9
   (1 row)
-- T11 · Sesión B
   COMMIT
```

En T6, la sesión B **quedó bloqueada** sin devolver resultado. En T7, la sesión C muestra que el pid de B espera un Lock/transactionid y que `pg_blocking_pids` apunta al pid de A. Cuando A descontó una unidad y confirmó (T8–T9), B se destrabó sola (T10) y leyó el stock **ya actualizado (9)**, no el 10 que había cuando pidió el bloqueo. No hubo actualización perdida.

**Explicación de la IA (copiada tal cual)**

> **Herramienta: Claude (Anthropic), Claude Opus 5.5**
>
> La sesión B queda esperando porque `SELECT ... FOR UPDATE` toma un bloqueo exclusivo de fila que dura hasta que termina la transacción de A. Ningún otro FOR UPDATE, UPDATE o DELETE sobre esa fila puede avanzar hasta que A haga COMMIT o ROLLBACK. Las lecturas simples no se bloquean, gracias a MVCC. En pg_stat_activity la espera aparece como wait_event_type = Lock / transactionid, y pg_blocking_pids() devuelve el pid de A.
>
> Esto no es una anomalía a evitar: es el mecanismo que evita la actualización perdida del stock, y es el mismo que usa el trigger de la Parte 1. Cuando A confirma, B (en READ COMMITTED) vuelve a leer la versión nueva de la fila (9) y sigue. Si B estuviera en REPEATABLE READ o SERIALIZABLE, al destrabarse recibiría el error **40001** (could not serialize access due to concurrent update), así que la aplicación tendría que reintentar.
>
> Si no se quiere esperar, `FOR UPDATE NOWAIT` falla de inmediato con **55P03** (lock_not_available); también se puede fijar `lock_timeout`. El nivel de aislamiento no elimina la espera: la espera la produce el bloqueo.
>

**Verificación en el motor**

Repetición con la sesión B en REPEATABLE READ. B toma su snapshot antes de pedir el bloqueo:

| T | Sesión A | Sesión B | Sesión C (diagnóstico) |
|---|---|---|---|
| 1 | `SELECT pg_backend_pid();` |  |  |
| 2 |  | `SELECT pg_backend_pid();` |  |
| 3 | `BEGIN;` |  |  |
| 4 | `SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 2 FOR UPDATE;` |  |  |
| 5 |  | `BEGIN;` |  |
| 6 |  | `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;` |  |
| 7 |  | `SELECT id_producto, stock FROM producto WHERE id_producto = 1;  -- toma el snapshot de la transacción` |  |
| 8 |  | `SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 2 FOR UPDATE;` |  |
| 9 |  |  | `SELECT pid, pg_blocking_pids(pid) AS bloqueado_por, wait_event_type, wait_event, state FROM pg_stat_activity WHERE datname = 'copia_trabajo' AND pid <> pg_backend_pid() ORDER BY pid;` |
| 10 | `UPDATE producto SET stock = stock - 1 WHERE id_producto = 2;` |  |  |
| 11 | `COMMIT;` |  |  |
| 12 |  | `(se destraba lo pedido en T8)` |  |
| 13 |  | `\echo :LAST_ERROR_SQLSTATE` |  |
| 14 |  | `ROLLBACK;` |  |

*Salida real con B en REPEATABLE READ*

```
-- T1 · Sesión A
    pg_backend_pid 
   ----------------
               603
   (1 row)
-- T2 · Sesión B
    pg_backend_pid 
   ----------------
               606
   (1 row)
-- T3 · Sesión A
   BEGIN
-- T4 · Sesión A
    id_producto |      nombre       | stock 
   -------------+-------------------+-------
              2 | Hamburguesa doble |    10
   (1 row)
-- T5 · Sesión B
   BEGIN
-- T6 · Sesión B
   SET
-- T7 · Sesión B
    id_producto | stock 
   -------------+-------
              1 |    20
   (1 row)
-- T8 · Sesión B
   -- (la sesión queda BLOQUEADA, sin devolver resultado)
-- T9 · Sesión C
    pid | bloqueado_por | wait_event_type |  wait_event   |        state        
   -----+---------------+-----------------+---------------+---------------------
    603 | {}            | Client          | ClientRead    | idle in transaction
    606 | {603}         | Lock            | transactionid | active
   (2 rows)
-- T10 · Sesión A
   UPDATE 1
-- T11 · Sesión A
   COMMIT
-- T12 · Sesión B (vuelve la respuesta de T8)
   ERROR:  could not serialize access due to concurrent update
-- T13 · Sesión B
   40001
-- T14 · Sesión B
   ROLLBACK
```

B esperó igual (T8 y T9: la espera no depende del nivel), pero al destrabarse recibió **ERROR: could not serialize access due to concurrent update**, con SQLSTATE **40001**.

Repetición con NOWAIT:

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `SELECT pg_backend_pid();` |  |
| 2 |  | `SELECT pg_backend_pid();` |
| 3 | `BEGIN;` |  |
| 4 | `SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 2 FOR UPDATE;` |  |
| 5 |  | `BEGIN;` |
| 6 |  | `SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 2 FOR UPDATE NOWAIT;` |
| 7 |  | `\echo :LAST_ERROR_SQLSTATE` |
| 8 |  | `ROLLBACK;` |
| 9 | `ROLLBACK;` |  |

*Salida real con FOR UPDATE NOWAIT*

```
-- T1 · Sesión A
    pg_backend_pid 
   ----------------
               614
   (1 row)
-- T2 · Sesión B
    pg_backend_pid 
   ----------------
               617
   (1 row)
-- T3 · Sesión A
   BEGIN
-- T4 · Sesión A
    id_producto |      nombre       | stock 
   -------------+-------------------+-------
              2 | Hamburguesa doble |    10
   (1 row)
-- T5 · Sesión B
   BEGIN
-- T6 · Sesión B
   ERROR:  could not obtain lock on row in relation "producto"
-- T7 · Sesión B
   55P03
-- T8 · Sesión B
   ROLLBACK
-- T9 · Sesión A
   ROLLBACK
```

Con NOWAIT, B no esperó: falló de inmediato con **55P03**.

**Conclusión**

**La explicación de la IA se confirmó en las tres variantes.** La espera la produce el bloqueo de fila de FOR UPDATE en cualquier nivel de aislamiento. En READ COMMITTED, B continúa con el stock actualizado. En REPEATABLE READ aborta con 40001 y hay que reintentar. Con NOWAIT, o con lock_timeout, se evita la espera a cambio de un error inmediato.

## Escenario 4 — Interbloqueo real (opcional)

**Escenario**

Interbloqueo provocado por el propio trigger de stock de la Parte 1: A carga el pedido 2 con los productos 1 y después 2; B carga el pedido 4 con los productos 2 y después 1 (orden cruzado). Cada INSERT en pedido_producto bloquea la fila del producto con `FOR UPDATE` dentro del trigger.

**Cómo se reprodujo (comandos exactos, en orden)**

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` |  |
| 2 |  | `BEGIN;` |
| 3 | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 1, 1, 8500);` |  |
| 4 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (4, 2, 1, 11000);` |
| 5 | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 2, 1, 11000);` |  |
| 6 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (4, 1, 1, 8500);` |
| 7 | `(se destraba lo pedido en T5)` |  |
| 8 |  | `\echo :LAST_ERROR_SQLSTATE` |
| 9 | `COMMIT;` |  |
| 10 |  | `COMMIT;` |

**Qué se observó (salida real)**

*Salida real de cada comando*

```
-- T1 · Sesión A
   BEGIN
-- T2 · Sesión B
   BEGIN
-- T3 · Sesión A
   INSERT 0 1
-- T4 · Sesión B
   INSERT 0 1
-- T5 · Sesión A
   -- (la sesión queda BLOQUEADA, sin devolver resultado)
-- T6 · Sesión B
   ERROR:  deadlock detected
   DETAIL:  Process 625 waits for ShareLock on transaction 940; blocked by process 622.
   Process 622 waits for ShareLock on transaction 941; blocked by process 625.
   HINT:  See server log for query details.
   CONTEXT:  while locking tuple (0,24) in relation "producto"
   SQL statement "SELECT activo, stock FROM producto
       WHERE id_producto = NEW.id_producto
       FOR UPDATE"
   PL/pgSQL function fn_pedido_producto_valida_y_descuenta_stock() line 6 at SQL statement
-- T7 · Sesión A (vuelve la respuesta de T5)
   INSERT 0 1
-- T8 · Sesión B
   40P01
-- T9 · Sesión A
   COMMIT
-- T10 · Sesión B
   ROLLBACK
```

En T5, A quedó esperando la fila del producto 2, que tenía B. En T6, cuando B pidió el producto 1, se formó el ciclo. Pasado 1 s (deadlock_timeout), el motor abortó a B con **deadlock detected** (T6); el CONTEXT muestra que el bloqueo se pidió dentro de `fn_pedido_producto_valida_y_descuenta_stock`. T8 confirma el SQLSTATE **40P01**. A se destrabó (T7) y confirmó; el COMMIT de B devolvió ROLLBACK porque su transacción ya estaba abortada.

**Explicación de la IA (copiada tal cual)**

> **Herramienta: Claude (Anthropic), Claude Opus 5.5**
>
> Es un interbloqueo: A tiene bloqueado el producto 1 y espera el 2, mientras B tiene el 2 y espera el 1. Los bloqueos los toma el `SELECT ... FOR UPDATE` del trigger de stock, no el INSERT en sí. Pasado deadlock_timeout (1 s por defecto), PostgreSQL detecta el ciclo, elige una víctima y aborta su transacción con **40P01**. La otra sigue normalmente.
>
> Subir el nivel de aislamiento **no** lo evita: los bloqueos de fila se toman igual en todos los niveles, así que en SERIALIZABLE el deadlock se repite. Lo que lo evita es un **orden de bloqueo consistente**: que la aplicación inserte siempre las líneas de un pedido ordenadas por id_producto. Así, la segunda transacción espera en el primer producto en común en lugar de formar un ciclo. Además, la aplicación debe capturar 40P01 y reintentar el pedido completo.
>

**Verificación en el motor**

Repetición con SERIALIZABLE en ambas sesiones, para comprobar que el nivel de aislamiento **no** lo resuelve:

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` |  |
| 2 |  | `BEGIN;` |
| 3 | `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;` |  |
| 4 |  | `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;` |
| 5 | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 1, 1, 8500);` |  |
| 6 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (4, 2, 1, 11000);` |
| 7 | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 2, 1, 11000);` |  |
| 8 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (4, 1, 1, 8500);` |
| 9 | `(se destraba lo pedido en T7)` |  |
| 10 |  | `\echo :LAST_ERROR_SQLSTATE` |
| 11 | `COMMIT;` |  |
| 12 |  | `COMMIT;` |

*Salida real con SERIALIZABLE*

```
-- T1 · Sesión A
   BEGIN
-- T2 · Sesión B
   BEGIN
-- T3 · Sesión A
   SET
-- T4 · Sesión B
   SET
-- T5 · Sesión A
   INSERT 0 1
-- T6 · Sesión B
   INSERT 0 1
-- T7 · Sesión A
   -- (la sesión queda BLOQUEADA, sin devolver resultado)
-- T8 · Sesión B
   ERROR:  deadlock detected
   DETAIL:  Process 634 waits for ShareLock on transaction 945; blocked by process 631.
   Process 631 waits for ShareLock on transaction 946; blocked by process 634.
   HINT:  See server log for query details.
   CONTEXT:  while locking tuple (0,35) in relation "producto"
   SQL statement "SELECT activo, stock FROM producto
       WHERE id_producto = NEW.id_producto
       FOR UPDATE"
   PL/pgSQL function fn_pedido_producto_valida_y_descuenta_stock() line 6 at SQL statement
-- T9 · Sesión A (vuelve la respuesta de T7)
   INSERT 0 1
-- T10 · Sesión B
   40P01
-- T11 · Sesión A
   COMMIT
-- T12 · Sesión B
   ROLLBACK
```

El interbloqueo se repitió idéntico (40P01).

Repetición con el mecanismo que propuso la IA: las dos sesiones insertan las líneas ordenadas por id_producto (1 y después 2):

| T | Sesión A | Sesión B |
|---|---|---|
| 1 | `BEGIN;` |  |
| 2 |  | `BEGIN;` |
| 3 | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 1, 1, 8500);` |  |
| 4 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (4, 1, 1, 8500);` |
| 5 | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 2, 1, 11000);` |  |
| 6 | `COMMIT;` |  |
| 7 |  | `(se destraba lo pedido en T4)` |
| 8 |  | `INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (4, 2, 1, 11000);` |
| 9 |  | `COMMIT;` |
| 10 |  | `SELECT id_producto, stock FROM producto WHERE id_producto IN (1, 2) ORDER BY id_producto;` |

*Salida real con orden de inserción consistente*

```
-- T1 · Sesión A
   BEGIN
-- T2 · Sesión B
   BEGIN
-- T3 · Sesión A
   INSERT 0 1
-- T4 · Sesión B
   -- (la sesión queda BLOQUEADA, sin devolver resultado)
-- T5 · Sesión A
   INSERT 0 1
-- T6 · Sesión A
   COMMIT
-- T7 · Sesión B (vuelve la respuesta de T4)
   INSERT 0 1
-- T8 · Sesión B
   INSERT 0 1
-- T9 · Sesión B
   COMMIT
-- T10 · Sesión B
    id_producto | stock 
   -------------+-------
              1 |    18
              2 |     8
   (2 rows)
```

Sin interbloqueo: B esperó a A en el producto 1 (T4) y, cuando A confirmó, completó su pedido. Los dos descuentos quedaron aplicados: stock 20 → 18 y 10 → 8.

**Conclusión**

**La explicación de la IA se confirmó, incluida la parte negativa:** el nivel de aislamiento no resuelve el interbloqueo (en SERIALIZABLE se repitió) y el orden consistente sí. Para Food Store queda una regla de aplicación: insertar las líneas de un pedido ordenadas por id_producto y reintentar ante 40P01.

## Resumen de verificación en el motor

| Escenario | READ COMMITTED | REPEATABLE READ | SERIALIZABLE | Qué lo resuelve |
|---|---|---|---|---|
| Lectura no repetible (precio) | Ocurre (8500 → 9000) | No ocurre (8500 / 8500) | No ocurre (no probado: es más estricto que RR) | REPEATABLE READ o superior |
| Lectura fantasma (ventas) | Ocurre (1/2 → 2/5) | No ocurre (1/2 / 1/2) | No ocurre (1/2 / 1/2) | REPEATABLE READ en PostgreSQL (el estándar exige SERIALIZABLE) |
| Espera por FOR UPDATE (stock) | Espera y sigue con el stock nuevo (9) | Espera y aborta con 40001 | Igual que RR (no probado) | Es el mecanismo deseado; NOWAIT (55P03) o lock_timeout si no se quiere esperar |
| Interbloqueo (líneas de pedido) | Ocurre (40P01) | Igual que RC y SER (no probado) | Ocurre (40P01) | Insertar las líneas ordenadas por id_producto + reintento |

### DUIA de la Parte 2

| Campo | Completado |
|---|---|
| Herramienta | Claude (Anthropic), modelo Claude Opus 5.5, usado por chat en lugar de OpenCode (ver nota inicial) |
| Spec o prompt utilizado | El pedido textual del principio de este informe, junto con la transcripción de cada escenario. |
| Qué generó | Las cuatro explicaciones copiadas arriba. También `lab/experimentos.py` (abre dos procesos psql y les envía los comandos en el orden de la columna T) y `lab/reset.sql` (restaura el estado inicial entre corridas). En clase se reproduce igual con dos pestañas de psql, escribiendo cada comando en ese orden. |
| Qué se aceptó | Las cuatro explicaciones: todas se confirmaron en el motor. También las variantes de verificación propuestas (REPEATABLE READ, SERIALIZABLE, NOWAIT y orden consistente). |
| Qué se modificó o descartó, y por qué | Nada de las explicaciones. En el escenario 2 se destaca que la IA separó bien el estándar SQL del comportamiento de PostgreSQL. La consulta de diagnóstico de la sesión C se acortó (sin la columna query) para que la salida entre en el informe. |
| Verificación realizada | 11 corridas en total con salida real: 2 del escenario 1, 3 del escenario 2, 3 del escenario 3 y 3 del escenario 4, incluidas las de verificación. Cada conclusión cita el valor o el SQLSTATE observado (40001, 55P03, 40P01). |
