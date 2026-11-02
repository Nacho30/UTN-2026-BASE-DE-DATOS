"""Genera docs/informe.pdf del TP Unidad 8 (máximo 6 páginas).

Uso (desde food-store-tp-u8/):  python3 docs/generar_informe.py
Toma los extractos de evidencia de docs/evidencia/, así que hay que correr
antes correr_todo.sh y los scripts de revision/.
"""
import csv
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

pdfmetrics.registerFont(TTFont("DV", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("DVB", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("DVM", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"))
pdfmetrics.registerFontFamily("DV", normal="DV", bold="DVB")

AZUL = colors.HexColor("#1F4E79")
GRIS = colors.HexColor("#F2F2F2")
ROJO = colors.HexColor("#F8D7DA")
AMAR = colors.HexColor("#FFF3CD")
VERDE = colors.HexColor("#D4EDDA")

base = ParagraphStyle("base", fontName="DV", fontSize=9, leading=11.6, alignment=TA_LEFT, spaceAfter=2.5)
celda = ParagraphStyle("celda", parent=base, fontSize=8.1, leading=10, spaceAfter=0)
cab = ParagraphStyle("cab", parent=celda, fontName="DVB", textColor=colors.white)
h2 = ParagraphStyle("h2", parent=base, fontName="DVB", fontSize=10.2, leading=12.5, textColor=AZUL,
                    spaceBefore=7, spaceAfter=3)
titulo = ParagraphStyle("titulo", parent=base, fontName="DVB", fontSize=13.5, leading=16.5, textColor=AZUL)
sub = ParagraphStyle("sub", parent=base, fontSize=8, textColor=colors.HexColor("#595959"))
mono = ParagraphStyle("mono", fontName="DVM", fontSize=6.6, leading=8)
regla = ParagraphStyle("regla", parent=celda, backColor=colors.HexColor("#E8F0F8"), borderPadding=4,
                       spaceBefore=3, spaceAfter=5, fontSize=8)

ANCHO = A4[0] - 30 * mm


def tabla(filas, anchos, fondos=None):
    datos = [[Paragraph(c, cab if i == 0 else celda) for c in f] for i, f in enumerate(filas)]
    t = Table(datos, colWidths=anchos, repeatRows=1)
    estilo = [
        ("BACKGROUND", (0, 0), (-1, 0), AZUL),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS]),
        ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#BFBFBF")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 2), ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("LEFTPADDING", (0, 0), (-1, -1), 3), ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]
    for (col, fila), color in (fondos or {}).items():
        estilo.append(("BACKGROUND", (col, fila), (col, fila), color))
    t.setStyle(TableStyle(estilo))
    return t


def bloque(texto):
    t = Table([[Preformatted(texto, mono)]], colWidths=[ANCHO])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), GRIS),
        ("BOX", (0, 0), (-1, -1), 0.3, colors.HexColor("#BFBFBF")),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]))
    return t


def sin_columna(texto, columna):
    """Quita de una salida en columnas todo lo que está desde la columna indicada."""
    lineas = texto.splitlines()
    corte = lineas[0].find(columna)
    return "\n".join(l[:corte].rstrip() for l in lineas) if corte > 0 else texto


def tramo(archivo, desde, hasta=None, ultima=False):
    """Líneas de un archivo de evidencia desde un marcador hasta otro (excluido)."""
    lineas = (EVID / archivo).read_text(encoding="utf-8").splitlines()
    idx = [n for n, l in enumerate(lineas) if l.startswith(desde)]
    i = idx[-1] if ultima else idx[0]
    j = next((n for n, l in enumerate(lineas) if n > i and hasta and l.startswith(hasta)), len(lineas))
    return "\n".join(l.rstrip() for l in lineas[i:j] if l.strip() and not set(l.strip()) <= {"-"})


with open(EVID / "snapshots" / "00_inicial.csv", encoding="utf-8") as f:
    FECHA_COPIA = next(csv.DictReader(f))["fecha_snapshot"]

