# DUIA — Declaración de Uso de IA · TP Unidad 8

Proyecto Food Store · Bases de Datos II · Tecnicatura Universitaria en Programación · UTN
Alumno: Ignacio Martín Rodríguez · Fecha: 02/11/2026

Herramientas declaradas en la consigna: **Kiro** (especificación) y **OpenCode** (generación y code review en el agente Plan). En este TP se usó **Claude (Anthropic)**, en una sesión de Claude Code, para ambos roles, igual que se declaró en las DUIA de las unidades anteriores (`duia.md`, `duia_parte1.md`). Los archivos de `docs/kiro/` cumplen el rol del spec de Kiro (se escribieron antes de generar el código) y el code review cumple el rol del agente Plan de OpenCode.

| Herramienta | Para qué se usó | Prompt / spec (resumen) | Se aceptó / se descartó — por qué |
|---|---|---|---|
| Claude (rol Kiro: especificar) | Spec de la base de la tablet y la simulación | La consigna del TP 8 y el esquema del repositorio; 4 requisitos EARS, cada uno ligado a un caso | Aceptados los 4 requisitos (C2, C3, C4, C6), con la decisión de no validar stock en la tablet (bitácora, entrada 1). |
| Claude (rol OpenCode: generar) | `schema_sqlite.sql`, `cargar_snapshot.sql`, `semaforo.sql`, `pruebas_sqlite.sql`, scripts de casos y `correr_todo.sh` | Las tareas de `docs/kiro/tasks.md` | Aceptados tras correrlos desde cero: C2 a C6 dan el resultado esperado y PostgreSQL no cambia (`08_verificacion_final.txt`). Corregida la presentación de los UUID (bitácora, entrada 3). |
| Claude (rol OpenCode, agente Plan) | Code review de los scripts de la cursada | "Revisá los scripts de todas las unidades: errores de lógica, reglas que no se cumplen, riesgos de ejecución" | 3 corregidos (H1 `sp_registrar_pedido`, H2 líneas de pedido, H4 `reset.sql`), 2 descartados con fundamento (H3 índice, H5 UPDATE sin WHERE), 2 aceptados como limitación documentada (L1 stock compartido, P1 PRAGMA por conexión). Cada uno comprobado en la base (`09_*.txt` a `13_*.txt`). |
| Claude | Sustituto del CLI de SQLite para generar la evidencia | "No hay sqlite3 en el entorno; ejecutá los scripts sin cambiarlos" | Aceptado sólo como herramienta de ejecución (`herramientas/sqlite_cli.py`); los scripts son SQL estándar de SQLite. |

## Reglas que se respetaron
- Sólo se trabajó sobre `copia_trabajo`, sobre bases descartables (`revision`, `revision_antes`, `revision_despues`) y sobre copias de la base de la tablet.
- Ningún dato personal real ni contraseña en SQLite ni en lo que se le dio a la IA.
- La tablet nunca escribe en PostgreSQL; `SIMULADO_APROBADO` se presenta como simulación, no como venta.
- Todo lo generado se leyó y se probó antes de aceptarlo; lo descartado figura en `bitacora_ia.md`.
