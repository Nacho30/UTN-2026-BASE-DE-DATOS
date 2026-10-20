#!/usr/bin/env bash
# =====================================================================
# restore_test.sh — TP Unidad 6, Parte 4 (simulacro contra reloj)
# Restaura el ÚLTIMO respaldo de backups/ en foodstore_restore_test,
# valida el resultado contra los conteos tomados al respaldar y mide:
#   RTO observado = desde inmediatamente antes de createdb hasta que
#                   terminan las validaciones;
#   RPO observado = antigüedad del respaldo al empezar el simulacro, y
#                   cuántos cambios de foodstore quedaron fuera de él.
#
# foodstore NUNCA se modifica: sólo se lee para medir la pérdida (RPO).
#
# Uso:   ./scripts/restore_test.sh [--recrear] [--jobs N] [--dump ARCHIVO]
#   --recrear  borra foodstore_restore_test si ya existe (única base que
#              este script puede borrar)
#   --jobs N   pg_restore en paralelo (por defecto 1)
# Sale:  0 = restauración validada; 1 = falla (ver logs/restore_*.log)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
readonly ORIGEN="foodstore"
readonly DESTINO="foodstore_restore_test"     # fijo: no se acepta otro nombre
RECREAR=0; JOBS=1; DUMP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --recrear) RECREAR=1 ;;
        --jobs)    JOBS="$2"; shift ;;
        --dump)    DUMP="$2"; shift ;;
        *) echo "Opción desconocida: $1" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p logs
LOG="logs/restore_$(date +%Y%m%d_%H%M%S).log"
log()   { printf '%s %s\n' "$(date '+%F %T.%3N %z')" "$*" | tee -a "$LOG"; }
falla() { log "ERROR: $*"; log "RESULTADO: FALLO"; exit 1; }
ms()    { echo $(( ($(date +%s%N) - $1) / 1000000 )); }
q()     { psql -X -q -A -t -w -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }

[[ -z "${PGPASSWORD:-}" ]] || falla "PGPASSWORD está definida; usar ~/.pgpass (SPEC_U6.md, regla 1)"
[[ "$DESTINO" != "$ORIGEN" ]] || falla "el destino no puede ser la base principal"