h = []
h.append(Paragraph("Food Store en la feria: la base de la tablet y el cierre de la capa de datos", titulo))
h.append(Paragraph("TP N.º 8 · Unidad 8 · Bases de Datos II · Tecnicatura Universitaria en Programación · UTN — "
                   "<b>Ignacio Martín Rodríguez</b> — 02/11/2026 · PostgreSQL 16.15 (base de pruebas "
                   "<b>copia_trabajo</b>) · SQLite 3.53 · repositorio <b>github.com/Nacho30/UTN-2026-BASE-DE-DATOS</b>, "
                   "rama <b>tp-unidad-8</b>, etiqueta <b>tp8</b>, carpeta <b>food-store-tp-u8/</b>", sub))
h.append(Paragraph("<b>Regla de oro:</b> el móvil propone, el servidor dispone. La tablet sólo consulta y arma "
                   "borradores; precio, stock y ventas los decide PostgreSQL. <b>SIMULADO_APROBADO no es una "
                   "venta:</b> ningún paso de la tablet escribe en el servidor.", regla))

# ------------------------------------------------------------------ 1.a
h.append(Paragraph("1.a Qué datos viajan a la tablet", h2))
h.append(tabla([
    ["Dato en PostgreSQL", "¿Viaja?", "Cómo llega a SQLite / por qué no"],
    ["producto.id_producto", "Sí", "<b>id</b> de <b>producto_cache</b>; lo usan las FK de los ítems y el semáforo"],
    ["producto.nombre", "Sí", "<b>nombre</b>, para mostrar y para el motivo del semáforo"],
    ["producto.precio NUMERIC(10,2)", "Sí", "<b>precio_centavos</b> entero: precio × 100, exacto"],
    ["producto.stock", "Sí", "<b>stock_visto</b>: sólo informativo, envejece en cuanto se copia"],
    ["producto.activo, categoria.activo", "Sí, derivados", "<b>disponible</b> (activo, categoría activa y stock &gt; 0) y <b>eliminado</b> (= NOT activo, lápida)"],
    ["fecha de la copia", "Sí", "<b>copiado_en</b> = <b>fecha_snapshot</b> de la vista"],
    ["producto.descripcion, id_categoria, created_at", "No", "La venta en la feria no los usa"],
    ["cliente (nombre, apellido, email, teléfono)", "No", "Datos personales: la tablet registra sólo un alias de vendedor"],
    ["pedido, pedido_producto, usuarios y credenciales (U5)", "No", "Historial y seguridad viven sólo en el servidor"],
], [52 * mm, 20 * mm, ANCHO - 72 * mm]))
h.append(Paragraph(
    "Viaja lo mínimo para vender sin señal: identificar el producto, mostrar su nombre y su precio y saber si se "
    "puede ofrecer. <b>La fuente de verdad es PostgreSQL</b>: la tablet tiene una copia fechada que puede estar "
    "vieja, por eso el precio y el stock que ve son sólo una referencia y el semáforo vuelve a compararlos con una "
    "instantánea nueva.", base))

h.append(Paragraph("1.b, 1.c y 2.a En dos líneas", h2))
h.append(Paragraph(
    "<b>schema_sqlite.sql</b> empieza con <b>PRAGMA foreign_keys = ON;</b> y crea las cuatro tablas pedidas más "
    "<b>snapshot_servidor</b>, todas <b>STRICT</b>, con centavos enteros, <b>CHECK</b> de dominios y cantidades, "
    "FK y un trigger que impide cambiar una solicitud ya evaluada. <b>pruebas_sqlite.sql</b> guarda un borrador "
    "completo con <b>COMMIT</b>, deshace otro con <b>ROLLBACK</b>, lee el catálogo sólo desde <b>producto_cache</b> (C1; repetido con PostgreSQL detenido en <b>14_c1_sin_servidor.txt</b>) y "
    "muestra que cantidad 0 y producto 999 fallan sin dejar filas (C7). La vista <b>v_snapshot_movil</b> incluye "
    "los productos dados de baja (lápidas); la instantánea inicial es del <b>" + FECHA_COPIA + "</b> (UTC).", base))

