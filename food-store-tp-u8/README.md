# Food Store — TP Unidad 8: la base de la tablet y el cierre de la capa de datos

Bases de Datos II · Tecnicatura Universitaria en Programación · UTN · 2026
Alumno: Ignacio Martín Rodríguez

**Repositorio (con el historial de commits):** https://github.com/Nacho30/utn-2026-base-de-datos/tree/tp-unidad-8
— rama `tp-unidad-8`, carpeta `food-store-tp-u8/`. La Unidad 7 está en la rama `tp-unidad-7`.

El food truck vende en una feria sin señal. La tablet guarda una copia del catálogo en **SQLite** y arma borradores; la sincronización con **PostgreSQL** se simula con un semáforo. **El móvil propone, el servidor dispone:** la tablet nunca escribe en PostgreSQL y `SIMULADO_APROBADO` no es una venta.

## Qué hay en cada lugar

```
food-store-tp-u8/
├── README.md                     este archivo (orden desde cero y ensayo de defensa)
├── correr_todo.sh                crea todo desde cero y corre las consignas 1 y 2, con evidencia
├── movil/
│   ├── schema_sqlite.sql         1.b  cinco tablas STRICT con CHECK, FK y trigger
│   ├── cargar_snapshot.sql       2.a  importa el CSV y actualiza producto_cache
│   ├── pruebas_sqlite.sql        1.c  COMMIT, ROLLBACK, C1 y C7
│   ├── semaforo.sql              2.b  evalúa las solicitudes PENDIENTE
│   ├── casos/                    2.c  la parte de la tablet de C2 a C6
│   ├── servidor_snapshot.csv     2.a  última instantánea exportada (la inicial está en docs/evidencia/snapshots/)
│   └── foodstore_movil.db        la base de la tablet al terminar todos los casos
├── servidor/
│   ├── 01_vista_snapshot.sql     2.a  vista v_snapshot_movil (en copia_trabajo)
│   ├── exportar_snapshot.sql     2.a  \copy a movil/servidor_snapshot.csv
│   ├── casos/                    2.c  la preparación de C2, C3 y C4 en el servidor
│   ├── estado_servidor.sql            foto del servidor
│   └── verificacion_final.sql    2.c  pedidos y stock no cambiaron
├── revision/                     3.c  verificación de cada hallazgo del code review
├── herramientas/sqlite_cli.py    sustituto del CLI sqlite3 (sólo si no está instalado)
└── docs/
    ├── informe.pdf               1.a, 2.c, 3.a, 3.b y 3.c (3 páginas)
    ├── kiro/                     4.a  requirements.md · design.md · tasks.md
    ├── bitacora_ia.md            4.b
    ├── DUIA.md                   4.b
    └── evidencia/                salidas reales de cada paso (00 a 14) y las instantáneas
```

Cambios del code review fuera de esta carpeta: `migraciones/002_lineas_de_pedido_inmutables.sql`, `pruebas/002_pruebas_lineas_inmutables.sql`, `programables/funciones_procedimientos.sql` (H1) y `lab/reset.sql` (H4).

En el **.zip de entrega**, esos scripts base del repositorio (schema, datos, migraciones, programables, pruebas, `lab/reset.sql`, `protocolo_seguridad.md`) van en `proyecto/`, y `correr_todo.sh` los toma de ahí. `revision/verificar_hallazgos.sh` necesita el repositorio git (compara contra la rama `tp-unidad-7`).

## Orden para crear todo desde cero

Requisitos: PostgreSQL 16+ (`psql`, `createdb`) con acceso local y SQLite 3.37+ (`sqlite3` o DB Browser for SQLite). Sólo se usan las bases `plantilla_base` y `copia_trabajo` (ver `../protocolo_seguridad.md`).

**Automático** (Linux, macOS o Git Bash en Windows), desde `food-store-tp-u8/`:

```bash
./correr_todo.sh                              # consignas 1 y 2 → docs/evidencia/00 a 08
./revision/verificar_hallazgos.sh > docs/evidencia/09_code_review.txt 2>&1   # también → 12
./revision/correr_verificaciones_tablet.sh    # → docs/evidencia/10, 11 y 13
# 14 (C1 con PostgreSQL detenido) es manual: detener el servidor y correr la consulta
# del catálogo de pruebas_sqlite.sql sobre movil/foodstore_movil.db.
python3 docs/generar_informe.py               # → docs/informe.pdf
```

**A mano**, paso por paso (lo mismo que hace `correr_todo.sh`):

