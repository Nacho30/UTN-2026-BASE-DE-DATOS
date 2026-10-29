"""Genera docs/informe_u7.pdf (TP Unidad 7, hasta 5 páginas).

Uso (desde food-store-tp-u7/):  python3 docs/generar_informe.py

La salida de MongoDB se toma de docs/evidencia/04_salida_mongodb.txt. Mientras ese
archivo no exista, el informe marca la evidencia de MongoDB como pendiente y la
tabla de verificación muestra los valores esperados.
"""
import textwrap
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (KeepTogether, Paragraph, Preformatted, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

RAIZ = Path(__file__).resolve().parent.parent
EVID = RAIZ / "docs" / "evidencia"
SALIDA_MONGO = EVID / "04_salida_mongodb.txt"
HAY_MONGO = SALIDA_MONGO.exists()

pdfmetrics.registerFont(TTFont("DV", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("DVB", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("DVM", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"))
pdfmetrics.registerFontFamily("DV", normal="DV", bold="DVB")

AZUL = colors.HexColor("#1F4E79")
GRIS = colors.HexColor("#F2F2F2")
AMBAR = colors.HexColor("#FFF4CE")

base = ParagraphStyle("base", fontName="DV", fontSize=8.6, leading=11, alignment=TA_LEFT, spaceAfter=2.5)
celda = ParagraphStyle("celda", parent=base, fontSize=7.9, leading=9.8, spaceAfter=0)
cab = ParagraphStyle("cab", parent=celda, fontName="DVB", textColor=colors.white)
h2 = ParagraphStyle("h2", parent=base, fontName="DVB", fontSize=10.2, leading=12.5, textColor=AZUL,
                    spaceBefore=7, spaceAfter=3)
titulo = ParagraphStyle("titulo", parent=base, fontName="DVB", fontSize=13.5, leading=16.5, textColor=AZUL)
sub = ParagraphStyle("sub", parent=base, fontSize=8, textColor=colors.HexColor("#595959"))
mono = ParagraphStyle("mono", fontName="DVM", fontSize=6.9, leading=8.3)
nota = ParagraphStyle("nota", parent=celda, backColor=AMBAR, borderPadding=4, spaceBefore=3, spaceAfter=5)

ANCHO = A4[0] - 30 * mm


def tabla(filas, anchos):
    datos = [[Paragraph(c, cab if i == 0 else celda) for c in f] for i, f in enumerate(filas)]
    t = Table(datos, colWidths=anchos, repeatRows=1)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), AZUL),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS]),
        ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#BFBFBF")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("LEFTPADDING", (0, 0), (-1, -1), 3), ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]))
    return t


def bloque(texto):
    t = Table([[Preformatted(texto, mono)]], colWidths=[ANCHO])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), GRIS),
        ("BOX", (0, 0), (-1, -1), 0.3, colors.HexColor("#BFBFBF")),
        ("LEFTPADDING", (0, 0), (-1, -1), 5), ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]))
    return t


def extracto(archivo, desde, hasta):
    """Líneas del archivo de evidencia entre dos marcadores (incluye 'desde', excluye 'hasta')."""
    lineas = (EVID / archivo).read_text(encoding="utf-8").splitlines()
    i = next(n for n, l in enumerate(lineas) if l.startswith(desde))
    j = next((n for n, l in enumerate(lineas) if n > i and hasta and l.startswith(hasta)), len(lineas))
    return "\n".join(l for l in lineas[i:j] if l.strip())