# ------------------------------------------------------------------ 2.c
h.append(Paragraph("2.c Los casos", h2))
h.append(Paragraph(
    "Cada caso: borrador en la tablet → cambio en <b>copia_trabajo</b> → <b>exportar_snapshot.sql</b> → "
    "<b>cargar_snapshot.sql</b> → <b>semaforo.sql</b>. Todo lo corre <b>correr_todo.sh</b> desde cero; las salidas "
    "están en <b>docs/evidencia/03</b> a <b>08</b>. Las tablas de abajo resumen esas salidas.", base))
filas = [
    ["Caso", "Comandos", "Resultado", "Explicación"],
    ["C2", "c2_borrador.sql (2 × Hamburguesa clásica a 8.500,00) · servidor/casos/c2_subir_precio.sql "
           "(precio 9.200,00) · exportar, cargar, semaforo.sql · c2_acepta.sql · semaforo.sql",
     "CONFLICTO: «precio visto 8500.00, precio actual 9200.00». La solicitud nueva: SIMULADO_APROBADO",
     "No hay causa roja, pero el precio cambió. La solicitud en CONFLICTO queda como historial (estado final); "
     "el cliente acepta, el borrador toma el precio del catálogo nuevo y se encola otro UUID."],
    ["C3", "c3_borrador.sql (5 × Hamburguesa doble; la tablet ve 9) · c3_ajustar_stock.sql (quedan 3) · "
           "exportar, cargar, semaforo.sql",
     "RECHAZADO: «stock insuficiente, pide 5 y quedan 3»",
     "La tablet no valida stock: el que ve es viejo. El rojo lo da la instantánea nueva. El stock bajó por un "
     "ajuste preparado en el servidor, no por la tablet."],
    ["C4", "c4_borrador.sql (2 × Agua mineral, 1 × Gaseosa) · c4_baja_producto.sql (activo = false) · exportar, "
           "cargar, semaforo.sql · c4_catalogo.sql",
     "RECHAZADO: «Agua mineral 500 ml: dado de baja». El catálogo ya no la muestra; la fila queda con "
     "eliminado = 1",
     "La baja viaja como lápida: si se borrara la fila, la FK del ítem del borrador quedaría huérfana. Un borrador "
     "nuevo ya no puede incluirla (0 ítems insertados)."],
    ["C5", "c5_borrador.sql (Pizza muzzarella y Flan) · exportar y cargar sin cambios · semaforo.sql",
     "SIMULADO_APROBADO: «todo coincide con la instantánea»",
     "Verde = coincide con la instantánea. No crea un pedido ni descuenta stock (ver verificación final)."],
    ["C6", "c6_reenvio.sql (mismo UUID de C5) · semaforo.sql otra vez",
     "«UNIQUE constraint failed: cola_sync.solicitud_uuid»; el UPDATE para forzar PENDIENTE lo frena el trigger; "
     "0 solicitudes evaluadas",
     "El UUID es la clave de idempotencia: no se duplica y repetir la simulación no reevalúa porque sólo toma "
     "PENDIENTE."],
]
h.append(tabla(filas, [10 * mm, 54 * mm, 50 * mm, ANCHO - 114 * mm],
               fondos={(2, 1): AMAR, (2, 2): ROJO, (2, 3): ROJO, (2, 4): VERDE}))
h.append(Spacer(1, 3))
h.append(Paragraph(
    "<b>C6 en un sistema de verdad (parada 8):</b> la protección no puede depender de la tablet. El servidor "
    "guardaría cada <b>solicitud_uuid</b> en una tabla con <b>UNIQUE</b> y lo insertaría en la <b>misma "
    "transacción</b> que crea el pedido (<b>INSERT ... ON CONFLICT DO NOTHING</b>); si el UUID ya estaba, "
    "devuelve el resultado anterior sin volver a vender.", base))
