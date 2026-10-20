# AGENTS.md — Food Store (Base de Datos I/II, UTN)

## Qué es este repo
Scripts SQL del proyecto integrador Food Store sobre PostgreSQL 16.
- `schema.sql`: esquema conciliado (TP1). `datos_iniciales.sql`: carga de prueba (datos ficticios).
- `migraciones/NNN_*.sql`: cambios estructurales, numerados y en orden.
- `pruebas/NNN_*.sql`: casos válidos e inválidos de cada migración.
- `lab/`: scripts del laboratorio de concurrencia (TP2 Parte 2).
- `optimizacion/`: carga masiva y consultas del laboratorio de optimización (TP3): `carga_masiva.sql`, `queries.sql`, `parte4_consultas.sql`.
- `analitica/`: consultas analíticas con joins, subconsultas, agregación y ventana del TP4: `queries_tp4.sql`, `parte2_qc.sql`, `parte3_ranking.sql`, `parte4_competencia.sql`.
- `indices.sql`, `views.sql`, `specs/`, `duia.md`, `informe_mediciones.md`, `README_U3S1.md`: entrega de Unidad 3 / Semana 1 (índices, vistas y vista materializada sobre el esquema heredado, sin modificar tablas ni restricciones).
- `programables/`: funciones y procedimientos PL/pgSQL del TPI (`funciones_procedimientos.sql`, `pruebas_funciones_procedimientos.sql`) — requieren los triggers de `migraciones/001_restricciones_reglas_negocio.sql` ya aplicados.
- `informe_tecnico_TPI.md`: informe técnico consolidado de la primera entrega parcial del TPI (mapea los 9 objetivos de la consigna contra la evidencia de cada unidad).

## Reglas para el agente
- Trabajar SOLO sobre la base `copia_trabajo` (ver `protocolo_seguridad.md`). Nunca sobre `plantilla_base`.
- Proponer en modo Plan; no aplicar nada sin revisión del `git diff`.
- Todo script que escribe se entrega para correr dentro de `BEGIN; ... ROLLBACK;`.
- Nunca generar `UPDATE` o `DELETE` sin `WHERE`. Categorías y productos NO se borran: baja lógica con `activo = FALSE` (R7).
- En subconsultas con `NOT IN`, contemplar `NULL` (preferir `NOT EXISTS`).

## Unidad 6 — respaldo y mantenimiento (`food-store-tp-u6/`)
La especificación es `food-store-tp-u6/SPEC_U6.md`; si una instrucción del chat la contradice, gana la SPEC.
- La base principal `foodstore` sólo se lee o recibe `VACUUM`/`ANALYZE`: nunca `dropdb`, `pg_restore`, `ALTER DATABASE` ni DML sobre ella desde estos scripts.
- La única base que se puede borrar y recrear es `foodstore_restore_test`, y sólo desde `restore_test.sh --recrear`.
- Prohibido escribir contraseñas en scripts, logs o el repo: usar `~/.pgpass` y `-w`. No usar `PGPASSWORD` en línea de comandos.
- `pg_dump` siempre en formato custom (`-Fc`); `pg_restore` siempre con `--exit-on-error`.
- No proponer `VACUUM FULL` como tarea periódica.
- Las tablas reales son `pedido_producto` (no `detalle_pedido`) y `cliente`; verificar nombres contra `schema.sql` antes de generar SQL.
