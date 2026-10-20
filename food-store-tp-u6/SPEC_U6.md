# SPEC_U6 — Plan de respaldo, monitoreo y mantenimiento de Food Store

**Alcance:** base `foodstore` (PostgreSQL 16, esquema de `schema.sql` + `migraciones/` + `programables/`). Base de ensayo: `foodstore_restore_test`. **Objetivos del laboratorio:** RPO ≤ 24 h (un respaldo diario) y RTO ≤ 15 min (desde crear la base de ensayo hasta validarla).

## Tareas automatizadas

| Tarea | Frecuencia (cron, hora AR) | Script | Termina bien cuando… | Evidencia |
|---|---|---|---|---|
| Respaldo de `foodstore` | Diaria, 03:10 | `scripts/backup_foodstore.sh` | `pg_dump` sale con 0, el `.dump` pesa > 0 y `pg_restore --list` lo lee entero | `backups/foodstore_AAAAMMDD_HHMMSS.dump`, `logs/backup_*.log` con tamaño y SHA-256, conteos previos en `logs/conteos_*.csv` |
| Chequeo de salud | Diaria, 07:05 | `sql/health_check.sql` | Corre sin error; ningún control en estado `ALERTA` | `logs/health_*.txt` |
| Revisión de mantenimiento | Semanal, domingo 04:10 | `sql/maintenance.sql` | Las tablas que superan el umbral reciben `VACUUM (ANALYZE)`; las demás, sólo se informan | `logs/maintenance_*.txt` con el estado antes y después |
| Restauración de prueba | Semanal, domingo 05:10 | `scripts/restore_test.sh` | Conteos iguales a los del respaldo, 0 productos y 0 líneas inválidas, sumas de control iguales | `logs/restore_*.log` con RTO y antigüedad del respaldo (RPO) |

```cron
CRON_TZ=America/Argentina/Buenos_Aires
10 3 * * *  cd /ruta/food-store-tp-u6 && ./scripts/backup_foodstore.sh
5  7 * * *  cd /ruta/food-store-tp-u6 && psql -X -h localhost -U postgres -d foodstore -w -f sql/health_check.sql > logs/health_$(date +\%F).txt
10 4 * * 0  cd /ruta/food-store-tp-u6 && psql -X -h localhost -U postgres -d foodstore -w -f sql/maintenance.sql > logs/maintenance_$(date +\%F).txt
10 5 * * 0  cd /ruta/food-store-tp-u6 && ./scripts/restore_test.sh --recrear
```

La programación es la propuesta. En el laboratorio, cada script **se ejecutó a mano y se revisó su salida** antes de considerarlo apto para programarse.

## Reglas de seguridad (obligatorias, también para el asistente de IA)

1. **Contraseñas:** ningún script ni archivo del repo contiene contraseñas. La conexión usa `~/.pgpass` (modo `0600`) y `-w`, que hace fallar el script en lugar de quedarse esperando una contraseña.
2. **`foodstore` es intocable:** sólo se lee (`pg_dump`, consultas de monitoreo) o recibe `VACUUM`/`ANALYZE`. Ningún script la elimina, la restaura ni la renombra. `restore_test.sh` aborta si el destino no es exactamente `foodstore_restore_test`.
3. **Destructivo sólo sobre lo descartable:** el único `dropdb` permitido es el de `foodstore_restore_test`, y sólo con `--recrear`.
4. **Formato custom (`-Fc`)** para poder usar `pg_restore`, restaurar en paralelo (`-j`) y listar el contenido.
5. **Fallar fuerte:** `set -euo pipefail`. Un `pg_dump` o `pg_restore` con error termina el script con código ≠ 0 y deja `ERROR` en el log. `pg_restore` usa `--exit-on-error`.
6. **Sin `VACUUM FULL` periódico:** bloquea la tabla con `ACCESS EXCLUSIVE` y la reescribe. Un `VACUUM` o `ANALYZE` manual sólo se ejecuta si la observación previa lo justifica (umbral explícito en `maintenance.sql`).
7. **Retención:** se conservan los `.dump` de los últimos 7 días. El borrado se limita a `backups/foodstore_*.dump`. Los respaldos no se versionan en Git.

## Fuera de alcance

Respaldo físico o PITR (`pg_basebackup` + WAL), réplicas y cifrado de los respaldos en reposo. Se mencionan como mejora en el informe.
