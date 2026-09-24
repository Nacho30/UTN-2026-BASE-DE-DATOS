# Ejercicio de lectura crítica (Parte 3)

Proyecto Food Store — PostgreSQL 16.13. Salidas reales del motor.

## Script 1 — «dar de baja las funciones de películas retiradas de cartel»

**Datos de partida (catedra_demo)**

```
 id |          titulo          | en_cartel | activa 
----+--------------------------+-----------+--------
  1 | La ciudad de los espejos | t         | t
  2 | La ciudad de los espejos | t         | t
  3 | Tormenta en el sur       | t         | t
  4 | El último faro           | f         | t
  5 | Números primos           | f         | t
```

**Qué filas afectaría realmente, tal como está escrito**

*Ensayo en transacción (salida real)*

```
BEGIN;
UPDATE funcion SET activa = FALSE;
UPDATE 5
SELECT count(*) FILTER (WHERE NOT activa) AS inactivas, count(*) AS total FROM funcion;
 inactivas | total 
-----------+-------
         5 |     5
ROLLBACK;
```

**Afecta a TODAS las filas de funcion** (5 de 5), porque no tiene WHERE. Desactiva también las funciones 1, 2 y 3, de películas que siguen en cartel: deja de vender entradas para toda la cartelera.

**Por qué no coincide con la consigna que dice cumplir**

El comentario dice «funciones de películas retiradas de cartel», pero el script no menciona la película ni la condición de retiro. Ese dato está en `pelicula.en_cartel`, así que hace falta vincular las dos tablas. La sintaxis es correcta y el motor no da ningún error: es el patrón de los casos reales de 6.1, una intención razonable con un efecto distinto del pedido.

**Versión corregida**

```
-- Da de baja (borrado lógico) solo las funciones de películas que ya no están en cartel.
BEGIN;
UPDATE funcion f
SET    activa = FALSE
FROM   pelicula p
WHERE  f.pelicula_id = p.id
  AND  p.en_cartel = FALSE      -- la condición que pide la consigna
  AND  f.activa = TRUE;         -- solo las que cambian: conteo exacto y script idempotente
ROLLBACK;  -- cambiar por COMMIT solo si el conteo coincide con el esperado
```

*Verificación de la versión corregida (salida real)*

```
UPDATE 2
 id |          titulo          | en_cartel | activa 
----+--------------------------+-----------+--------
  1 | La ciudad de los espejos | t         | t
  2 | La ciudad de los espejos | t         | t
  3 | Tormenta en el sur       | t         | t
  4 | El último faro           | f         | f
  5 | Números primos           | f         | f
```

Solo se desactivan las funciones 4 y 5, las de las dos películas fuera de cartel.

## Script 2 — «limpiar las categorías sin productos asociados»

**Datos de partida (catedra_demo; en el esquema genérico, producto.categoria_id admite NULL)**

```
 id |  nombre   | productos       -- categoria_id en producto:
----+-----------+-----------      --   NULL, 1, 1, 2, 2, 3
  1 | Bebidas   |         2
  2 | Snacks    |         2
  3 | Combos    |         1
  4 | Golosinas |         0
  5 | Helados   |         0
```

**Qué filas afectaría realmente, tal como está escrito**

*Ensayo en transacción (salida real)*

```
BEGIN;
DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto);
DELETE 0
ROLLBACK;
```

**No borra ninguna fila** (DELETE 0), aunque hay dos categorías vacías. El motor no avisa nada.

**Por qué no coincide con la consigna que dice cumplir**

La subconsulta devuelve {NULL, 1, 1, 2, 2, 3}. `4 NOT IN (NULL, 1, 2, 3)` equivale a `4 <> NULL AND 4 <> 1 AND ...`, y `4 <> NULL` da NULL (desconocido), no TRUE. Con la lógica de tres valores, toda la condición da NULL y la fila no se borra. **Basta un solo NULL en producto.categoria_id para que el NOT IN no devuelva ninguna fila.** El efecto depende de los datos: el día que ese producto se categoriza, el mismo script empieza a borrar. Y si producto estuviera vacía, borraría todas las categorías.

**Versión corregida (esquema genérico)**

