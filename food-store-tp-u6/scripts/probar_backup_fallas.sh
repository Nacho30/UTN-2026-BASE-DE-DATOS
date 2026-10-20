#!/usr/bin/env bash
# =====================================================================
# probar_backup_fallas.sh — TP Unidad 6, Parte 2 (pruebas del respaldo)
# Verifica que backup_foodstore.sh termina con código ≠ 0, deja ERROR en
# el log y NO deja un .dump (ni un .parcial) en tres situaciones de falla:
#   1. servidor inalcanzable (puerto equivocado)
#   2. sin credenciales (archivo .pgpass vacío; -w impide quedarse esperando)
#   3. pg_dump falla a mitad de camino (inyección de falla: un pg_dump
#      falso en el PATH escribe un archivo parcial y sale con código 1)
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

ok=0; mal=0
probar() {
    local nombre="$1"; shift
    local antes; antes=$(ls backups/*.dump 2>/dev/null | wc -l)
    env "$@" ./scripts/backup_foodstore.sh > /dev/null 2>&1
    local rc=$?
    local log; log=$(ls -t logs/backup_*.log | head -1)
    local despues; despues=$(ls backups/*.dump 2>/dev/null | wc -l)
    local parciales; parciales=$(ls backups/*.parcial 2>/dev/null | wc -l)
    if [[ $rc -ne 0 ]] && grep -q 'RESULTADO: FALLO' "$log" && [[ $despues -eq $antes && $parciales -eq 0 ]]; then
        echo "OK    | $nombre | código $rc | $(grep 'ERROR:' "$log" | head -1 | cut -d' ' -f4-)"
        ok=$((ok + 1))
    else
        echo "FALLA | $nombre | código $rc | dumps antes/después $antes/$despues | parciales $parciales"
        mal=$((mal + 1))
    fi
}

# Falso pg_dump para la prueba 3: escribe basura en el destino y falla
FALSO=$(mktemp -d)
cat > "$FALSO/pg_dump" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do [[ "$a" == -f ]] && sig=1 && continue; [[ -n "${sig:-}" ]] && destino="$a" && sig=; done
echo "basura" > "$destino"
echo "pg_dump: error: falla inyectada por probar_backup_fallas.sh" >&2
exit 1
EOF
chmod +x "$FALSO/pg_dump"
VACIO=$(mktemp)

probar "servidor inalcanzable"  PGPORT=5499
sleep 1
probar "sin credenciales"       PGPASSFILE="$VACIO"
sleep 1
probar "pg_dump falla"          PATH="$FALSO:$PATH"

rm -rf "$FALSO" "$VACIO"
echo "Resultado: $ok de 3 pruebas OK"
[[ $mal -eq 0 ]]
