#!/usr/bin/env bash
# =====================================================================
# Food Store — TP Unidad 8 · correr_todo.sh
# Crea todo desde cero y corre la consigna 1 y 2 en orden, guardando la
# salida de cada paso en docs/evidencia/. Correr desde food-store-tp-u8/.
#   ./correr_todo.sh
# Requiere: psql/createdb de PostgreSQL 16 con acceso local, y sqlite3
# (si no está, usa herramientas/sqlite_cli.py con el SQLite de Python).
# Sólo toca las bases plantilla_base y copia_trabajo (protocolo_seguridad.md).
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
# Scripts base del proyecto (schema, datos, migraciones, programables): en el
# repositorio están en la carpeta de arriba; en el .zip de entrega, en proyecto/.
if [[ -f ../schema.sql ]]; then RAIZ=..; else RAIZ=proyecto; fi
EVID=docs/evidencia
mkdir -p "$EVID/snapshots"
rm -f "$EVID"/0[0-8]_*.txt "$EVID"/snapshots/*.csv   # 09 a 13 los genera revision/

PSQL="psql -X -v ON_ERROR_STOP=1"
pg()   { $PSQL -d copia_trabajo -f "$1"; }
movil() {   # corre un script de la tablet desde movil/
    if command -v sqlite3 >/dev/null; then (cd movil && sqlite3 foodstore_movil.db < "$1")
    else (cd movil && python3 ../herramientas/sqlite_cli.py foodstore_movil.db "$1"); fi
}
paso() { echo; echo "######## $1"; }
snapshot() {   # exporta, guarda una copia con nombre y la carga en la tablet
    pg servidor/exportar_snapshot.sql
    cp movil/servidor_snapshot.csv "$EVID/snapshots/$1.csv"
    movil cargar_snapshot.sql
}

{
paso "Servidor: plantilla_base y copia_trabajo desde cero"
dropdb --if-exists copia_trabajo
dropdb --if-exists plantilla_base
createdb plantilla_base
for f in schema.sql migraciones/001_restricciones_reglas_negocio.sql \
         migraciones/002_lineas_de_pedido_inmutables.sql \
         programables/funciones_procedimientos.sql datos_iniciales.sql; do
    $PSQL -q -d plantilla_base -f "$RAIZ/$f" > /dev/null
    echo "aplicado $f"
done
createdb -T plantilla_base copia_trabajo
pg servidor/01_vista_snapshot.sql
pg servidor/estado_servidor.sql
} 2>&1 | tee "$EVID/00_servidor_inicial.txt"

{
paso "Tablet: base desde cero e instantánea inicial (2.a)"
rm -f movil/foodstore_movil.db
movil schema_sqlite.sql
snapshot 00_inicial
} 2>&1 | tee "$EVID/01_tablet_y_snapshot_inicial.txt"

{
paso "Pruebas de la consigna 1.c"
movil pruebas_sqlite.sql
paso "Corrida inicial del semáforo (evalúa el borrador de las pruebas)"
movil semaforo.sql
} 2>&1 | tee "$EVID/02_pruebas_sqlite.txt"

{
paso "C2 · borrador"
movil casos/c2_borrador.sql
paso "C2 · el servidor sube el precio"
pg servidor/casos/c2_subir_precio.sql
paso "C2 · instantánea nueva y semáforo -> CONFLICTO"
snapshot c2
movil semaforo.sql
paso "C2 · el cliente acepta: precio actualizado y solicitud nueva"
movil casos/c2_acepta.sql
movil semaforo.sql
} 2>&1 | tee "$EVID/03_caso_c2.txt"

{
paso "C3 · borrador por 5 unidades"
movil casos/c3_borrador.sql
paso "C3 · en el servidor quedan 3"
pg servidor/casos/c3_ajustar_stock.sql
snapshot c3
movil semaforo.sql
} 2>&1 | tee "$EVID/04_caso_c3.txt"

{
paso "C4 · borrador con Agua mineral"
movil casos/c4_borrador.sql
paso "C4 · baja lógica en el servidor"
pg servidor/casos/c4_baja_producto.sql
snapshot c4
movil semaforo.sql
paso "C4 · catálogo recargado"
movil casos/c4_catalogo.sql
} 2>&1 | tee "$EVID/05_caso_c4.txt"

{
paso "C5 · borrador sin cambios"
movil casos/c5_borrador.sql
snapshot c5
movil semaforo.sql
} 2>&1 | tee "$EVID/06_caso_c5.txt"

{
paso "C6 · reenvío de la misma solicitud"
movil casos/c6_reenvio.sql
paso "C6 · repetir la simulación no reevalúa"
movil semaforo.sql
} 2>&1 | tee "$EVID/07_caso_c6.txt"

{
paso "Verificación final en PostgreSQL"
pg servidor/verificacion_final.sql
} 2>&1 | tee "$EVID/08_verificacion_final.txt"