def compactar(texto):
    """Una línea por sección '== ...' y un documento por línea, para que entre en el PDF."""
    import re
    secciones, actual = [], None
    for l in texto.splitlines():
        if l.startswith("=="):
            if actual is not None:
                secciones.append(actual)
            actual = [l, ""]
        elif actual is not None:
            actual[1] += " " + l.strip()
    if actual is not None:
        secciones.append(actual)
    salida = []
    for cab_, cuerpo in secciones:
        cuerpo = re.sub(r"\s+", " ", cuerpo).strip()
        cuerpo = re.sub(r"\{ ", "{", cuerpo).replace(" }", "}").replace("[ ", "[").replace(" ]", "]")
        cuerpo = re.sub(r"\}, \{(_id)", r"},\n  {\1", cuerpo)
        cuerpo = re.sub(r"\] cantidad: (\d+)$", r"]\ncantidad: \1", cuerpo)
        salida.append(cab_)
        for linea in cuerpo.splitlines() if cuerpo else []:
            salida.extend(textwrap.wrap(linea.strip(), 116, initial_indent="  ", subsequent_indent="      "))
    return "\n".join(salida)


mongo_txt = compactar(SALIDA_MONGO.read_text(encoding="utf-8").strip()) if HAY_MONGO else ""
esp = "" if HAY_MONGO else " <i>(esperado)</i>"

h = []
h.append(Paragraph("NoSQL y nuevas formas de almacenamiento — Pedidos de Food Store en MongoDB", titulo))
h.append(Paragraph("TP Unidad 7 · Bases de Datos II · Tecnicatura Universitaria en Programación · UTN — "
                   "<b>Ignacio Martín Rodríguez</b> — 29/10/2026 · PostgreSQL 16 · MongoDB "
                   "(base <b>foodstore_nosql</b>) · repositorio <b>github.com/Nacho30/UTN-2026-BASE-DE-DATOS</b>, "
                   "rama <b>tp-unidad-7</b>, carpeta <b>food-store-tp-u7/</b>", sub))

# ------------------------------------------------------------------ Parte 1
h.append(Paragraph("1. Subconjunto elegido y modelo documental (consigna 1)", h2))
h.append(Paragraph(
    "Se toma el subconjunto <b>pedidos y detalle de pedidos</b> del esquema real (<b>schema.sql</b>). "
    "Intervienen cuatro tablas: <b>pedido</b> (PK <b>id_pedido</b>; FK <b>id_cliente</b> → cliente, "
    "ON DELETE RESTRICT), <b>pedido_producto</b> (PK compuesta <b>(id_pedido, id_producto)</b>; FK a "
    "pedido con CASCADE y a producto con RESTRICT; <b>precio_unitario</b> histórico, R4), y "
    "<b>cliente</b> y <b>producto</b>, de las que sólo se copian los datos que el pedido muestra.", base))
h.append(Paragraph(
    "<b>Hallazgo:</b> el Food Store real no tiene estado de pedido. Como la consigna lo pide, "
    "<b>sql/01_estado_y_pedidos_prueba.sql</b> agrega el ENUM <b>estado_pedido</b> "
    "(PENDIENTE, EN_PREPARACION, ENTREGADO, CANCELADO) y la columna <b>pedido.estado</b> (NOT NULL, "
    "DEFAULT PENDIENTE), con las convenciones del proyecto y sin tocar <b>schema.sql</b>.", base))
h.append(Paragraph("Colección <b>pedidos</b> — un documento por pedido:", base))
h.append(bloque(
    "{ _id:        <id_pedido>              // identificador de origen conservado\n"
    "  fecha:      Date (UTC)               // pedido.fecha\n"
    "  estado:     \"ENTREGADO\" | ...        // pedido.estado (ENUM)\n"
    "  forma_pago: \"TARJETA\" | ...          // pedido.forma_pago (ENUM)\n"
    "  cliente:  { id_cliente, nombre, apellido }        // objeto embebido (copia)\n"
    "  lineas: [ { id_producto, nombre, cantidad: Int32, // arreglo embebido = pedido_producto\n"
    "              precio_unitario: Decimal128 } ],      // precio histórico, no el de lista\n"
    "  total:      Decimal128 }             // Σ cantidad × precio_unitario (derivado)"))