# ---------------------------------------------------------------------
# 0. Verificaciones previas (fuera del cronómetro de la consigna)
# ---------------------------------------------------------------------
INICIO_TOTAL=$(date +%s%N)
[[ -n "$DUMP" ]] || DUMP=$(ls -1 backups/${ORIGEN}_*.dump 2>/dev/null | sort | tail -1)
[[ -n "$DUMP" && -s "$DUMP" ]] || falla "no hay respaldos en backups/"
SELLO=$(basename "$DUMP" .dump); SELLO=${SELLO#${ORIGEN}_}
CONTEOS="logs/conteos_${SELLO}.csv"
[[ -s "$CONTEOS" ]] || falla "no están los conteos del respaldo ($CONTEOS)"
log "Respaldo elegido: $DUMP ($(stat -c %s "$DUMP") bytes)"
if [[ -s "${DUMP}.sha256" ]]; then
    ( cd "$(dirname "$DUMP")" && sha256sum --quiet -c "$(basename "$DUMP").sha256" ) \
        || falla "el SHA-256 del respaldo no coincide: archivo dañado"
    log "SHA-256 verificado"
else
    log "ADVERTENCIA: el respaldo no tiene .sha256; no se pudo verificar su integridad"
fi
declare -A ESPERADO
while IFS=, read -r clave valor; do [[ "$clave" == clave ]] || ESPERADO[$clave]=$valor; done < "$CONTEOS"

if [[ -n "$(q postgres "SELECT 1 FROM pg_database WHERE datname = '$DESTINO'")" ]]; then
    [[ $RECREAR -eq 1 ]] || falla "$DESTINO ya existe; usar --recrear para borrarla y repetir el simulacro"
    log "Borrando la base descartable $DESTINO (--recrear)"
    dropdb -w --if-exists "$DESTINO" 2>>"$LOG" || falla "no se pudo borrar $DESTINO"
fi

# ---------------------------------------------------------------------
# 1. CRONÓMETRO: inmediatamente antes de crear la base de prueba
# ---------------------------------------------------------------------
T0=$(date +%s%N); T0_EPOCH=$(date +%s)
log "CRONÓMETRO INICIA"
createdb -w "$DESTINO" 2>>"$LOG" || falla "createdb falló"
log "createdb OK ($(ms "$T0") ms)"

T1=$(date +%s%N)
pg_restore -w -d "$DESTINO" --no-owner --no-privileges --exit-on-error --jobs="$JOBS" "$DUMP" 2>>"$LOG" \
    || { rc=$?; falla "pg_restore terminó con código $rc"; }
log "pg_restore OK con --jobs=$JOBS ($(ms "$T1") ms)"

# pg_restore no trae estadísticas del planificador: sin ANALYZE la base
# restaurada responde, pero con planes malos hasta que actúe el autovacuum.
T2=$(date +%s%N)
q "$DESTINO" "ANALYZE" >/dev/null 2>>"$LOG" || falla "ANALYZE falló"
log "ANALYZE OK ($(ms "$T2") ms)"

# ---------------------------------------------------------------------
# 2. Validaciones mínimas (consigna) + sumas de control
#    La consigna usa "detalle_pedido"; en el esquema de Food Store la
#    tabla de líneas se llama pedido_producto.
# ---------------------------------------------------------------------
T3=$(date +%s%N)
FALLAS=0
while IFS='|' read -r tabla filas; do
    esperado=${ESPERADO[$tabla]:-?}
    if [[ "$filas" == "$esperado" ]]; then log "Validación filas $tabla: $filas = $esperado OK"
    else log "Validación filas $tabla: $filas ≠ $esperado (respaldo) FALLA"; FALLAS=$((FALLAS + 1)); fi
done < <(q "$DESTINO" "
    SELECT 'categoria', count(*) FROM categoria
    UNION ALL SELECT 'cliente', count(*) FROM cliente
    UNION ALL SELECT 'producto', count(*) FROM producto
    UNION ALL SELECT 'pedido', count(*) FROM pedido
    UNION ALL SELECT 'pedido_producto', count(*) FROM pedido_producto")

INV_PROD=$(q "$DESTINO" "SELECT count(*) FROM producto WHERE precio < 0 OR stock < 0")
INV_DET=$(q "$DESTINO" "SELECT count(*) FROM pedido_producto WHERE cantidad <= 0 OR precio_unitario < 0")
HUERF=$(q "$DESTINO" "SELECT count(*) FROM pedido_producto pp WHERE NOT EXISTS (SELECT 1 FROM pedido p WHERE p.id_pedido = pp.id_pedido)")
for par in "productos_invalidos:$INV_PROD" "detalles_invalidos:$INV_DET" "lineas_huerfanas:$HUERF"; do
    if [[ "${par#*:}" == "0" ]]; then log "Validación ${par%%:*}: 0 OK"
    else log "Validación ${par%%:*}: ${par#*:} FALLA"; FALLAS=$((FALLAS + 1)); fi
done

while IFS='|' read -r clave valor; do
    if [[ "$valor" == "${ESPERADO[$clave]}" ]]; then log "Control $clave: $valor OK"
    else log "Control $clave: $valor ≠ ${ESPERADO[$clave]} FALLA"; FALLAS=$((FALLAS + 1)); fi
done < <(q "$DESTINO" "
    SELECT 'ctl_suma_stock', sum(stock) FROM producto
    UNION ALL SELECT 'ctl_importe_lineas', sum(cantidad * precio_unitario) FROM pedido_producto
    UNION ALL SELECT 'ctl_max_id_pedido', max(id_pedido) FROM pedido")

TRIG=$(q "$DESTINO" "SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal")
log "Disparadores de negocio restaurados: $TRIG"
log "Validaciones: $(ms "$T3") ms"

RTO_MS=$(ms "$T0")
log "CRONÓMETRO DETIENE"
[[ $FALLAS -eq 0 ]] || falla "$FALLAS validaciones fallaron"

# ---------------------------------------------------------------------
# 3. RPO observado (sólo lectura sobre foodstore)
# ---------------------------------------------------------------------
EDAD_S=$(( T0_EPOCH - ${ESPERADO[ctl_hora_snapshot_epoch]} ))
read -r NUEVOS BORRADOS VIVOS < <(q "$ORIGEN" "
    SELECT count(*) FILTER (WHERE id_pedido > ${ESPERADO[ctl_max_id_pedido]}),
           ${ESPERADO[pedido]} - count(*) FILTER (WHERE id_pedido <= ${ESPERADO[ctl_max_id_pedido]}),
           count(*)
    FROM pedido" | tr '|' ' ')

log "RTO observado (createdb → validaciones OK): ${RTO_MS} ms ($(awk "BEGIN{printf \"%.1f\", $RTO_MS/1000}") s)"
log "Tiempo total incluidas verificaciones previas: $(ms "$INICIO_TOTAL") ms"
log "Respaldo del $(date -d "@${ESPERADO[ctl_hora_snapshot_epoch]}" '+%F %T %z'); antigüedad al iniciar el simulacro: ${EDAD_S} s ($(awk "BEGIN{printf \"%.1f\", $EDAD_S/60}") min)"
log "RPO observado: se perderían ${NUEVOS} pedidos creados y ${BORRADOS} cancelaciones hechas después del respaldo (foodstore tiene hoy ${VIVOS} pedidos; el respaldo, ${ESPERADO[pedido]})"
log "RESULTADO: OK"