h.append(KeepTogether([
    Paragraph("<b>Semáforo al final de todos los casos</b> (<b>07_caso_c6.txt</b>):", base),
    bloque(sin_columna(tramo("07_caso_c6.txt", "solicitud ", ultima=True), "snapshot_de")),
]))
h.append(Spacer(1, 3))
h.append(KeepTogether([
    Paragraph("<b>PostgreSQL no cambió por la simulación</b> (<b>servidor/verificacion_final.sql</b>, "
              "<b>08_verificacion_final.txt</b>): siguen los 4 pedidos y 6 líneas, y el servidor es idéntico a la "
              "última instantánea, exportada antes de C5 y C6: los verdes no descontaron nada. Los únicos cambios "
              "son los tres preparados a mano (precio del 1, stock del 2, baja del 5).", base),
    bloque(tramo("08_verificacion_final.txt", " pedidos", "== El servidor") + "\n" +
           tramo("08_verificacion_final.txt", " diferencia", "== Stock") + "\n" +
           tramo("08_verificacion_final.txt", " id_producto")),
]))

# ------------------------------------------------------------------ 3.a
h.append(Paragraph("3.a Mapa de la capa de datos", h2))
h.append(tabla([
    ["Motor", "Qué guarda", "Quién manda", "Cómo se actualiza"],
    ["<b>PostgreSQL</b> (U1–U6, U8)", "Catálogo, precios, stock, clientes, pedidos y líneas, usuarios y auditoría",
     "<b>Manda sobre todo.</b> Único lugar donde se crea una venta y se descuenta stock (trigger RN1/RN2 con FOR UPDATE)",
     "Transacciones de la app; respaldo diario (U6)"],
    ["<b>MongoDB</b> (U7)", "Colección <b>pedidos</b>: un documento por pedido con cliente y líneas embebidas",
     "No manda: copia de lectura derivada de PostgreSQL", "Se regenera desde PostgreSQL (export + insertMany)"],
    ["<b>SQLite</b> (U8, tablet)", "<b>producto_cache</b> (copia del catálogo), borradores, ítems y <b>cola_sync</b>",
     "Catálogo: manda PostgreSQL. Borradores: la tablet, hasta que el servidor los evalúa. Estados de la cola: "
     "el semáforo, sobre la instantánea", "Instantánea CSV de <b>v_snapshot_movil</b>; los borradores, el vendedor"],
], [27 * mm, 50 * mm, 58 * mm, ANCHO - 135 * mm]))
h.append(Spacer(1, 2))
h.append(bloque(
    "  PostgreSQL (fuente de verdad) ── export ──► MongoDB pedidos (copia de lectura, U7)\n"
    "        │  v_snapshot_movil ── \\copy CSV ──► SQLite snapshot_servidor ──► producto_cache\n"
    "        ▲                                              semáforo (simula) ◄── cola_sync ◄── borradores\n"
    "        └──── en un sistema real: solicitud con UUID ──► el servidor decide y crea (o no) el pedido"))

# ------------------------------------------------------------------ 3.b
h.append(Paragraph("3.b Plan de mantenimiento (agregado al plan de la Unidad 6)", h2))
h.append(tabla([
    ["Pregunta", "Respuesta"],
    ["¿Qué se respalda y cómo se prueba la restauración?",
     "<b>PostgreSQL</b>: igual que en U6, <b>pg_dump -Fc</b> diario con verificación y simulacro de restauración en "
     "una base aparte (<b>restore_test.sh</b>), ahora con <b>v_snapshot_movil</b> y la migración 002. "
     "<b>Tablet</b>: el archivo <b>foodstore_movil.db</b> se copia con <b>VACUUM INTO</b> al cerrar cada jornada, "
     "porque los borradores PENDIENTE sólo existen ahí; se prueba abriendo la copia y corriendo "
     "<b>PRAGMA integrity_check</b> y <b>PRAGMA foreign_key_check</b>. <b>MongoDB</b> no se respalda: se regenera "
     "desde PostgreSQL."],
    ["Si se restaura un respaldo viejo de PostgreSQL, ¿qué hacen las tablets?",
     "Recargan el catálogo completo con una instantánea nueva antes de vender. <b>cargar_snapshot.sql</b> ya lo "
     "contempla: un producto que el servidor dejó de informar no se borra (lo usan borradores), queda "
     "<b>disponible = 0</b>, y una solicitud con ese producto sale RECHAZADA (<b>11_respaldo_viejo.txt</b>). Las "
     "solicitudes ya evaluadas no se reenvían solas: las ventas reales perdidas (RPO) se reconstruyen desde la "
     "cola, y el UUID evita duplicarlas si el servidor sí las tenía."],
    ["¿Cada cuánto y quién revisa CONFLICTO y RECHAZADO?",
     "<b>CONFLICTO</b>: el vendedor, en el momento, con el cliente (acepta el precio nuevo → solicitud nueva). "
     "<b>RECHAZADO</b>: el encargado del food truck, al cierre de cada jornada de feria, con la consulta de "
     "<b>cola_sync</b> por estado; decide si se ofrece un reemplazo o se anula el borrador. Lo PENDIENTE de más de "
     "un día se revisa antes de la jornada siguiente."],
], [42 * mm, ANCHO - 42 * mm]))