h.append(Paragraph("2. Migración (consigna 2)", h2))
h.append(Paragraph(
    "Se migran <b>6 pedidos con 11 líneas</b>. Los pedidos 1 a 4 son los de <b>datos_iniciales.sql</b>; "
    "los <b>5 y 6 son pedidos de prueba</b> de esta unidad (había sólo 4), insertados en PostgreSQL de "
    "modo que pasan por el trigger de RN1/RN2 y descuentan stock. Los documentos no se escribieron a "
    "mano: <b>sql/02_exportar_pedidos_json.sql</b> los arma desde PostgreSQL y "
    "<b>scripts/generar_insertmany.py</b> los vuelca en el <b>insertMany()</b> de "
    "<b>consultas_mongodb.js</b> (montos como <b>NumberDecimal</b>, cantidades como <b>NumberInt</b>, "
    "fechas como <b>ISODate</b>). La colección se crea con un validador <b>$jsonSchema</b> e índices "
    "sobre <b>estado</b> y <b>lineas.id_producto</b>.", base))
h.append(tabla([
    ["_id", "Fecha (-03)", "Estado", "Cliente", "Líneas (producto × cant. a precio histórico)", "Total"],
    ["1", "20/09 20:15", "ENTREGADO", "1 Ana Pérez", "Hamburguesa clásica 2 × 8.000 · Gaseosa 500 ml 2 × 2.500", "21.000"],
    ["2", "21/09 13:02", "ENTREGADO", "2 Bruno Díaz", "Pizza muzzarella 1 × 12.000", "12.000"],
    ["3", "22/09 21:40", "ENTREGADO", "1 Ana Pérez", "Hamburguesa doble 1 × 11.000 · Agua mineral 1 × 1.800", "12.800"],
    ["4", "23/09 12:10", "EN_PREPARACION", "3 Carla Gómez", "Flan casero 2 × 3.500", "7.000"],
    ["5 (prueba)", "24/09 20:30", "PENDIENTE", "2 Bruno Díaz", "Hamburguesa doble 2 × 11.000 · Gaseosa 500 ml 2 × 2.500", "27.000"],
    ["6 (prueba)", "25/09 13:45", "ENTREGADO", "3 Carla Gómez", "Pizza muzzarella 1 × 12.000 · Agua mineral 1 × 1.800 · Flan 1 × 3.500", "17.300"],
], [15 * mm, 18 * mm, 23 * mm, 21 * mm, ANCHO - 93 * mm, 16 * mm]))

h.append(Paragraph("3. Reglas de integridad y qué se embebió (consigna 3)", h2))
h.append(Paragraph(
    "<b>Regla 1 — Precio histórico (R4).</b> Cada línea lleva el <b>precio_unitario</b> de "
    "<b>pedido_producto</b>, nunca <b>producto.precio</b>. No es teórico: el pedido 1 vendió la "
    "hamburguesa clásica a 8.000 y hoy su precio de lista es 8.500; migrar con el precio actual daría "
    "un total de 22.000 en vez de 21.000 (<b>03_contraste_ia_postgresql.txt</b>).", base))
h.append(Paragraph(
    "<b>Regla 2 — Cantidades y montos válidos y total coherente.</b> Se conservan los CHECK "
    "<b>cantidad &gt; 0</b> y <b>precio_unitario ≥ 0</b>, y los dominios de estado y forma de pago, "
    "como validador <b>$jsonSchema</b> (con <b>validationAction: \"error\"</b> y prueba de rechazo de "
    "una línea con cantidad 0). Como <b>total</b> es un dato derivado que PostgreSQL no guarda (3FN), "
    "el script verifica que en todos los documentos sea igual a Σ cantidad × precio_unitario.", base))
h.append(Paragraph(
    "<b>Por qué embebido.</b> Las líneas no existen sin su pedido (en PostgreSQL se borran en CASCADE), "
    "son pocas por pedido, se leen siempre junto con él y se escriben una sola vez: es la relación "
    "«contiene» para la que la documentación de MongoDB recomienda embeber, y deja el pedido completo en "
    "una lectura y una escritura atómica. Del cliente y del producto se copian sólo id y nombre "
    "(lo que el pedido muestra), conservando sus id para volver a PostgreSQL. <b>Precio de lista, stock, "
    "activo, email y teléfono quedan fuera</b>: cambian independientemente del pedido y copiarlos "
    "duplicaría datos que no son del momento de la venta.", base))

