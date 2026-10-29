// =====================================================================
// Food Store — TP Unidad 7 · consultas_mongodb.js
// Subconjunto "pedidos y detalle de pedidos" migrado a MongoDB.
// Ejecutar con:  mongosh "mongodb://localhost:27017" --file consultas_mongodb.js
// (o pegarlo por bloques en la shell de mongosh / Compass).
// Los documentos se generaron desde PostgreSQL con
// sql/02_exportar_pedidos_json.sql + scripts/generar_insertmany.py.
// =====================================================================
db = db.getSiblingDB("foodstore_nosql");

// Re-ejecutable: se parte siempre de una colección vacía.
db.pedidos.drop();

// ---------------------------------------------------------------------
// Consigna 2 · Colección con validación ($jsonSchema)
// Reglas de integridad que se conservan de PostgreSQL (consigna 3):
//   - cantidad > 0 y precio_unitario >= 0 (chk_pedido_producto_*)
//   - estado y forma_pago dentro de sus dominios cerrados (ENUMs)
//   - todo pedido tiene cliente y al menos una línea (R2, R3)
// ---------------------------------------------------------------------
db.createCollection("pedidos", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "fecha", "estado", "forma_pago", "cliente", "lineas", "total"],
      properties: {
        _id:        { bsonType: "number", description: "id_pedido de PostgreSQL" },
        fecha:      { bsonType: "date" },
        estado:     { enum: ["PENDIENTE", "EN_PREPARACION", "ENTREGADO", "CANCELADO"] },
        forma_pago: { enum: ["EFECTIVO", "TARJETA", "TRANSFERENCIA"] },
        cliente: {
          bsonType: "object",
          required: ["id_cliente", "nombre", "apellido"],
          properties: { id_cliente: { bsonType: "number" } }
        },
        lineas: {
          bsonType: "array",
          minItems: 1,
          items: {
            bsonType: "object",
            required: ["id_producto", "nombre", "cantidad", "precio_unitario"],
            properties: {
              id_producto:     { bsonType: "number" },
              cantidad:        { bsonType: "int", minimum: 1 },
              precio_unitario: { bsonType: "decimal", minimum: 0 }
            }
          }
        },
        total: { bsonType: "decimal", minimum: 0 }
      }
    }
  },
  validationAction: "error"
});

// ---------------------------------------------------------------------
// Consigna 2 · Migración de los 6 pedidos (ids 1-4 de datos_iniciales.sql,
// 5-6 pedidos de prueba del TP U7)
// ---------------------------------------------------------------------
db.pedidos.insertMany([
  {
    _id: 1,
    fecha: ISODate("2026-09-20T23:15:00Z"),
    estado: "ENTREGADO",
    forma_pago: "TARJETA",
    cliente: { id_cliente: 1, nombre: "Ana", apellido: "Pérez" },
    lineas: [
      { id_producto: 1, nombre: "Hamburguesa clásica", cantidad: NumberInt(2), precio_unitario: NumberDecimal("8000.00") },
      { id_producto: 4, nombre: "Gaseosa 500 ml", cantidad: NumberInt(2), precio_unitario: NumberDecimal("2500.00") }
    ],
    total: NumberDecimal("21000.00")
  },
  {
    _id: 2,
    fecha: ISODate("2026-09-21T16:02:00Z"),
    estado: "ENTREGADO",
    forma_pago: "EFECTIVO",
    cliente: { id_cliente: 2, nombre: "Bruno", apellido: "Díaz" },
    lineas: [
      { id_producto: 3, nombre: "Pizza muzzarella", cantidad: NumberInt(1), precio_unitario: NumberDecimal("12000.00") }
    ],
    total: NumberDecimal("12000.00")
  },
  {
    _id: 3,
    fecha: ISODate("2026-09-23T00:40:00Z"),
    estado: "ENTREGADO",
    forma_pago: "TARJETA",
    cliente: { id_cliente: 1, nombre: "Ana", apellido: "Pérez" },
    lineas: [
      { id_producto: 2, nombre: "Hamburguesa doble", cantidad: NumberInt(1), precio_unitario: NumberDecimal("11000.00") },
      { id_producto: 5, nombre: "Agua mineral 500 ml", cantidad: NumberInt(1), precio_unitario: NumberDecimal("1800.00") }
    ],
    total: NumberDecimal("12800.00")
  },
  {
    _id: 4,
    fecha: ISODate("2026-09-23T15:10:00Z"),
    estado: "EN_PREPARACION",
    forma_pago: "TRANSFERENCIA",
    cliente: { id_cliente: 3, nombre: "Carla", apellido: "Gómez" },
    lineas: [
      { id_producto: 6, nombre: "Flan casero", cantidad: NumberInt(2), precio_unitario: NumberDecimal("3500.00") }
    ],
    total: NumberDecimal("7000.00")
  },
  {
    _id: 5,
    fecha: ISODate("2026-09-24T23:30:00Z"),
    estado: "PENDIENTE",
    forma_pago: "EFECTIVO",
    cliente: { id_cliente: 2, nombre: "Bruno", apellido: "Díaz" },
    lineas: [
      { id_producto: 2, nombre: "Hamburguesa doble", cantidad: NumberInt(2), precio_unitario: NumberDecimal("11000.00") },
      { id_producto: 4, nombre: "Gaseosa 500 ml", cantidad: NumberInt(2), precio_unitario: NumberDecimal("2500.00") }
    ],
    total: NumberDecimal("27000.00")
  },
  {
    _id: 6,
    fecha: ISODate("2026-09-25T16:45:00Z"),
    estado: "ENTREGADO",
    forma_pago: "TARJETA",
    cliente: { id_cliente: 3, nombre: "Carla", apellido: "Gómez" },
    lineas: [
      { id_producto: 3, nombre: "Pizza muzzarella", cantidad: NumberInt(1), precio_unitario: NumberDecimal("12000.00") },
      { id_producto: 5, nombre: "Agua mineral 500 ml", cantidad: NumberInt(1), precio_unitario: NumberDecimal("1800.00") },
      { id_producto: 6, nombre: "Flan casero", cantidad: NumberInt(1), precio_unitario: NumberDecimal("3500.00") }
    ],
    total: NumberDecimal("17300.00")
  }
]);

