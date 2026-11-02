PRAGMA foreign_keys = ON;
-- =====================================================================
-- Food Store — TP Unidad 8 · movil/schema_sqlite.sql   (consigna 1.b)
-- Base de la tablet del food truck. SQLite 3.37+ (tablas STRICT).
--   sqlite3 foodstore_movil.db < schema_sqlite.sql
-- Re-ejecutable: borra y vuelve a crear todo.
-- OJO: PRAGMA foreign_keys es POR CONEXIÓN; por eso todos los scripts
-- de la tablet empiezan con esa misma línea.
-- =====================================================================

DROP TABLE IF EXISTS cola_sync;
DROP TABLE IF EXISTS item_borrador;
DROP TABLE IF EXISTS pedido_borrador;
DROP TABLE IF EXISTS producto_cache;
DROP TABLE IF EXISTS snapshot_servidor;

-- ---------------------------------------------------------------------
-- producto_cache: el catálogo que la tablet consulta sin señal.
-- La fuente de verdad es PostgreSQL; esta tabla sólo cambia al cargar
-- una instantánea (cargar_snapshot.sql). Las filas no se borran nunca:
-- una baja llega como eliminado = 1 (lápida).
-- ---------------------------------------------------------------------
CREATE TABLE producto_cache (
    id               INTEGER PRIMARY KEY,                 -- = producto.id_producto
    nombre           TEXT    NOT NULL CHECK (nombre <> ''),
    precio_centavos  INTEGER NOT NULL CHECK (precio_centavos >= 0),
    stock_visto      INTEGER NOT NULL CHECK (stock_visto >= 0),
    disponible       INTEGER NOT NULL CHECK (disponible IN (0, 1)),
    eliminado        INTEGER NOT NULL DEFAULT 0 CHECK (eliminado IN (0, 1)),
    copiado_en       TEXT    NOT NULL                     -- fecha de la instantánea (UTC, ISO 8601)
) STRICT;

-- ---------------------------------------------------------------------
-- pedido_borrador: lo que arma el vendedor. No es un pedido: el pedido
-- lo crea el servidor, si lo acepta.
-- ---------------------------------------------------------------------
CREATE TABLE pedido_borrador (
    id_local    TEXT NOT NULL PRIMARY KEY
                CHECK (length(id_local) = 36
                       AND substr(id_local, 9, 1) = '-' AND substr(id_local, 14, 1) = '-'
                       AND substr(id_local, 19, 1) = '-' AND substr(id_local, 24, 1) = '-'),
    usuario     TEXT NOT NULL CHECK (usuario <> ''),     -- alias del vendedor, nunca datos personales
    forma_pago  TEXT NOT NULL CHECK (forma_pago IN ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA')),
    fecha       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
) STRICT;

-- ---------------------------------------------------------------------
-- item_borrador: equivalente local de pedido_producto.
-- precio_centavos_visto = el precio que el vendedor le dijo al cliente.
-- ---------------------------------------------------------------------
CREATE TABLE item_borrador (
    id_local               TEXT    NOT NULL REFERENCES pedido_borrador (id_local) ON DELETE CASCADE,
    producto_id            INTEGER NOT NULL REFERENCES producto_cache (id) ON DELETE RESTRICT,
    cantidad               INTEGER NOT NULL CHECK (cantidad > 0),
    precio_centavos_visto  INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),
    PRIMARY KEY (id_local, producto_id)   -- un producto una sola vez por borrador, como en pedido_producto
) STRICT;

CREATE INDEX idx_item_borrador_producto ON item_borrador (producto_id);

-- ---------------------------------------------------------------------
-- cola_sync: una fila por envío al servidor. solicitud_uuid es la clave
-- de idempotencia: reenviar el mismo envío choca con la PK.
-- ---------------------------------------------------------------------
CREATE TABLE cola_sync (
    solicitud_uuid  TEXT NOT NULL PRIMARY KEY
                    CHECK (length(solicitud_uuid) = 36
                           AND substr(solicitud_uuid, 9, 1) = '-' AND substr(solicitud_uuid, 14, 1) = '-'
                           AND substr(solicitud_uuid, 19, 1) = '-' AND substr(solicitud_uuid, 24, 1) = '-'),
    id_local        TEXT NOT NULL REFERENCES pedido_borrador (id_local) ON DELETE RESTRICT,
    estado          TEXT NOT NULL DEFAULT 'PENDIENTE'
                    CHECK (estado IN ('PENDIENTE', 'CONFLICTO', 'RECHAZADO', 'SIMULADO_APROBADO')),
    motivo          TEXT,
    creada_en       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    evaluada_en     TEXT,                 -- cuándo corrió el semáforo sobre esta solicitud
    snapshot_de     TEXT,                 -- fecha de la instantánea contra la que se evaluó
    CHECK ((estado = 'PENDIENTE') = (evaluada_en IS NULL))
) STRICT;

CREATE INDEX idx_cola_sync_estado ON cola_sync (estado);

-- Un resultado ya dado no se cambia: reintentar es encolar otra solicitud.
CREATE TRIGGER trg_cola_sync_estado_final
BEFORE UPDATE OF estado, motivo, evaluada_en ON cola_sync
WHEN OLD.estado <> 'PENDIENTE'
BEGIN
    SELECT RAISE(ABORT, 'cola_sync: la solicitud ya fue evaluada y su estado es final');
END;

-- ---------------------------------------------------------------------
-- snapshot_servidor: copia cruda del CSV exportado de PostgreSQL.
-- Los booleanos vienen de psql como 't' / 'f' y se guardan así.
-- ---------------------------------------------------------------------
CREATE TABLE snapshot_servidor (
    id               INTEGER PRIMARY KEY,
    nombre           TEXT    NOT NULL,
    precio_centavos  INTEGER NOT NULL,
    stock            INTEGER NOT NULL,
    disponible       TEXT    NOT NULL CHECK (disponible IN ('t', 'f')),
    eliminado        TEXT    NOT NULL CHECK (eliminado IN ('t', 'f')),
    fecha_snapshot   TEXT    NOT NULL
) STRICT;

.print 'Tablas creadas:'
SELECT name, strict FROM pragma_table_list WHERE schema = 'main' AND type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;
