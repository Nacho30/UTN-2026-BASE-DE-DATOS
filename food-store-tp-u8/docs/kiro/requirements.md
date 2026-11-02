# Requirements Document — Food Store en la feria (base de la tablet)

## Introduction

El food truck de Food Store vende en una feria sin señal. La tablet guarda una copia del catálogo y arma **borradores** de pedido; cuando vuelve la señal, una **simulación de sincronización** (el semáforo) compara cada solicitud con una instantánea del servidor PostgreSQL.

**Regla de oro:** el móvil propone, el servidor dispone. La tablet sólo consulta y arma borradores; precio, stock y ventas los decide PostgreSQL. `SIMULADO_APROBADO` no es una venta.

**Actores:** vendedor del food truck (usa la tablet, alias sin datos personales), servidor Food Store (PostgreSQL, fuente de verdad), encargado (revisa la cola).

## Requirements

### REQ-01 — Precio cambiado → CONFLICTO (amarillo)

**User Story:** Como vendedor, quiero enterarme si un precio cambió desde que copié el catálogo, para volver a confirmarlo con el cliente antes de cobrar.

#### Acceptance Criteria
1. WHEN una solicitud PENDIENTE no tiene causas de rechazo y el precio de algún ítem en la instantánea es distinto del `precio_centavos_visto` THE SYSTEM SHALL marcarla como `CONFLICTO` y registrar en el motivo el precio visto y el actual.
2. WHEN el cliente acepta el precio nuevo THE SYSTEM SHALL permitir actualizar el precio del borrador y encolar una solicitud nueva (otro `solicitud_uuid`), sin modificar la solicitud ya evaluada.

**Se prueba con:** C2 (CONFLICTO y luego SIMULADO_APROBADO con la solicitud nueva).

### REQ-02 — Stock insuficiente → RECHAZADO (rojo)

**User Story:** Como encargado, quiero que la simulación rechace un pedido que el servidor no podría cumplir, para no prometer unidades que ya no hay.

#### Acceptance Criteria
1. WHEN algún ítem de una solicitud PENDIENTE pide más unidades que el `stock` de la instantánea THE SYSTEM SHALL marcarla como `RECHAZADO` con un motivo que diga cuántas pide y cuántas quedan.
2. THE SYSTEM SHALL NOT modificar el stock ni el precio en PostgreSQL al evaluar ninguna solicitud.

**Se prueba con:** C3, y la verificación final en PostgreSQL.

### REQ-03 — Producto dado de baja → RECHAZADO y lápida en el catálogo

**User Story:** Como vendedor, quiero que un producto dado de baja desaparezca del catálogo de la tablet sin romper los borradores que ya lo usaban.

#### Acceptance Criteria
1. WHEN algún ítem de una solicitud PENDIENTE corresponde a un producto que en la instantánea figura eliminado, no disponible o inexistente THE SYSTEM SHALL marcarla como `RECHAZADO`.
2. WHEN se recarga el catálogo con una instantánea que trae el producto como eliminado THE SYSTEM SHALL ocultarlo de la consulta del catálogo disponible y conservar su fila en `producto_cache` (lápida), de modo que las claves foráneas de los borradores sigan válidas.

**Se prueba con:** C4.

### REQ-04 — Idempotencia de la cola

**User Story:** Como encargado, quiero que reenviar la misma solicitud no duplique pedidos ni cambie un resultado ya dado.

#### Acceptance Criteria
1. WHEN se intenta encolar una solicitud con un `solicitud_uuid` ya registrado THE SYSTEM SHALL rechazar la inserción con error de clave primaria.
2. WHEN se repite la simulación THE SYSTEM SHALL evaluar sólo las solicitudes en estado `PENDIENTE` y no reevaluar las ya resueltas.

**Se prueba con:** C6 (y C5, que da la solicitud verde que se reenvía).

## Fuera de alcance

- Confirmar ventas, descontar stock o crear pedidos en PostgreSQL desde la tablet.
- Interfaz de usuario y app de celular.
- Datos personales de clientes en la tablet (sólo un alias de vendedor).

## Casos que cubre el diseño sin requisito propio

- **C1** catálogo disponible sin conexión, **C5** borrador sin cambios (verde) y **C7** validación local (cantidad 0, producto inexistente): se prueban en `pruebas_sqlite.sql` y en los casos.
