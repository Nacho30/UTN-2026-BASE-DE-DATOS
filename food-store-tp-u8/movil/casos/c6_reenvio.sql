PRAGMA foreign_keys = ON;
-- TP U8 · Caso C6 (tablet): se reenvía la misma solicitud de C5 (mismo UUID),
-- como haría una app que no recibió la respuesta y reintenta.
.print '-- Estado de la solicitud de C5 antes del reenvío:'
SELECT solicitud_uuid, estado, evaluada_en FROM cola_sync
WHERE solicitud_uuid = '55000000-0000-4000-8000-000000000001';
.print '-- Reenvío con el mismo UUID: se espera error de clave primaria'
INSERT INTO cola_sync (solicitud_uuid, id_local)
VALUES ('55000000-0000-4000-8000-000000000001', 'b5000000-0000-4000-8000-000000000005');
.print '-- Intento de forzar una reevaluación: se espera error del trigger'
UPDATE cola_sync SET estado = 'PENDIENTE', evaluada_en = NULL
WHERE solicitud_uuid = '55000000-0000-4000-8000-000000000001';
SELECT count(*) AS solicitudes_con_ese_uuid FROM cola_sync
WHERE solicitud_uuid = '55000000-0000-4000-8000-000000000001';