# ------------------------------------------------------------------ 3.c
h.append(Paragraph("3.c Code review con IA", h2))
h.append(Paragraph(
    "Revisión de los scripts de la cursada hecha con Claude en el rol del agente Plan de OpenCode (ver DUIA). "
    "Cada hallazgo se comprobó en una base descartable, antes y después de corregir "
    "(<b>revision/verificar_hallazgos.sh</b> → <b>09_code_review.txt</b>; tablet → <b>10</b>, <b>11</b> y <b>13</b>). "
    "Las pruebas de 001 y de los programables dan la misma salida antes y después de las correcciones.", base))
h.append(tabla([
    ["#", "Unidad · script", "Hallazgo", "Decisión", "Motivo y comprobación"],
    ["H1", "TPI · programables",
     "<b>sp_registrar_pedido</b> saltea en silencio un id_producto inexistente: el INSERT ... SELECT sin filas no es error",
     "<b>Corregido</b>", "Carrito de 2 productos (uno es 999) → pedido con 1 línea. Ahora <b>IF NOT FOUND THEN RAISE</b> y "
     "no se crea el pedido."],
    ["H2", "U2 · migraciones/001",
     "El trigger RN1/RN2 sólo corre en INSERT: un UPDATE de la línea cambia cantidad sin tocar stock o la pasa a un "
     "producto de baja", "<b>Corregido</b>",
     "UPDATE cantidad 2 → 40: stock del flan sigue en 3. Migración <b>002</b> bloquea el UPDATE; la cancelación "
     "con CASCADE sigue andando (<b>12_pruebas_002.txt</b>)."],
    ["H3", "U1 · schema.sql", "Falta un índice sobre <b>pedido_producto(id_pedido)</b> para los joins y el CASCADE",
     "<b>Descartado</b>", "La PK <b>(id_pedido, id_producto)</b> lo tiene como columna líder: EXPLAIN usa "
     "<b>pedido_producto_pkey</b>. Otro índice sólo encarecería las escrituras."],
    ["H4", "U2 · lab/reset.sql", "Dice «solo en copia_trabajo» pero corre en cualquier base",
     "<b>Corregido</b>", "Corrido sobre otra base: stock total 124 → 133. Guarda con <b>DO</b> + "
     "<b>ON_ERROR_STOP</b> (sin esto último psql seguía tras el error)."],
    ["H5", "U2 · lab/reset.sql", "UPDATE de producto sin WHERE, contra la regla de AGENTS.md", "<b>Descartado</b>",
     "Es el reset deliberado de los 7 productos del laboratorio; la regla apunta a UPDATE accidentales. Con H4 sólo "
     "puede correr en copia_trabajo."],
    ["L1", "U8 · semaforo.sql", "Evalúa cada solicitud por separado: dos que juntas superan el stock salen verdes",
     "<b>Aceptado</b>", "Limitación documentada. 2 + 2 flanes con stock 3 → dos verdes; en el servidor el segundo "
     "<b>sp_registrar_pedido</b> falla por RN2. Reservar stock en la tablet sería decidir por el servidor."],
    ["P1", "U8 · scripts de movil/", "<b>PRAGMA foreign_keys</b> es por conexión: un script que no lo "
     "activa inserta ítems de productos inexistentes", "<b>Aceptado</b>",
     "Sin el PRAGMA, el ítem con producto 999 se inserta; <b>foreign_key_check</b> lo marca. Todos los scripts "
     "empiezan con el PRAGMA (<b>13_pragma_por_conexion.txt</b>)."],
], [8 * mm, 27 * mm, 45 * mm, 21 * mm, ANCHO - 101 * mm],
    fondos={(3, 1): VERDE, (3, 2): VERDE, (3, 3): ROJO, (3, 4): VERDE, (3, 5): ROJO, (3, 6): AMAR, (3, 7): AMAR}))
