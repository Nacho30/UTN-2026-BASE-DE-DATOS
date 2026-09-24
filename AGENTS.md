# AGENTS.md — Food Store (Base de Datos I/II, UTN)

## Qué es este repo
Scripts SQL del proyecto integrador Food Store sobre PostgreSQL 16.
- `schema.sql`: esquema conciliado (TP1). `datos_iniciales.sql`: carga de prueba (datos ficticios).
- `migraciones/NNN_*.sql`: cambios estructurales, numerados y en orden.
- `pruebas/NNN_*.sql`: casos válidos e inválidos de cada migración.
- `lab/`: scripts del laboratorio de concurrencia (TP2 Parte 2).
- `optimizacion/`: carga masiva y consultas del laboratorio de optimización (TP3): `carga_masiva.sql`, `queries.sql`, `parte4_consultas.sql`.

## Reglas para el agente
- Trabajar SOLO sobre la base `copia_trabajo` (ver `protocolo_seguridad.md`). Nunca sobre `plantilla_base`.
- Proponer en modo Plan; no aplicar nada sin revisión del `git diff`.
- Todo script que escribe se entrega para correr dentro de `BEGIN; ... ROLLBACK;`.
- Nunca generar `UPDATE` o `DELETE` sin `WHERE`. Categorías y productos NO se borran: baja lógica con `activo = FALSE` (R7).
- En subconsultas con `NOT IN`, contemplar `NULL` (preferir `NOT EXISTS`).
