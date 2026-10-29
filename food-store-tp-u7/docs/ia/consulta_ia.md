# Consigna 6 · Consulta a herramienta de IA

- **Herramienta:** Claude (Anthropic), modelo Claude Opus 5.5, en claude.ai.
- **Fecha:** 29/10/2026.
- **Uso:** sólo para la comparación de la consigna 6. Las afirmaciones se contrastan en el informe (consigna 7) con la documentación oficial y con `docs/evidencia/`.

## Prompt

> Estoy evaluando cómo almacenar los pedidos de Food Store, una app de pedidos de comida. Hoy está en PostgreSQL 16 con un modelo relacional normalizado (3FN): `pedido(id_pedido, fecha, estado, forma_pago, id_cliente)`, `cliente(...)`, `producto(id_producto, nombre, precio, stock, activo, ...)` y la tabla asociativa `pedido_producto(id_pedido, id_producto, cantidad, precio_unitario)` con PK compuesta. `precio_unitario` es histórico: no cambia si cambia `producto.precio`. Hay CHECK de cantidad > 0 y precio >= 0, y un trigger que al insertar una línea valida que el producto esté activo y descuenta stock con la fila bloqueada. El acceso más frecuente es leer el pedido completo (cabecera + cliente + líneas). Necesito conservar la coherencia de cantidades y precios. Compará PostgreSQL y MongoDB para almacenar y consultar estos pedidos y decime qué conviene.

## Respuesta (resumen fiel, sin la introducción)

1. **Lectura del pedido completo.** En PostgreSQL leer un pedido completo exige unir `pedido`, `cliente`, `pedido_producto` y `producto`. En MongoDB, con las líneas embebidas en el documento del pedido, se obtiene con una sola lectura (`findOne({_id})`), sin joins.
2. **Atomicidad.** En MongoDB la escritura de un documento es atómica, así que insertar un pedido con todas sus líneas embebidas no necesita transacción multi-documento.
3. **Coherencia de valores.** Las restricciones de cantidad y precio se pueden expresar con `$jsonSchema` en el validador de la colección, de forma parecida a un CHECK.
4. **Lo que se pierde.** MongoDB no tiene claves foráneas: nada impide que una línea apunte a un `id_producto` inexistente o dado de baja, y el descuento de stock (que hoy hace el trigger sobre otra tabla) pasaría a la aplicación o a una transacción multi-documento.
5. **Precio histórico.** Embeber `precio_unitario` y una copia del nombre del producto en cada línea es correcto porque es un dato del momento de la venta; no hay que referenciar el precio actual.
6. **Montos.** Para importes conviene `Decimal128` y no `double`.
7. **Recomendación.** Mantener PostgreSQL como sistema de registro de pedidos (transacciones, FK, trigger de stock) y, si la lectura de pedidos completos se vuelve un cuello de botella, usar MongoDB como réplica de lectura (vista materializada documental), no como fuente de verdad.