```
-- Opción A (recomendada): NOT EXISTS no tiene el problema del NULL.
BEGIN;
DELETE FROM categoria c
WHERE NOT EXISTS (SELECT 1 FROM producto p WHERE p.categoria_id = c.id)
RETURNING c.id, c.nombre;
ROLLBACK;  -- COMMIT solo si la lista es la esperada
-- Opción B: NOT IN excluyendo los NULL de la subconsulta.
-- DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto WHERE categoria_id IS NOT NULL);
```

*Verificación (salida real)*

```
 id |  nombre   
----+-----------
  5 | Helados
  4 | Golosinas
DELETE 2
```

## Script 2 trasladado a Food Store

En Food Store, `producto.id_categoria` es **NOT NULL** (R1), así que la trampa del NULL no puede darse: el NOT IN adaptado (`id_categoria NOT IN (SELECT id_categoria FROM producto)`) encuentra la categoría vacía. Pero sigue siendo incorrecto por otra razón del propio proyecto: **R7 dice que las categorías no se borran físicamente**, sino que se dan de baja con `activo = FALSE`.

*copia_trabajo de Food Store (salida real)*

```
 id_categoria |    nombre    | activo | productos
--------------+--------------+--------+-----------
            1 | Hamburguesas | t      |         2
            2 | Pizzas       | t      |         2
            3 | Bebidas      | t      |         2
            4 | Postres      | t      |         1
            5 | Ensaladas    | t      |         0

BEGIN;   -- script original adaptado a los nombres de Food Store
DELETE FROM categoria WHERE id_categoria NOT IN (SELECT id_categoria FROM producto)
RETURNING id_categoria, nombre;
 id_categoria |  nombre
--------------+-----------
            5 | Ensaladas
DELETE 1          -- borra físicamente: viola R7
ROLLBACK;

BEGIN;   -- corrección Food Store: baja lógica (R7) con NOT EXISTS
UPDATE categoria c SET activo = FALSE
WHERE c.activo
  AND NOT EXISTS (SELECT 1 FROM producto p WHERE p.id_categoria = c.id_categoria)
RETURNING c.id_categoria, c.nombre, c.activo;
 id_categoria |  nombre   | activo
--------------+-----------+--------
            5 | Ensaladas | f
UPDATE 1
ROLLBACK;

BEGIN;   -- red de seguridad: DELETE de una categoría con productos
DELETE FROM categoria WHERE id_categoria = 1;
ERROR:  update or delete on table "categoria" violates foreign key constraint
        "producto_id_categoria_fkey" on table "producto"
DETAIL:  Key (id_categoria)=(1) is still referenced from table "producto".
ROLLBACK;
```

El script original haría un DELETE físico de Ensaladas, contra R7. La corrección para Food Store es un UPDATE de baja lógica con NOT EXISTS, que respeta R7 y no depende de que la columna sea NOT NULL. La FK con ON DELETE RESTRICT confirma la red de seguridad: un DELETE sobre una categoría con productos es rechazado por el motor.

### DUIA de la Parte 3

| Campo | Completado |
|---|---|
| Herramienta | Claude (Anthropic), modelo Claude Opus 5.5, usado por chat en lugar de OpenCode (ver nota inicial) |
| Spec o prompt utilizado | «Para cada uno de estos dos scripts, decime qué filas afectaría tal como está escrito, por qué no cumple lo que dice su comentario y una versión corregida. Probalo dentro de BEGIN … ROLLBACK, y trasladá el script 2 a mi esquema Food Store.» |
| Qué generó | El análisis de ambos scripts, las versiones corregidas (UPDATE … FROM pelicula; NOT EXISTS / NOT IN con IS NOT NULL), la versión Food Store (UPDATE de baja lógica) y las consultas de verificación. |
| Qué se aceptó | El diagnóstico: el script 1 afecta todas las filas por no tener WHERE, y el script 2 no afecta ninguna por el NULL en el NOT IN. También las correcciones. |
| Qué se modificó o descartó, y por qué | Se agregó `AND f.activa = TRUE` al script 1 para que el conteo refleje solo los cambios reales. En Food Store se descartó cualquier DELETE físico de categoria y se reemplazó por baja lógica, por R7. |
| Verificación realizada | Script 1: UPDATE 5 original frente a UPDATE 2 corregido. Script 2 genérico: DELETE 0 original frente a DELETE 2 corregido. En Food Store: DELETE 1 (Ensaladas, contra R7) frente a UPDATE 1 de baja lógica; DELETE de una categoría con productos rechazado por la FK. Todo dentro de BEGIN … ROLLBACK. |
