#!/usr/bin/env bash
# Parte C — orquesta el simulacro y captura el log crudo.
# El log CRUDO contiene datos personales: queda en tmp/ (fuera de Git).
# Se anonimiza después con scripts/anonimizar_log.py.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

PGDATA="${PGDATA:-/home/claude/pgdata}"
LOG="$PGDATA/log/postgresql-$(date +%Y-%m-%d).log"
mkdir -p tmp
touch "$LOG"
INICIO=$(stat -c %s "$LOG")

# Estado limpio de la cuenta víctima antes del simulacro
psql -X -q -d foodstore_u5 -c "UPDATE usuario SET intentos_fallidos = 0, bloqueado = FALSE WHERE id IN (1, 50);"

# Tráfico legítimo de la aplicación antes y después (desde 127.0.0.1)
legitimo() {
  PGHOST=127.0.0.1 PGUSER=app_web PGPASSWORD="$PW_APP_WEB" PGAPPNAME=foodstore-web \
    psql -X -q -d foodstore_u5 >/dev/null <<'SQL'
SELECT fn_autenticar($1, $2) \bind 'benjamin.ruiz1@hotmail.com' 'Clave1!' \g
SQL
}
legitimo; sleep 2

# El atacante: credenciales filtradas de app_web, desde otro origen.
# origen_remoto.py hace que el servidor vea la conexión desde 127.0.0.2.
python3 scripts/origen_remoto.py & REENVIO=$!
trap 'kill $REENVIO 2>/dev/null || true' EXIT
sleep 1
PGHOST=127.0.0.1 PGPORT=6543 PGUSER=app_web PGPASSWORD="$PW_APP_WEB" \
  psql -X -d foodstore_u5 -f sql/simulacro_incidente.sql | tee tmp/salida_simulacro.txt

sleep 2; legitimo; sleep 1
tail -c +"$((INICIO + 1))" "$LOG" > tmp/log_simulacro_crudo.log
echo "== Log crudo: tmp/log_simulacro_crudo.log ($(wc -l < tmp/log_simulacro_crudo.log) líneas)"