# ------------------------------------------------------------------ Parte 2
h.append(KeepTogether([Paragraph("4. Consultas en MongoDB (consigna 4)", h2), tabla([
    ["", "Instrucción en consultas_mongodb.js", "Resultado"],
    ["a", "find({}, {_id: 1, estado: 1}).sort({_id: 1})", "6 pedidos: 1, 2, 3 y 6 ENTREGADO; 4 EN_PREPARACION; 5 PENDIENTE" + esp],
    ["b", "find({estado: \"ENTREGADO\"}, {_id: 1, estado: 1, fecha: 1})", "4 pedidos: 1, 2, 3, 6" + esp],
    ["c", "find({\"lineas.id_producto\": 4}, {_id: 1, estado: 1, lineas: {$elemMatch: {id_producto: 4}}})"
          " — producto 4 = Gaseosa 500 ml; se filtra por id, no por el nombre copiado",
     "2 pedidos: 1, 5" + esp],
    ["d", "find({total: {$gt: NumberDecimal(\"16000\")}}, {_id: 1, estado: 1, total: 1})",
     "3 pedidos: 1 (21.000), 5 (27.000), 6 (17.300)" + esp],
], [6 * mm, ANCHO - 66 * mm, 60 * mm])]))
h.append(Paragraph(
    "<b>Umbral de d).</b> 16.000 es el ticket promedio de los pedidos migrados (16.183,33, calculado con "
    "<b>$avg</b> en el script y con <b>AVG</b> en PostgreSQL) redondeado: la consulta responde «qué "
    "pedidos están por encima del ticket promedio». Un umbral fijo como 10.000 dejaría afuera sólo al "
    "pedido 4 y no distinguiría nada.", base))
if not HAY_MONGO:
    h.append(Paragraph(
        "<b>Pendiente:</b> la ejecución en MongoDB se hace con "
        "<b>mongosh \"mongodb://localhost:27017\" --file consultas_mongodb.js</b>, guardando la salida en "
        "<b>docs/evidencia/04_salida_mongodb.txt</b> y volviendo a generar este PDF. Hasta entonces, los "
        "resultados marcados como <i>esperado</i> se derivan de los mismos datos exportados desde "
        "PostgreSQL.", nota))

h.append(Paragraph("5. Verificación contra PostgreSQL (consigna 5)", h2))
h.append(Paragraph(
    "En <b>consultas_postgresql.sql</b>: b) <b>WHERE estado = 'ENTREGADO'</b>; c) <b>EXISTS</b> sobre "
    "<b>pedido_producto</b> con <b>id_producto = 4</b> (la PK compuesta impide repetir el producto en un "
    "pedido, así que un JOIN daría lo mismo, pero EXISTS no duplicaría pedidos si eso cambiara). "
    "Salida completa en <b>02_consultas_postgresql.txt</b>.", base))
h.append(tabla([
    ["Consulta", "Cantidad en PostgreSQL", "Cantidad en MongoDB", "IDs PostgreSQL", "IDs MongoDB", "Coinciden los IDs"],
    ["Estado seleccionado: ENTREGADO", "4", "4" + esp, "1, 2, 3, 6", "1, 2, 3, 6" + esp, "Sí" + esp],
    ["Producto seleccionado: 4 Gaseosa 500 ml", "2", "2" + esp, "1, 5", "1, 5" + esp, "Sí" + esp],
], [38 * mm, 25 * mm, 25 * mm, 25 * mm, 25 * mm, ANCHO - 138 * mm]))
h.append(Paragraph(
    "<b>Diferencias detectadas entre los modelos</b> (no cambian b ni c, pero sí cambiarían otras "
    "consultas y por eso se corrigieron o documentaron):", base))
