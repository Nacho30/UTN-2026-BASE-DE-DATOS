PRAGMA foreign_keys = ON;
-- =====================================================================
-- Food Store — TP Unidad 8 · movil/semaforo.sql   (consigna 2.b)
-- Simula la sincronización: compara cada solicitud PENDIENTE con
-- snapshot_servidor y guarda estado y motivo en cola_sync.
--   Rojo     RECHAZADO          algún producto no existe, no está disponible,
--                               fue dado de baja o no alcanza el stock
--   Amarillo CONFLICTO          sin rojo, pero cambió algún precio
--   Verde    SIMULADO_APROBADO  todo coincide  (NO es una venta)
-- Sólo toca solicitudes PENDIENTE: repetirlo no cambia nada.
-- No se conecta a PostgreSQL ni modifica producto_cache.
--   sqlite3 foodstore_movil.db < semaforo.sql
-- =====================================================================
WITH evaluacion AS (
    SELECT
        c.solicitud_uuid,
        CASE
            WHEN count(i.producto_id) = 0 THEN 'RECHAZADO'
            WHEN sum(s.id IS NULL
                     OR s.eliminado = 't'
                     OR s.disponible <> 't'
                     OR i.cantidad > s.stock) > 0 THEN 'RECHAZADO'
            WHEN sum(i.precio_centavos_visto <> s.precio_centavos) > 0 THEN 'CONFLICTO'
            ELSE 'SIMULADO_APROBADO'
        END AS estado,
        CASE
            WHEN count(i.producto_id) = 0 THEN 'el borrador no tiene ítems'
            ELSE coalesce(group_concat(
                CASE
                    WHEN s.id IS NULL THEN
                        'producto ' || i.producto_id || ': no existe en el servidor'
                    WHEN s.eliminado = 't' THEN
                        'producto ' || i.producto_id || ' (' || s.nombre || '): dado de baja'
                    WHEN s.disponible <> 't' THEN
                        'producto ' || i.producto_id || ' (' || s.nombre || '): no disponible'
                    WHEN i.cantidad > s.stock THEN
                        'producto ' || i.producto_id || ' (' || s.nombre || '): stock insuficiente, pide '
                        || i.cantidad || ' y quedan ' || s.stock
                    WHEN i.precio_centavos_visto <> s.precio_centavos THEN
                        'producto ' || i.producto_id || ' (' || s.nombre || '): precio visto '
                        || printf('%.2f', i.precio_centavos_visto / 100.0) || ', precio actual '
                        || printf('%.2f', s.precio_centavos / 100.0)
                END, '; '), 'todo coincide con la instantánea')
        END AS motivo
    FROM cola_sync c
    LEFT JOIN item_borrador     i ON i.id_local = c.id_local
    LEFT JOIN snapshot_servidor s ON s.id = i.producto_id
    WHERE c.estado = 'PENDIENTE'
      AND EXISTS (SELECT 1 FROM snapshot_servidor)   -- sin instantánea no se evalúa nada
    GROUP BY c.solicitud_uuid
)
UPDATE cola_sync
SET estado      = e.estado,
    motivo      = e.motivo,
    evaluada_en = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'),
    snapshot_de = (SELECT max(fecha_snapshot) FROM snapshot_servidor)
FROM evaluacion e
WHERE cola_sync.solicitud_uuid = e.solicitud_uuid;

SELECT changes() AS solicitudes_evaluadas_en_esta_corrida;

SELECT substr(solicitud_uuid, 1, 2) || '…' || substr(solicitud_uuid, -4) AS solicitud,
       substr(id_local, 1, 2) || '…' || substr(id_local, -4) AS borrador,
       estado, motivo, snapshot_de
FROM cola_sync
ORDER BY creada_en, solicitud_uuid;
