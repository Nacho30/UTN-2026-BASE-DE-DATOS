# Food Store — TP Unidad 6: Mantenimiento, respaldo y recuperación

Bases de Datos II · Tecnicatura Universitaria en Programación · UTN · 2026
Alumno: Ignacio Martín Rodríguez

Trabajo sobre el esquema real de Food Store (`../schema.sql`, `../migraciones/`, `../programables/`) en PostgreSQL 16.

## Entregables

| Archivo | Contenido |
|---|---|
| [`SPEC_U6.md`](SPEC_U6.md) | Especificación: tareas, frecuencia, condición de éxito y reglas de seguridad |
| [`scripts/backup_foodstore.sh`](scripts/backup_foodstore.sh) | Respaldo custom con fecha, log, conteos en el mismo snapshot y verificación |
| [`sql/health_check.sql`](sql/health_check.sql) | 7 controles de monitoreo con estado OK/ALERTA |
| [`sql/maintenance.sql`](sql/maintenance.sql) | Revisión de autovacuum y acción justificada por la observación |
| [`scripts/restore_test.sh`](scripts/restore_test.sh) | Simulacro contra reloj en `foodstore_restore_test`, con RTO y RPO |
| [`docs/informe_u6.pdf`](docs/informe_u6.pdf) | Informe post-incidente de una página |
| [`docs/evidencia/`](docs/evidencia/) | Salidas reales de cada paso (00 a 08) |

Además: `scripts/probar_backup_fallas.sh` (pruebas de falla del respaldo), `sql/carga_volumen.sql` y `sql/actividad_post_respaldo.sql` (datos y actividad de laboratorio), `config/pg_hba_u6.conf` (acceso por TCP con SCRAM) y `docs/generar_informe.py` (genera el PDF).

## Resultados

| | Previsto | Observado |
|---|---|---|
| RPO | ≤ 24 h | 3,5 min de antigüedad del respaldo; se perderían 40 pedidos nuevos y 3.000 cancelaciones |
| RTO | ≤ 15 min | 1,8 s (createdb → validaciones OK) |

## Cómo reproducir

```bash
# Credenciales: nunca en los scripts
echo "localhost:5432:*:postgres:<contraseña>" > ~/.pgpass && chmod 600 ~/.pgpass
# Base foodstore con el esquema del repo
createdb foodstore
for f in ../schema.sql ../migraciones/001_restricciones_reglas_negocio.sql \
         ../programables/funciones_procedimientos.sql ../datos_iniciales.sql sql/carga_volumen.sql; do
  psql -X -v ON_ERROR_STOP=1 -d foodstore -f "$f"; done

./scripts/backup_foodstore.sh                 # Parte 2
./scripts/probar_backup_fallas.sh
psql -X -h localhost -U postgres -w -d foodstore -f sql/actividad_post_respaldo.sql
psql -X -h localhost -U postgres -w -d foodstore -f sql/health_check.sql     # Parte 3
psql -X -h localhost -U postgres -w -d foodstore -f sql/maintenance.sql
./scripts/restore_test.sh --recrear           # Parte 4 (agregar --jobs N para paralelizar)
```

Los `.dump` (`backups/`) y los logs crudos (`logs/`) no se versionan. La evidencia de su creación, tamaño, SHA-256 y restauración exitosa está en `docs/evidencia/`.
