#!/usr/bin/env bash
# =====================================================================
# backup_foodstore.sh — TP Unidad 6, Parte 2
# Respaldo lógico de foodstore en formato custom (-Fc), con fecha y hora
# en el nombre, log en logs/ y salida con error si algo falla.
#
# Credenciales: NUNCA en este archivo. Se usa ~/.pgpass (modo 0600):
#     localhost:5432:*:postgres:<contraseña>
# y -w (--no-password): si no hay credencial, falla en vez de esperar.
#
# Uso:   ./scripts/backup_foodstore.sh
# Vars:  PGHOST (localhost) PGPORT (5432) PGUSER (postgres)
#        BASE (foodstore) RETENCION_DIAS (7)
# Sale:  0 = respaldo verificado; 1 = error (ver logs/backup_*.log)
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
BASE="${BASE:-foodstore}"
RETENCION_DIAS="${RETENCION_DIAS:-7}"
FECHA="$(date +%Y%m%d_%H%M%S)"

mkdir -p backups logs
ARCHIVO="backups/${BASE}_${FECHA}.dump"
LOG="logs/backup_${FECHA}.log"
CONTEOS="logs/conteos_${FECHA}.csv"

# Si el script se interrumpe (Ctrl+C, kill, error), no queda un .parcial ni
# una sesión abierta reteniendo el snapshot.
limpiar() {
    rm -f -- "${ARCHIVO}.parcial"
    [[ -n "${SESION_PID:-}" ]] && kill "$SESION_PID" 2>/dev/null || true
}
trap limpiar EXIT

log()   { printf '%s %s\n' "$(date '+%F %T %z')" "$*" | tee -a "$LOG"; }
falla() { log "ERROR: $*"; rm -f "${ARCHIVO}.parcial"; log "RESULTADO: FALLO"; exit 1; }

log "Inicio respaldo de ${BASE} en ${PGHOST}:${PGPORT} como ${PGUSER}"

if [[ -n "${PGPASSWORD:-}" ]]; then
    falla "PGPASSWORD está definida en el entorno; usar ~/.pgpass (regla 1 de SPEC_U6.md)"
fi

# ---------------------------------------------------------------------
# 1. Conteos y sumas de control en el MISMO snapshot que el respaldo.
#    Una sesión psql abre una transacción REPEATABLE READ, exporta su
#    snapshot y calcula los conteos; pg_dump usa ese snapshot. Así los
#    conteos corresponden exactamente a lo que queda dentro del .dump,
#    aunque la base siga recibiendo pedidos durante el respaldo.
# ---------------------------------------------------------------------
coproc SESION { psql -X -q -A -t -F ',' -w -v ON_ERROR_STOP=1 -d "$BASE" 2>&1; }
exec {ENTRADA}>&"${SESION[1]}"

leer() { local linea; IFS= read -r -t 60 -u "${SESION[0]}" linea || return 1; printf '%s' "$linea"; }

echo "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY; SELECT pg_export_snapshot();" >&"$ENTRADA"
SNAPSHOT="$(leer)" || falla "no se pudo abrir la sesión de snapshot (¿credenciales en ~/.pgpass? ¿servidor activo?)"
[[ "$SNAPSHOT" =~ ^[0-9A-F]+-[0-9A-F]+-[0-9]+$ ]] || falla "respuesta inesperada al exportar el snapshot: $SNAPSHOT"
log "Snapshot exportado: $SNAPSHOT"

cat >&"$ENTRADA" <<'SQL'
SELECT 'categoria', count(*) FROM categoria
UNION ALL SELECT 'cliente', count(*) FROM cliente
UNION ALL SELECT 'producto', count(*) FROM producto
UNION ALL SELECT 'pedido', count(*) FROM pedido
UNION ALL SELECT 'pedido_producto', count(*) FROM pedido_producto
UNION ALL SELECT 'ctl_suma_stock', sum(stock) FROM producto
UNION ALL SELECT 'ctl_importe_lineas', sum(cantidad * precio_unitario) FROM pedido_producto
UNION ALL SELECT 'ctl_max_id_pedido', max(id_pedido) FROM pedido
UNION ALL SELECT 'ctl_ultimo_pedido_epoch', extract(epoch FROM max(fecha))::bigint FROM pedido
UNION ALL SELECT 'ctl_hora_snapshot_epoch', extract(epoch FROM now())::bigint;
SELECT 'FIN';
SQL
echo "clave,valor" > "$CONTEOS"
while linea="$(leer)"; do
    [[ "$linea" == "FIN" ]] && break
    [[ "$linea" == *,* ]] || falla "error al calcular los conteos: $linea"
    echo "$linea" >> "$CONTEOS"
done
[[ "$linea" == "FIN" ]] || falla "la sesión de conteos terminó antes de tiempo"
log "Conteos previos registrados en $CONTEOS: $(grep -v '^ctl_\|^clave' "$CONTEOS" | tr '\n' ' ')"

# ---------------------------------------------------------------------
# 2. pg_dump formato custom, a un archivo .parcial que sólo se renombra
#    si todo salió bien (un respaldo roto nunca parece "el último").
# ---------------------------------------------------------------------
INICIO_NS=$(date +%s%N)
pg_dump -w -d "$BASE" -Fc --snapshot="$SNAPSHOT" -f "${ARCHIVO}.parcial" 2>>"$LOG" \
    || { rc=$?; falla "pg_dump terminó con código $rc"; }
DURACION_MS=$(( ($(date +%s%N) - INICIO_NS) / 1000000 ))

# \q cierra psql aunque el coproc conserve abierto su descriptor de entrada
# (sin \q, el wait quedaba colgado: falla encontrada en la primera prueba).
printf 'COMMIT;\n\\q\n' >&"$ENTRADA"; exec {ENTRADA}>&-
wait "$SESION_PID" 2>/dev/null || true

# ---------------------------------------------------------------------
# 3. Verificación: tamaño > 0 y pg_restore puede leer el índice completo
# ---------------------------------------------------------------------
[[ -s "${ARCHIVO}.parcial" ]] || falla "el archivo de respaldo quedó vacío"
OBJETOS=$(pg_restore --list "${ARCHIVO}.parcial" 2>>"$LOG" | grep -vc '^;') \
    || falla "pg_restore --list no pudo leer el respaldo"
mv "${ARCHIVO}.parcial" "$ARCHIVO"
( cd backups && sha256sum "$(basename "$ARCHIVO")" > "$(basename "$ARCHIVO").sha256" )

log "Archivo: $ARCHIVO"
log "Tamaño: $(stat -c %s "$ARCHIVO") bytes ($(du -h "$ARCHIVO" | cut -f1))"
log "SHA-256: $(cut -d' ' -f1 "${ARCHIVO}.sha256")"
log "Objetos en el índice (pg_restore --list): $OBJETOS"
log "Duración de pg_dump: ${DURACION_MS} ms"

# ---------------------------------------------------------------------
# 4. Retención: sólo respaldos de esta base con este patrón de nombre
# ---------------------------------------------------------------------
while IFS= read -r viejo; do
    rm -f -- "$viejo" "${viejo}.sha256"
    log "Retención: eliminado $viejo (más de ${RETENCION_DIAS} días)"
done < <(find backups -maxdepth 1 -type f -name "${BASE}_*.dump" -mtime +"$RETENCION_DIAS")

log "RESULTADO: OK"
