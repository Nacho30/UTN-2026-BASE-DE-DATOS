# Protocolo de seguridad — copia, transacción, respaldo

Entorno: PostgreSQL 16 local (socket en /tmp, usuario `postgres`), proyecto Food Store.
Base plantilla: `plantilla_base` (schema.sql + datos_iniciales.sql). Base de trabajo: `copia_trabajo`.
Nunca se ejecuta un script generado por IA contra otra base que no sea `copia_trabajo`.

## 1. Copia
```bash
export PGHOST=/tmp PGUSER=postgres
dropdb --if-exists copia_trabajo
createdb -T plantilla_base copia_trabajo
psql -d copia_trabajo -c "select current_database();"   # confirmar SIEMPRE contra qué base se corre
```

## 2. Transacción
Todo script que escribe se ejecuta primero así, y se lee el resultado (filas afectadas, errores) antes de decidir:
```sql
\set ON_ERROR_STOP on
BEGIN;
\i script_a_probar.sql
-- inspección: SELECT de las filas afectadas, conteos antes/después
ROLLBACK;   -- recién cuando el efecto es el esperado se repite con COMMIT
```

## 3. Respaldo
Antes de cualquier DDL (ALTER, DROP, CREATE TRIGGER, migración):
```bash
pg_dump -Fc -d copia_trabajo -f ~/respaldos/copia_trabajo_$(date +%Y%m%d_%H%M)_<motivo>.dump
# restaurar:
dropdb copia_trabajo && createdb copia_trabajo && pg_restore -d copia_trabajo ~/respaldos/<archivo>.dump
```
Los respaldos viven en `~/respaldos/`, fuera del repositorio (no se versionan datos).

## Reglas adicionales para agentes de IA
- El agente trabaja en modo Plan; nada se aplica sin leer el `git diff` completo.
- Se usa un usuario sin permisos sobre otras bases; nunca credenciales de producción en el entorno del agente.
- No se confía en el reporte del agente: el efecto se verifica con un SELECT propio.
