#!/usr/bin/env bash
# TP U8 · revision/correr_verificaciones_tablet.sh — verificaciones extra del code
# review sobre COPIAS de movil/foodstore_movil.db (no la modifica).
# Correr desde food-store-tp-u8/ después de ./correr_todo.sh.
set -euo pipefail
cd "$(dirname "$0")"
EVID=../docs/evidencia
movil() {
    if command -v sqlite3 >/dev/null; then sqlite3 "$1" < "$2"
    else python3 ../herramientas/sqlite_cli.py "$1" "$2"; fi
}

# L1: dos solicitudes que juntas superan el stock; en SQLite y en el servidor
cp ../movil/foodstore_movil.db copia_movil.db
{ movil copia_movil.db limitaciones_semaforo.sql
  movil copia_movil.db ../movil/semaforo.sql
  echo '== L1 en el servidor (base descartable revision, dentro de BEGIN ... ROLLBACK)'
  dropdb --if-exists revision; createdb -T plantilla_base revision
  psql -X -d revision -c "BEGIN" \
       -c "CALL sp_registrar_pedido(1, 'EFECTIVO', '[{\"id_producto\": 6, \"cantidad\": 2}]')" \
       -c "CALL sp_registrar_pedido(2, 'EFECTIVO', '[{\"id_producto\": 6, \"cantidad\": 2}]')" \
       -c "ROLLBACK" 2>&1 | sed "/^CONTEXT/d;/^SQL statement/,/^PL\/pgSQL/d"
  dropdb revision
} > "$EVID/10_limitacion_stock_compartido.txt" 2>&1

# R1: instantánea de un servidor restaurado de un respaldo viejo (sin el producto 3)
cp ../movil/foodstore_movil.db copia_movil.db
grep -v "^3," ../movil/servidor_snapshot.csv > servidor_snapshot.csv
{ echo '== Carga de una instantánea SIN el producto 3'
  movil copia_movil.db ../movil/cargar_snapshot.sql
  movil copia_movil.db respaldo_viejo.sql
  movil copia_movil.db ../movil/semaforo.sql
} > "$EVID/11_respaldo_viejo.txt" 2>&1
rm -f servidor_snapshot.csv

# P1: PRAGMA foreign_keys es por conexión
cp ../movil/foodstore_movil.db copia_movil.db
movil copia_movil.db sin_pragma.sql > "$EVID/13_pragma_por_conexion.txt" 2>&1
rm -f copia_movil.db
echo "verificaciones de la tablet: OK"
