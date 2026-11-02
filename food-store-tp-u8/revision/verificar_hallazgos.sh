#!/usr/bin/env bash
# TP U8 · revision/verificar_hallazgos.sh — comprueba en la base cada hallazgo
# del code review, ANTES (scripts como estaban en la rama tp-unidad-7) y
# DESPUÉS (scripts corregidos). Usa bases descartables revision_antes y
# revision_despues; nunca foodstore ni copia_trabajo.
# Correr desde food-store-tp-u8/:  ./revision/verificar_hallazgos.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
PSQL="psql -X -q"
TMP="$(mktemp -d)"
git show tp-unidad-7:programables/funciones_procedimientos.sql > "$TMP/prog_antes.sql"
git show tp-unidad-7:lab/reset.sql                             > "$TMP/reset_antes.sql"

armar() {  # base, programables, con_002
    dropdb --if-exists "$1"; createdb "$1"
    $PSQL -d "$1" -f schema.sql -f migraciones/001_restricciones_reglas_negocio.sql > /dev/null
    [[ "$3" == si ]] && $PSQL -d "$1" -f migraciones/002_lineas_de_pedido_inmutables.sql > /dev/null
    $PSQL -d "$1" -f "$2" -f datos_iniciales.sql > /dev/null
}
armar revision_antes   "$TMP/prog_antes.sql"                      no
armar revision_despues programables/funciones_procedimientos.sql  si

pruebas() {  # base, reset.sql a usar
    echo "######## Base: $1"
    $PSQL -d "$1" <<'SQL'
\echo '== H1 (TPI, programables): sp_registrar_pedido con un producto inexistente'
BEGIN;
CALL sp_registrar_pedido(1, 'EFECTIVO', '[{"id_producto": 4, "cantidad": 1}, {"id_producto": 999, "cantidad": 3}]');
SELECT p.id_pedido, count(pp.id_producto) AS lineas_registradas, 2 AS lineas_pedidas
FROM pedido p LEFT JOIN pedido_producto pp USING (id_pedido) WHERE p.id_pedido > 4 GROUP BY p.id_pedido;
ROLLBACK;
\echo '== H2 (TP2, migración 001): UPDATE de la cantidad de una línea'
BEGIN;
SELECT stock AS stock_flan_antes FROM producto WHERE id_producto = 6;
UPDATE pedido_producto SET cantidad = 40 WHERE id_pedido = 4 AND id_producto = 6;
SELECT pp.cantidad AS cantidad_en_la_linea, pr.stock AS stock_flan_despues
FROM pedido_producto pp JOIN producto pr USING (id_producto) WHERE pp.id_pedido = 4;
ROLLBACK;
\echo '== H3 (TP1, schema.sql): ¿hace falta un índice en pedido_producto(id_pedido)?'
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT * FROM pedido_producto WHERE id_pedido = 3;
EXPLAIN (COSTS OFF) DELETE FROM pedido WHERE id_pedido = 3;
SQL
    echo "== H4 (TP2, lab/reset.sql): correrlo sobre una base que NO es copia_trabajo ($1)"
    $PSQL -d "$1" -f "$2" 2>&1
    $PSQL -d "$1" -c "SELECT (SELECT sum(stock) FROM producto) AS stock_total_tras_intentar_el_reset, 124 AS stock_total_de_datos_iniciales"
}
pruebas revision_antes   "$TMP/reset_antes.sql"
pruebas revision_despues lab/reset.sql
# Pruebas de la migración 002 y de la corrección de H1 (todo dentro de BEGIN ... ROLLBACK)
dropdb --if-exists revision_002; createdb -T revision_despues revision_002
psql -X -d revision_002 -f pruebas/002_pruebas_lineas_inmutables.sql \
    > food-store-tp-u8/docs/evidencia/12_pruebas_002.txt 2>&1
dropdb revision_002
dropdb revision_antes; dropdb revision_despues; rm -rf "$TMP"
