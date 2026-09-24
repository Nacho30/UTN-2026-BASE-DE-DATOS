-- =====================================================================
-- Food Store — schema.sql
-- TP1 Base de Datos I (UTN) — esquema conciliado de las Partes 2 y 3
-- =====================================================================
-- Reglas de negocio referenciadas: R1..R7 (ver enunciado, Sección 2)

-- Dominio cerrado para la forma de pago (R.-)
CREATE TYPE forma_pago AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA');

-- ---------------------------------------------------------------------
-- categoria
-- ---------------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(80)   NOT NULL UNIQUE,   -- clave candidata (Parte 1)
    descripcion     VARCHAR(255),
    activo          BOOLEAN       NOT NULL DEFAULT TRUE,  -- baja lógica, R7
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- producto
-- ---------------------------------------------------------------------
CREATE TABLE producto (
    id_producto     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(120)  NOT NULL,
    descripcion     VARCHAR(255),
    precio          NUMERIC(10,2) NOT NULL,
    stock           INTEGER       NOT NULL DEFAULT 0,
    activo          BOOLEAN       NOT NULL DEFAULT TRUE,  -- baja lógica, R7
    -- R1: todo producto pertenece exactamente a una categoría -> NOT NULL.
    -- ON DELETE RESTRICT: R7 dice que las categorías no se borran físicamente
    -- (se marcan activo=false); RESTRICT actúa como red de seguridad para que
    -- un DELETE accidental sobre categoria nunca deje productos huérfanos.
    id_categoria    BIGINT        NOT NULL REFERENCES categoria(id_categoria) ON DELETE RESTRICT,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT chk_producto_precio_no_negativo CHECK (precio >= 0),  -- R5
    CONSTRAINT chk_producto_stock_no_negativo  CHECK (stock  >= 0)   -- R5
);

-- Acelera "listar productos vigentes de una categoría" (WHERE id_categoria = ? AND activo = true),
-- consulta esperada para armar el menú/catálogo por categoría.
CREATE INDEX idx_producto_categoria ON producto (id_categoria);

-- ---------------------------------------------------------------------
-- cliente
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(80)  NOT NULL,
    apellido        VARCHAR(80)  NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,  -- R6
    telefono        VARCHAR(30),
    activo          BOOLEAN      NOT NULL DEFAULT TRUE,
    fecha_alta      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- pedido
-- ---------------------------------------------------------------------
CREATE TABLE pedido (
    id_pedido       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha           TIMESTAMPTZ NOT NULL DEFAULT now(),
    forma_pago      forma_pago  NOT NULL,
    -- R2: todo pedido pertenece exactamente a un cliente -> NOT NULL.
    -- ON DELETE RESTRICT: no queremos perder el historial de compras de un
    -- cliente por un borrado accidental; la baja de un cliente se maneja
    -- con el flag "activo", igual que en categoria/producto (R7).
    id_cliente      BIGINT      NOT NULL REFERENCES cliente(id_cliente) ON DELETE RESTRICT
);

-- Acelera "buscar los pedidos de un cliente" (WHERE id_cliente = ?),
-- consulta esperada para el historial de compras de un cliente.
CREATE INDEX idx_pedido_cliente ON pedido (id_cliente);

-- ---------------------------------------------------------------------
-- pedido_producto (entidad asociativa, resuelve la relación N:M R3/R4)
-- ---------------------------------------------------------------------
CREATE TABLE pedido_producto (
    -- ON DELETE CASCADE: una línea de pedido no tiene existencia propia sin
    -- su pedido (es una entidad débil); si se elimina un pedido, sus líneas
    -- se eliminan con él.
    id_pedido        BIGINT        NOT NULL REFERENCES pedido(id_pedido) ON DELETE CASCADE,
    -- ON DELETE RESTRICT: a diferencia del pedido, el producto no debería
    -- borrarse nunca mientras tenga líneas asociadas (se da de baja con
    -- "activo", R7); RESTRICT protege el histórico de ventas.
    id_producto      BIGINT        NOT NULL REFERENCES producto(id_producto) ON DELETE RESTRICT,
    cantidad         INTEGER       NOT NULL,
    -- Histórico (R4): el precio de lista de producto puede cambiar; este
    -- valor queda fijo en el momento de la venta y no se recalcula.
    precio_unitario  NUMERIC(10,2) NOT NULL,
    PRIMARY KEY (id_pedido, id_producto),  -- clave compuesta: ver justificación Parte 2
    CONSTRAINT chk_pedido_producto_cantidad_positiva  CHECK (cantidad > 0),
    CONSTRAINT chk_pedido_producto_precio_no_negativo CHECK (precio_unitario >= 0)
);

-- Acelera reportes de "cuánto se vendió de este producto" / "en qué pedidos
-- aparece" (WHERE id_producto = ?), ya que la PK compuesta solo indexa
-- eficientemente por id_pedido como columna líder.
CREATE INDEX idx_pedido_producto_producto ON pedido_producto (id_producto);

-- NOTA: subtotal (cantidad * precio_unitario) se calcula en consultas/vistas,
-- no se almacena como columna: es 100% derivable de datos ya presentes en
-- la fila y guardarlo violaría 3FN (dependencia transitiva), según lo
-- desarrollado en la Parte 3.
