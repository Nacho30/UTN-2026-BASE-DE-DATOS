# Food Store — TP Unidad 5: Administración y seguridad

Base de Datos II · Tecnicatura Universitaria en Programación · UTN · 2026
Alumno: Ignacio Martín Rodríguez

Roles de mínimo privilegio, auditoría, simulacro de incidente reconstruido con IA y anonimización de datos personales sobre la base Food Store (PostgreSQL 16).

> Todo se ejecutó **exclusivamente** contra la instancia de desarrollo propia (`foodstore_u5`). Ningún script apunta a sistemas de terceros.

## Estructura

```
food-store-tp-u5/
├── sql/
│   ├── 00_punto_de_partida.sql      reconstrucción de usuario, fn_autenticar y fn_resetear_password
│   ├── roles.sql                    Parte A — roles, GRANT/REVOKE, default privileges y 22 pruebas
│   ├── verificacion_permisos.sql    Parte A — \du + role_table_grants contra la matriz de la spec
│   ├── auditoria_config.sql         Parte B — parámetros de auditoría (ALTER SYSTEM)
│   ├── auditoria_test.sql           Parte B — secuencia de prueba
│   ├── simulacro_incidente.sql      Parte C — simulacro de acceso indebido
│   ├── usuario_anon.sql             Parte D — tabla anonimizada
│   └── verificacion_equivalencia.sql Parte D — consultas de agregación comparadas
├── scripts/
│   ├── ejecutar_auditoria_test.sh   Parte B — corre la prueba y captura el log
│   ├── ejecutar_simulacro.sh        Parte C — corre el simulacro y captura el log crudo
│   ├── origen_remoto.py             Parte C — hace que el "atacante" llegue desde otra IP
│   └── anonimizar_log.py            Parte C — anonimiza el log con el criterio de usuario_anon
├── config/pg_hba.conf               Parte B — autenticación SCRAM en lugar de trust
├── docs/
│   ├── kiro_roles_spec/             Parte A — requirements.md, design.md, tasks.md
│   ├── verificacion_permisos.txt    Parte A — salida de la verificación
│   ├── pruebas_roles.txt            Parte A — pruebas positivas/negativas
│   ├── informe_auditoria.md         Parte B
│   ├── log_auditoria_prueba.txt     Parte B
│   ├── log_simulacro_anonimizado.txt Parte C
│   ├── respuestas_ia/               respuestas completas de la IA (Partes A, C y D)
│   ├── informe_incidente.md         Parte C — contraste con la IA y decisión de contención
│   ├── verificacion_equivalencia.md Parte D
│   └── prompts.md                   texto exacto de los prompts
└── BITACORA.md                      Parte E — bitácora de uso de IA
```

## Cómo reproducir

```bash
cp .env.example .env          # completar contraseñas y ANON_SALT
set -a; . ./.env; set +a
psql -d foodstore_u5 -f sql/00_punto_de_partida.sql     # base Food Store de las Unidades 1–4
psql -d foodstore_u5 -v ON_ERROR_STOP=1 -f sql/roles.sql
psql -d foodstore_u5 -f sql/verificacion_permisos.sql
psql -f sql/auditoria_config.sql && cp config/pg_hba.conf "$PGDATA/" && pg_ctl restart
./scripts/ejecutar_auditoria_test.sh
./scripts/ejecutar_simulacro.sh && python3 scripts/anonimizar_log.py tmp/log_simulacro_crudo.log docs/log_simulacro_anonimizado.txt
psql -d foodstore_u5 -v ON_ERROR_STOP=1 -f sql/usuario_anon.sql
psql -d foodstore_u5 -f sql/verificacion_equivalencia.sql
```

`.env` (contraseñas y sal de anonimización) y `tmp/` (log crudo con datos personales) están en `.gitignore`.
