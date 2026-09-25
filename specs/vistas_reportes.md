# spec: vistas_reportes (Parte B)

Objetivo: exponer 3 vistas de lectura para los reportes habituales de
Food Store, más una vista de seguridad.

## vista_producto_vigente
Columnas: id_producto, producto (nombre), precio, stock, id_categoria,
categoria (nombre). Filtro de vigencia: `producto.activo = true` y
`categoria.activo = true` (ambos lados del JOIN).

## vista_pedido_cliente
Columnas: id_pedido, fecha, forma_pago, id_cliente, cliente (nombre +
apellido concatenado). Filtro de vigencia: `cliente.activo = true`
(pedido no tiene columna de vigencia propia).

## vista_detalle_pedido
Columnas: id_pedido, id_producto, producto (nombre), producto_vigente
(booleano), cantidad, precio_unitario, subtotal calculado. Sin filtro
de vigencia sobre producto: una línea de un pedido histórico debe
seguir siendo visible aunque el producto se haya dado de baja después;
en cambio se expone `producto_vigente` como columna para que quien
consuma la vista decida qué hacer con eso.

## vista_cliente_publico (criterio de seguridad)
Columnas: id_cliente, nombre, apellido, activo, fecha_alta. Columnas
ocultadas: `email`, `telefono`. Nota de adaptación: el esquema Food
Store no tiene columna de autenticación (`contraseña`), así que el
criterio de seguridad de la consigna ("exponer usuario sin la columna
contraseña") se traslada al dato sensible equivalente disponible en
este modelo — los datos de contacto directo del cliente — para poder
otorgar `SELECT` sobre esta vista a un rol de reporting sin dar acceso
a cómo contactar a cada cliente.

Criterio de aceptación (las 4): el resultado de la vista debe coincidir
exactamente, fila por fila, con la consulta manual equivalente escrita
por separado (verificación con `EXCEPT` en ambos sentidos, 0 filas de
diferencia).