```bash
# 1. Servidor de PRUEBAS (desde la raíz del repositorio)
createdb plantilla_base
for f in schema.sql migraciones/001_restricciones_reglas_negocio.sql \
         migraciones/002_lineas_de_pedido_inmutables.sql \
         programables/funciones_procedimientos.sql datos_iniciales.sql; do
  psql -X -v ON_ERROR_STOP=1 -d plantilla_base -f "$f"; done
createdb -T plantilla_base copia_trabajo

cd food-store-tp-u8
psql -X -d copia_trabajo -f servidor/01_vista_snapshot.sql
psql -X -d copia_trabajo -f servidor/exportar_snapshot.sql     # → movil/servidor_snapshot.csv

# 2. Tablet (desde movil/)
cd movil
sqlite3 foodstore_movil.db < schema_sqlite.sql
sqlite3 foodstore_movil.db < cargar_snapshot.sql
sqlite3 foodstore_movil.db < pruebas_sqlite.sql      # los errores que muestra son los casos negativos esperados
sqlite3 foodstore_movil.db < semaforo.sql

# 3. Cada caso: borrador en la tablet → cambio en el servidor → instantánea nueva → semáforo
sqlite3 foodstore_movil.db < casos/c2_borrador.sql
(cd .. && psql -X -d copia_trabajo -f servidor/casos/c2_subir_precio.sql \
       && psql -X -d copia_trabajo -f servidor/exportar_snapshot.sql)
sqlite3 foodstore_movil.db < cargar_snapshot.sql
sqlite3 foodstore_movil.db < semaforo.sql            # → CONFLICTO
sqlite3 foodstore_movil.db < casos/c2_acepta.sql
sqlite3 foodstore_movil.db < semaforo.sql            # → SIMULADO_APROBADO
#    C3: casos/c3_borrador.sql + servidor/casos/c3_ajustar_stock.sql   → RECHAZADO
#    C4: casos/c4_borrador.sql + servidor/casos/c4_baja_producto.sql   → RECHAZADO; después casos/c4_catalogo.sql
#    C5: casos/c5_borrador.sql, exportar y cargar sin cambios          → SIMULADO_APROBADO
#    C6: casos/c6_reenvio.sql y semaforo.sql otra vez                  → error de PK, 0 evaluadas

# 4. Cierre (desde food-store-tp-u8/)
psql -X -d copia_trabajo -f servidor/verificacion_final.sql
```

En PowerShell, `<` no funciona: usar `Get-Content schema_sqlite.sql | sqlite3 foodstore_movil.db`, o abrir `foodstore_movil.db` en DB Browser y ejecutar cada script en la pestaña *Ejecutar SQL* (la línea `.import` de `cargar_snapshot.sql` se reemplaza por *Archivo → Importar → Tabla desde CSV* sobre `snapshot_servidor`).

**Sobre la evidencia:** el entorno donde se generó no tenía el CLI `sqlite3`, así que `correr_todo.sh` usó `herramientas/sqlite_cli.py` (SQLite 3.53.1 de Python), que corre los mismos `.sql` sin cambios. Con `sqlite3` instalado, el script lo usa directamente.

## Resultados

| Caso | Esperado | Obtenido | Evidencia |
|---|---|---|---|
| C1 | catálogo sin servidor | 6 productos a la venta, leídos de `producto_cache`; también con PostgreSQL detenido | `02_pruebas_sqlite.txt`, `14_c1_sin_servidor.txt` |
| C2 | CONFLICTO, luego SIMULADO_APROBADO | CONFLICTO (8.500,00 → 9.200,00); la solicitud nueva, SIMULADO_APROBADO | `03_caso_c2.txt` |
| C3 | RECHAZADO | RECHAZADO: pide 5 y quedan 3 | `04_caso_c3.txt` |
| C4 | RECHAZADO; fuera del catálogo, la fila queda | RECHAZADO: dado de baja; `eliminado = 1`, el borrador sigue válido | `05_caso_c4.txt` |
| C5 | SIMULADO_APROBADO | SIMULADO_APROBADO | `06_caso_c5.txt` |
| C6 | error de PK y no reevalúa | `UNIQUE constraint failed: cola_sync.solicitud_uuid`; 0 solicitudes evaluadas | `07_caso_c6.txt` |
| C7 | errores sin filas nuevas | `CHECK` y `FOREIGN KEY`; 1 borrador, 2 ítems y 1 solicitud antes y después | `02_pruebas_sqlite.txt` |
| PostgreSQL | sin cambios por la simulación | 4 pedidos y 6 líneas; servidor = última instantánea (0 diferencias) | `08_verificacion_final.txt` |

## Ensayo de defensa (10 minutos)

| Tiempo | Qué mostrar | Qué decir |
|---|---|---|
| 0:00–2:30 | **El mapa** (informe, sección 3.a) | Quién manda sobre cada dato: PostgreSQL decide precio, stock y ventas; MongoDB es una copia de lectura de los pedidos (U7); SQLite tiene una copia del catálogo y los borradores, que son de la tablet hasta que el servidor los evalúe. |
| 2:30–7:00 | **Un caso en vivo: C2** | Armar el borrador (`casos/c2_borrador.sql`), subir el precio en `copia_trabajo`, exportar y cargar la instantánea, correr `semaforo.sql` → CONFLICTO con el motivo; `c2_acepta.sql` y otra vez el semáforo → SIMULADO_APROBADO. Cerrar con `verificacion_final.sql`: los pedidos siguen siendo 4. Si sobra tiempo, C6: el mismo UUID choca con la PK. |
| 7:00–9:30 | **Un hallazgo de la IA: H1** | `sp_registrar_pedido` salteaba en silencio un producto inexistente: un carrito de 2 productos quedaba con 1 línea. Se comprobó con `CALL` dentro de `BEGIN ... ROLLBACK` y se corrigió con `IF NOT FOUND THEN RAISE`. Contar también uno descartado: el índice sobre `pedido_producto(id_pedido)`, innecesario porque la PK compuesta ya lo cubre (EXPLAIN). |
| 9:30–10:00 | Cierre | `SIMULADO_APROBADO` no es una venta: dos verdes de 2 flanes con 3 en stock; el servidor rechaza el segundo (evidencia 10). |

Preguntas probables: por qué centavos; por qué `PRAGMA foreign_keys` en cada script; por qué no se borran los productos dados de baja de la tablet; qué pasa si se restaura un respaldo viejo; dónde iría la protección real contra duplicados.