h.append(tabla([
    ["Diferencia", "Efecto", "Corrección"],
    ["Fecha: PostgreSQL muestra la hora local (-03); MongoDB guarda Date en UTC.",
     "El pedido 3 (22/09 21:40 local) es del 23/09 en UTC: un filtro «pedidos del 22/09» en Mongo lo "
     "perdería.", "Filtrar por rango con el desfase: 22/09 03:00Z a 23/09 03:00Z."],
    ["Precio: tomar producto.precio en lugar de pedido_producto.precio_unitario.",
     "Pedido 1: total 22.000 en vez de 21.000; d) y cualquier suma de facturación no coincidirían.",
     "El export usa precio_unitario; el script verifica total = Σ líneas."],
    ["Nombre del producto: en Mongo es una copia.",
     "Si el catálogo renombra un producto, buscar por nombre dejaría de coincidir con PostgreSQL.",
     "La consulta c) filtra por lineas.id_producto, el id conservado."],
    ["Tipos numéricos: en mongosh un número sin tipo es double.",
     "Montos double pueden arrastrar error binario (0,1 + 0,2 ≠ 0,3) frente a NUMERIC(10,2).",
     "NumberDecimal para montos y NumberInt para cantidades; el validador lo exige."],
], [48 * mm, ANCHO - 106 * mm, 58 * mm]))

# ------------------------------------------------------------------ Parte 3
h.append(Paragraph("6. Consulta a la IA (consigna 6)", h2))
h.append(Paragraph(
    "Herramienta: Claude (Anthropic), 29/10/2026. El prompt describió el modelo actual (4 tablas, 3FN, "
    "PK compuesta, <b>precio_unitario</b> histórico, CHECK y trigger de stock), el acceso frecuente al "
    "pedido completo y la necesidad de conservar la coherencia de cantidades y precios. Prompt y "
    "respuesta resumida en <b>docs/ia/consulta_ia.md</b>. La IA recomendó mantener PostgreSQL como "
    "sistema de registro y usar MongoDB, si hiciera falta, como réplica de lectura.", base))

h.append(Paragraph("7. Contraste de afirmaciones (consigna 7)", h2))
h.append(tabla([
    ["Afirmación de la IA", "Contraste", "Veredicto"],
    ["«En PostgreSQL leer un pedido completo exige unir pedido, cliente, pedido_producto y producto; en "
     "MongoDB, con las líneas embebidas, es una sola lectura.»",
     "<b>Laboratorio:</b> el EXPLAIN del pedido 1 muestra 3 joins sobre 4 tablas, todos por PK o índice "
     "(<b>pedido_pkey</b>, <b>cliente_pkey</b>, <b>pedido_producto_pkey</b>). En MongoDB, "
     "<b>findOne({_id: 1})</b> devuelve el documento con cliente y líneas, sin <b>$lookup</b>. <b>Documentación</b> (Embedded Data): "
     "embeber permite obtener datos relacionados en una sola operación.",
     "<b>Correcta</b>, con matiz: los joins son por clave e indexados, así que «4 tablas» no implica "
     "lentitud con este volumen."],
    ["«Las restricciones de cantidad y precio se pueden expresar con $jsonSchema, de forma parecida a un "
     "CHECK.»",
     "<b>Documentación</b> (Specify JSON Schema Validation): <b>bsonType</b>, <b>minimum</b>, "
     "<b>enum</b> y <b>minItems</b> están soportados y con <b>validationAction: \"error\"</b> se "
     "rechaza la escritura. Pero el validador sólo evalúa el documento que se escribe: no puede consultar "
     "otra colección. <b>Laboratorio:</b> RN1 (producto activo) y RN2 (stock: los pedidos de prueba "
     "bajaron, p. ej., la hamburguesa doble de 9 a 7) dependen de la fila de <b>producto</b>.",
     "<b>Parcialmente correcta</b>: cubre la regla 2 de la consigna 3, no RN1/RN2 ni las FK, que en "
     "MongoDB pasarían a la aplicación o a una transacción multidocumento."],
], [50 * mm, ANCHO - 92 * mm, 42 * mm]))
h.append(Paragraph(
    "También se verificó la afirmación de atomicidad: según <b>Atomicity and Transactions</b>, las "
    "escrituras son atómicas a nivel de documento único y las transacciones distribuidas cuestan más "
    "y no reemplazan un buen diseño de esquema; un pedido con sus líneas embebidas se inserta entero o "
    "no se inserta.", base))

