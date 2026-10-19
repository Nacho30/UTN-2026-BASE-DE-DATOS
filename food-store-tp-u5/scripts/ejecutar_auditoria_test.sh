#!/usr/bin/env bash
# Parte B, punto 2 — ejecuta la secuencia de prueba y captura el log.
# Uso:  ./scripts/ejecutar_auditoria_test.sh
# Requiere .env con PW_APP_WEB y acceso de lectura al directorio de log
# (correrlo como el usuario postgres del sistema operativo, ver informe).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

PGDATA="${PGDATA:-/home/claude/pgdata}"
LOG="$PGDATA/log/postgresql-$(date +%Y-%m-%d).log"
SALIDA="docs/log_auditoria_prueba.txt"
touch "$LOG"
INICIO=$(stat -c %s "$LOG")          # byte desde el que empieza esta prueba

export PGHOST=127.0.0.1 PGDATABASE=foodstore_u5 PGAPPNAME=foodstore-web

echo "== 1-5. Lectura, inserción, actualización, login de app fallido y DELETE denegado (app_web)"
PGUSER=app_web PGPASSWORD="$PW_APP_WEB" psql -X -f sql/auditoria_test.sql || true

echo "== 6. Inicio de sesión fallido del MOTOR (contraseña incorrecta para app_web)"
PGUSER=app_web PGPASSWORD="esta-no-es" psql -X -c "SELECT 1" || true

sleep 1
tail -c +"$((INICIO + 1))" "$LOG" > "$SALIDA"
echo "== Fragmento de log guardado en $SALIDA ($(wc -l < "$SALIDA") líneas)"