h.append(Paragraph("Desarrollo de tres hallazgos", h2))
h.append(Paragraph(
    "<b>H1 (TPI, corregido).</b> En <b>revision_antes</b>, dentro de <b>BEGIN ... ROLLBACK</b>, "
    "<b>CALL sp_registrar_pedido(1, 'EFECTIVO', '[{\"id_producto\": 4, ...}, {\"id_producto\": 999, ...}]')</b> "
    "devolvió el pedido 5 con <b>1 línea registrada de 2 pedidas</b>: el cliente pagaría por algo que nunca se "
    "registró. Es el procedimiento que recibiría las solicitudes de la tablet, así que el error también afectaba a "
    "U8. Con la corrección, el mismo CALL falla con «El producto 999 no existe» y el pedido no se crea; un carrito "
    "válido sigue funcionando.", base))
h.append(Paragraph(
    "<b>H2 (U2, corregido).</b> Con <b>UPDATE pedido_producto SET cantidad = 40</b> sobre la línea del flan, la "
    "cantidad pasó a 40 y el stock siguió en 3: RN2 no se cumple. También se pudo pasar una línea al producto 7, "
    "dado de baja (RN1). La migración <b>002</b> agrega un trigger <b>BEFORE UPDATE</b> que rechaza el cambio: una "
    "línea se corrige cancelando el pedido (<b>sp_cancelar_pedido</b> repone stock) y registrándolo de nuevo. No se "
    "bloqueó DELETE porque el CASCADE de <b>pedido</b> lo necesita; la prueba 002 muestra que cancelar sigue "
    "funcionando y repone el stock (3 → 5).", base))
h.append(Paragraph(
    "<b>H3 (U1, descartado con fundamento).</b> La sugerencia de indexar <b>pedido_producto(id_pedido)</b> suena "
    "razonable porque es la FK que se recorre en cada join y en el CASCADE. Pero un B-tree sobre "
    "<b>(id_pedido, id_producto)</b> sirve para buscar por su primera columna: con <b>enable_seqscan = off</b>, el "
    "EXPLAIN de <b>WHERE id_pedido = 3</b> usa <b>Bitmap Index Scan on pedido_producto_pkey</b>. Un índice extra "
    "duplicaría la PK y sumaría costo a cada INSERT, como se midió en U3 con el índice descartado sobre "
    "<b>forma_pago</b>.", base))


def pie(canvas, doc):
    canvas.saveState()
    canvas.setFont("DV", 7)
    canvas.setFillColor(colors.HexColor("#808080"))
    canvas.drawString(15 * mm, 9 * mm, "Bases de Datos II · TP N.º 8 · Food Store")
    canvas.drawRightString(A4[0] - 15 * mm, 9 * mm, f"Página {doc.page}")
    canvas.restoreState()


doc = SimpleDocTemplate(str(RAIZ / "docs" / "informe.pdf"), pagesize=A4,
                        leftMargin=15 * mm, rightMargin=15 * mm, topMargin=13 * mm, bottomMargin=15 * mm,
                        title="TP 8 — Food Store en la feria", author="Ignacio Martín Rodríguez")
doc.build(h, onFirstPage=pie, onLaterPages=pie)
print("informe.pdf generado")