// Índices para los accesos de la parte 2 (multikey sobre el arreglo)
db.pedidos.createIndex({ estado: 1 });
db.pedidos.createIndex({ "lineas.id_producto": 1 });

// ---------------------------------------------------------------------
// Verificación de la migración
// ---------------------------------------------------------------------
print("== Documentos migrados:", db.pedidos.countDocuments());

// Integridad: total == Σ cantidad × precio_unitario en cada documento.
// Debe devolver 0 documentos.
print("== Pedidos con total inconsistente (esperado: ninguno)");
printjson(db.pedidos.aggregate([
  { $project: {
      total: 1,
      calculado: { $sum: { $map: { input: "$lineas", as: "l",
                    in: { $multiply: [ { $toDecimal: "$$l.cantidad" }, "$$l.precio_unitario" ] } } } } } },
  { $match: { $expr: { $ne: ["$total", "$calculado"] } } }
]).toArray());

// Prueba del validador: una línea con cantidad 0 debe rechazarse.
try {
  db.pedidos.insertOne({ _id: 999, fecha: new Date(), estado: "PENDIENTE", forma_pago: "EFECTIVO",
    cliente: { id_cliente: 1, nombre: "Ana", apellido: "Pérez" },
    lineas: [ { id_producto: 1, nombre: "Hamburguesa clásica", cantidad: NumberInt(0), precio_unitario: NumberDecimal("8500.00") } ],
    total: NumberDecimal("0") });
  print("== ERROR: el validador aceptó cantidad 0");
} catch (e) {
  print("== Validador OK, rechazó cantidad 0:", e.codeName || e.message);
}

// Acceso frecuente: el pedido completo (cabecera + cliente + líneas) en
// una sola lectura, sin $lookup. Se usa en el contraste de la consigna 7.
print("== Pedido completo _id 1");
printjson(db.pedidos.findOne({ _id: 1 }));

// ---------------------------------------------------------------------
// Consigna 4 a) Todos los pedidos, con identificador y estado
// ---------------------------------------------------------------------
print("== a) Todos los pedidos");
printjson(db.pedidos.find({}, { _id: 1, estado: 1 }).sort({ _id: 1 }).toArray());

// ---------------------------------------------------------------------
// Consigna 4 b) Pedidos en un estado existente: ENTREGADO
// ---------------------------------------------------------------------
print("== b) Pedidos ENTREGADO");
printjson(db.pedidos.find({ estado: "ENTREGADO" }, { _id: 1, estado: 1, fecha: 1 }).sort({ _id: 1 }).toArray());
print("   cantidad:", db.pedidos.countDocuments({ estado: "ENTREGADO" }));

// ---------------------------------------------------------------------
// Consigna 4 c) Pedidos que contienen un producto dentro de "lineas":
// id_producto 4 = "Gaseosa 500 ml". Se filtra por el id conservado y no
// por el nombre, que es una copia y podría cambiar en el catálogo.
// ---------------------------------------------------------------------
print("== c) Pedidos con el producto 4 (Gaseosa 500 ml)");
printjson(db.pedidos.find(
  { "lineas.id_producto": 4 },
  { _id: 1, estado: 1, lineas: { $elemMatch: { id_producto: 4 } } }
).sort({ _id: 1 }).toArray());
print("   cantidad:", db.pedidos.countDocuments({ "lineas.id_producto": 4 }));

// ---------------------------------------------------------------------
// Consigna 4 d) Pedidos con total superior a un umbral.
// Umbral = ticket promedio de los pedidos migrados (se calcula abajo:
// 16.183,33), redondeado a 16.000 → "pedidos por encima del promedio".
// ---------------------------------------------------------------------
print("== d) Ticket promedio (justifica el umbral)");
printjson(db.pedidos.aggregate([{ $group: { _id: null, promedio: { $avg: "$total" } } }]).toArray());
print("== d) Pedidos con total > 16000");
printjson(db.pedidos.find(
  { total: { $gt: NumberDecimal("16000") } },
  { _id: 1, estado: 1, total: 1 }
).sort({ _id: 1 }).toArray());