h.append(Paragraph("Conclusión", h2))
h.append(Paragraph(
    "Conviene <b>mantener PostgreSQL</b> como almacenamiento de los pedidos de Food Store. "
    "<b>Criterio 1, integridad:</b> las reglas que más importan al pedido cruzan entidades: el trigger "
    "valida que el producto esté activo y descuenta stock con la fila bloqueada, y las FK impiden líneas "
    "huérfanas. El validador de MongoDB sólo ve el documento, así que esas reglas pasarían a la "
    "aplicación o a transacciones multidocumento, que la propia documentación desaconseja como sustituto "
    "del diseño. <b>Criterio 2, patrón de acceso y rendimiento:</b> el documento embebido coincide con "
    "la lectura frecuente del pedido completo y lo escribe atómicamente; es la ventaja real de MongoDB. "
    "Pero en PostgreSQL esa lectura son joins por clave primaria e índice, sin costo relevante con el "
    "volumen del proyecto. <b>Criterio 3, coherencia de montos:</b> la migración exige cuidar tipos "
    "(Decimal128), precio histórico y zona horaria; cada copia es una fuente posible de diferencias. "
    "Combinar tecnologías tendría sentido sólo si se midiera un cuello de botella en la lectura de "
    "pedidos: MongoDB como réplica de lectura alimentada desde PostgreSQL, nunca como fuente de verdad.",
    base))

# ------------------------------------------------------------------ Evidencias
h.append(Paragraph("Anexo · Evidencias de ejecución", h2))
h.append(Paragraph("<b>PostgreSQL</b> — consultas b) y c) (<b>docs/evidencia/02_consultas_postgresql.txt</b>):", base))
h.append(bloque(extracto("02_consultas_postgresql.txt", "== b)", "== d)")))
h.append(Spacer(1, 4))
h.append(Paragraph("<b>PostgreSQL</b> — umbral de d) y contraste de precio y fechas "
                   "(<b>02_consultas_postgresql.txt</b>, <b>03_contraste_ia_postgresql.txt</b>):", base))
h.append(bloque(extracto("02_consultas_postgresql.txt", "== d)", None) + "\n\n" +
                extracto("03_contraste_ia_postgresql.txt", "== Si se migrara", "== RN2")))
h.append(Spacer(1, 4))
h.append(Paragraph("<b>MongoDB</b> — salida de <b>consultas_mongodb.js</b> "
                   "(<b>docs/evidencia/04_salida_mongodb.txt</b>):", base))
if HAY_MONGO:
    h.append(bloque(mongo_txt))
else:
    h.append(Paragraph("Pendiente de ejecución (ver nota de la sección 4).", nota))


def pie(canvas, doc):
    canvas.saveState()
    canvas.setFont("DV", 7)
    canvas.setFillColor(colors.HexColor("#808080"))
    canvas.drawString(15 * mm, 9 * mm, "Bases de Datos II · TP Unidad 7 · Food Store")
    canvas.drawRightString(A4[0] - 15 * mm, 9 * mm, f"Página {doc.page}")
    canvas.restoreState()


doc = SimpleDocTemplate(str(RAIZ / "docs" / "informe_u7.pdf"), pagesize=A4,
                        leftMargin=15 * mm, rightMargin=15 * mm, topMargin=13 * mm, bottomMargin=15 * mm,
                        title="TP Unidad 7 — Food Store NoSQL", author="Ignacio Martín Rodríguez")
doc.build(h, onFirstPage=pie, onLaterPages=pie)
print("informe_u7.pdf generado; evidencia MongoDB:", "incluida" if HAY_MONGO else "PENDIENTE")
