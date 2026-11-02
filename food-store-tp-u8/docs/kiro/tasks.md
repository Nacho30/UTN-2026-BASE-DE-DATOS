# Implementation Plan — Food Store en la feria

- [x] 1. Servidor: crear `copia_trabajo` desde `plantilla_base` y la vista `v_snapshot_movil`
  - `servidor/01_vista_snapshot.sql`; exportación en `servidor/exportar_snapshot.sql`
  - _Requisitos: REQ-02.2, REQ-03.1_
- [x] 2. Tablet: `movil/schema_sqlite.sql` con las cinco tablas `STRICT`, `CHECK`, FK y el trigger de estado final
  - _Requisitos: REQ-03.2, REQ-04.1, REQ-04.2_
- [x] 3. Tablet: `movil/cargar_snapshot.sql` (vaciar, `.import`, upsert a `producto_cache`, ocultar lo que el servidor no informa)
  - _Requisitos: REQ-03.2_
- [x] 4. Tablet: `movil/pruebas_sqlite.sql` — borrador con `COMMIT`, operación con `ROLLBACK`, C1 y C7
- [x] 5. Tablet: `movil/semaforo.sql` — evaluación de las solicitudes `PENDIENTE`
  - _Requisitos: REQ-01.1, REQ-02.1, REQ-03.1, REQ-04.2_
- [x] 6. Casos C2 a C6: un script por paso en `movil/casos/` y `servidor/casos/`, orquestados por `correr_todo.sh`
  - _Requisitos: todos_
- [x] 7. Verificación final en PostgreSQL: pedidos, líneas y stock no cambiaron por la simulación (`servidor/verificacion_final.sql`)
  - _Requisitos: REQ-02.2_
