# Bitácora de uso de IA — TP Unidad 8

Proyecto Food Store · Bases de Datos II · UTN · Ignacio Martín Rodríguez · 02/11/2026

**Herramienta usada:** Claude (Anthropic), en una sesión de Claude Code, en lugar de Kiro y OpenCode (ver `DUIA.md`). Todo lo generado se ejecutó contra `copia_trabajo` o contra bases descartables (`revision*`) y contra copias de la base de la tablet. Nada se aceptó sin una salida que lo respalde en `docs/evidencia/`.

**Datos:** a la IA sólo se le dio el esquema del repositorio y los datos ficticios de `datos_iniciales.sql` (correos `@example.com`). No se le pasaron contraseñas ni datos personales; la tablet usa el alias `vendedor_feria_01`.

| # | Qué se le pidió | Qué se aceptó | Qué se descartó y por qué | Evidencia |
|---|---|---|---|---|
| 1 | Escribir el spec (`requirements.md` con 4 requisitos EARS ligados a casos, `design.md`, `tasks.md`) **antes** del código, a partir de la consigna | Los 4 requisitos (C2, C3, C4, C6) y el diseño de lápidas y estado final de la cola | Nada. Decisión de diseño que hay que saber defender: la tablet **no** valida stock al armar el borrador, porque el stock que ve es viejo y la regla de oro dice que lo decide el servidor | `docs/kiro/` |
| 2 | Generar el esquema SQLite, la carga de la instantánea y el semáforo a partir de las tareas | Esquema `STRICT` con `CHECK`, FK y trigger de estado final; semáforo con un solo `UPDATE ... FROM` | Nada. Decisión a defender: `snapshot_servidor` guarda los booleanos como texto `t`/`f`, tal como los exporta psql (con `CHECK`), y la conversión a 0/1 se hace al pasar a `producto_cache`; así `.import` nunca falla por tipo | `01_*.txt`, casos C2–C6 |
| 3 | Mostrar en el semáforo un identificador corto de cada solicitud | La salida con prefijo y sufijo del UUID (`52…0001`) | **Descartada la primera versión**, que recortaba a los primeros 8 caracteres: en C2 las dos solicitudes aparecían iguales (`52000000`), lo que en la defensa se lee como un duplicado | `03_caso_c2.txt` |
| 4 | Code review de los scripts de la cursada (rol del agente Plan de OpenCode) | 3 correcciones (H1, H2, H4) y una limitación documentada (L1) | Descartado el índice sobre `pedido_producto(id_pedido)` (H3): la PK compuesta ya lo cubre (EXPLAIN). Descartado también "UPDATE sin WHERE" en `lab/reset.sql` (H5): es el reset deliberado del laboratorio | `09_code_review.txt`, `10_*.txt` |
| 5 | Agregar a `lab/reset.sql` una guarda para que sólo corra sobre `copia_trabajo` | La guarda con `DO ... RAISE EXCEPTION` **más** `\set ON_ERROR_STOP on` | **Descartada la primera versión** (sólo el `DO`): al verificarla sobre `revision_despues`, psql informó el error y siguió con los `DELETE`/`UPDATE` (stock total 133 en vez de 124). Sin `ON_ERROR_STOP`, la guarda no protege nada | `09_code_review.txt` (H4) |
| 6 | Correr los scripts de la tablet sin el CLI `sqlite3`, que no estaba instalado ni se podía instalar en el entorno | `herramientas/sqlite_cli.py`, un sustituto mínimo que imita `sqlite3 base < script` (incluido `.import` y seguir tras un error) | Se descartó reescribir los scripts en Python: los `.sql` quedan tal cual para el CLI oficial o DB Browser. **Pendiente:** correrlos una vez con el `sqlite3` oficial antes de la defensa | `correr_todo.sh` |

## Lo que tengo que poder explicar en la defensa

- Por qué el `PRAGMA foreign_keys = ON;` está al principio de **cada** script (evidencia 13: sin él, el ítem con producto 999 se inserta).
- Por qué `SIMULADO_APROBADO` no es una venta (evidencia 10: dos verdes que juntos superan el stock; el servidor rechaza el segundo).
- Por qué los productos dados de baja no se borran de `producto_cache` (C4: la FK de los borradores).
