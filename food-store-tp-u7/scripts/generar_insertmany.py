"""Convierte docs/pedidos_export.jsonl (salida de sql/02_exportar_pedidos_json.sql)
en el bloque insertMany() de consultas_mongodb.js.

Montos -> NumberDecimal (Decimal128, sin error de redondeo binario),
cantidades -> NumberInt, fechas -> ISODate (UTC). Los _id son los id_pedido.

    python3 scripts/generar_insertmany.py docs/pedidos_export.jsonl > /tmp/insert.js
"""
import json
import sys


def js_str(s):
    return json.dumps(s, ensure_ascii=False)


def linea(l):
    return ("{ id_producto: %d, nombre: %s, cantidad: NumberInt(%d), "
            "precio_unitario: NumberDecimal(%s) }"
            % (l["id_producto"], js_str(l["nombre"]), l["cantidad"], js_str(l["precio_unitario"])))


def documento(d):
    c = d["cliente"]
    lineas = ",\n      ".join(linea(l) for l in d["lineas"])
    return (
        "  {\n"
        f"    _id: {d['_id']},\n"
        f"    fecha: ISODate({js_str(d['fecha'])}),\n"
        f"    estado: {js_str(d['estado'])},\n"
        f"    forma_pago: {js_str(d['forma_pago'])},\n"
        f"    cliente: {{ id_cliente: {c['id_cliente']}, nombre: {js_str(c['nombre'])}, apellido: {js_str(c['apellido'])} }},\n"
        f"    lineas: [\n      {lineas}\n    ],\n"
        f"    total: NumberDecimal({js_str(d['total'])})\n"
        "  }"
    )


def main(path):
    with open(path, encoding="utf-8") as f:
        docs = [json.loads(x) for x in f if x.strip()]
    print("db.pedidos.insertMany([")
    print(",\n".join(documento(d) for d in docs))
    print("]);")


if __name__ == "__main__":
    main(sys.argv[1])
