"""Genera docs/informe_u6.pdf (una página) con los valores medidos en el simulacro.

Uso: python3 docs/generar_informe.py   (desde food-store-tp-u6/)
"""
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

pdfmetrics.registerFont(TTFont("DV", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("DVB", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"))
pdfmetrics.registerFontFamily("DV", normal="DV", bold="DVB")

AZUL = colors.HexColor("#1F4E79")
GRIS = colors.HexColor("#F2F2F2")

base = ParagraphStyle("base", fontName="DV", fontSize=7.9, leading=9.9, alignment=TA_LEFT)
celda = ParagraphStyle("celda", parent=base, fontSize=7.6, leading=9.3)
cab = ParagraphStyle("cab", parent=celda, fontName="DVB", textColor=colors.white)
h2 = ParagraphStyle("h2", parent=base, fontName="DVB", fontSize=9.2, leading=11, textColor=AZUL,
                    spaceBefore=4.5, spaceAfter=1.5)
titulo = ParagraphStyle("titulo", parent=base, fontName="DVB", fontSize=12.5, leading=15, textColor=AZUL)
sub = ParagraphStyle("sub", parent=base, fontSize=7.6, textColor=colors.HexColor("#595959"))


def tabla(filas, anchos):
    datos = [[Paragraph(c, cab if i == 0 else celda) for c in f] for i, f in enumerate(filas)]
    t = Table(datos, colWidths=anchos)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), AZUL),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, GRIS]),
        ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#BFBFBF")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 1.6), ("BOTTOMPADDING", (0, 0), (-1, -1), 1.6),
        ("LEFTPADDING", (0, 0), (-1, -1), 3), ("RIGHTPADDING", (0, 0), (-1, -1), 3),
    ]))
    return t


ANCHO = A4[0] - 30 * mm
h = []
h.append(Paragraph("Informe post-incidente — Simulacro de restauración de Food Store", titulo))
h.append(Paragraph("TP Unidad 6 · Bases de Datos II · UTN — Ignacio Martín Rodríguez — 20/10/2026 · "
                   "PostgreSQL 16.15 · rama <b>tp-unidad-6</b>, carpeta <b>food-store-tp-u6/</b>", sub))
h.append(Spacer(1, 3))

h.append(Paragraph("1. Respaldo utilizado y tiempos del simulacro", h2))
h.append(tabla([
    ["Dato", "Valor", "Evidencia"],
    ["Respaldo", "<b>foodstore_20261020_084525.dump</b> — tomado el <b>20/10/2026 08:45:25 (-03)</b>; "
     "formato custom; 2.800.370 bytes; SHA-256 83fcb30a…6ac90fb; pg_dump en 0,6 s. "
     "Conteos y sumas de control tomados en el mismo snapshot (pg_export_snapshot).",
     "01_backup_ok.txt"],
    ["Base de la prueba", "Restaurada en <b>foodstore_restore_test</b>. <b>foodstore</b> no se modificó "
     "(147.044 pedidos antes y después).", "05, 06"],
    ["Cronómetro", "Inicio 08:48:58,926 (antes de createdb) → fin 08:49:00,712 (validaciones OK). "
     "createdb 76 ms · pg_restore 1.027 ms · ANALYZE 231 ms · validaciones 433 ms. "
     "<b>Total de restauración y validación: 1,8 s</b> (1,9 s contando la verificación previa del SHA-256).",
     "05_simulacro_restore.log"],
], [24 * mm, ANCHO - 52 * mm, 28 * mm]))

h.append(Paragraph("2. RPO y RTO: previstos y observados", h2))
h.append(tabla([
    ["", "Qué mide", "Previsto (SPEC_U6)", "Observado"],
    ["<b>RPO</b>", "Cuántos datos se pueden perder: el tiempo entre el último respaldo y el incidente.",
     "≤ 24 h (respaldo diario a las 03:10)",
     "<b>3,5 min</b> (antigüedad del respaldo al iniciar). Se perderían <b>40 pedidos nuevos y 3.000 "
     "cancelaciones</b> hechas después del respaldo. El 3,5 min es del laboratorio: con el plan diario, "
     "el peor caso real es de casi 24 h de ventas."],
    ["<b>RTO</b>", "Cuánto se tarda en volver a tener la base operativa y validada.",
     "≤ 15 min", "<b>1,8 s</b> (mediana de 5 repeticiones: 1,87 s). Muy por debajo del objetivo para 2,7 MB "
     "comprimidos; crece con el tamaño de la base."],
], [12 * mm, 52 * mm, 33 * mm, ANCHO - 97 * mm]))

h.append(Paragraph("3. Resultado de las validaciones", h2))
h.append(tabla([
    ["Control", "Resultado"],
    ["Filas por tabla contra el respaldo", "categoria 15 · cliente 5.003 · producto 307 · pedido 150.004 · "
     "pedido_producto 375.006 — <b>5/5 iguales</b>"],
    ["Restricciones lógicas", "Productos con precio o stock negativo: <b>0</b> · líneas con cantidad ≤ 0 o precio < 0: "
     "<b>0</b> · líneas sin pedido: <b>0</b>"],
    ["Sumas de control", "Stock total, importe total de líneas e id máximo de pedido: <b>3/3 iguales</b>. "
     "Los 2 disparadores de negocio (RN1–RN3) se restauraron."],
    ["Pruebas de falla", "Respaldo: servidor caído, sin credenciales y pg_dump fallido → código 1, sin .dump (3/3). "
     "Restauración: sin --recrear, respaldo dañado y truncado → código 1 (3/3)."],
], [44 * mm, ANCHO - 44 * mm]))

h.append(Paragraph("4. Problemas reales encontrados", h2))
h.append(Paragraph(
    "<b>a)</b> La consulta de validación de la consigna usa <b>detalle_pedido</b>, que no existe en el esquema de Food "
    "Store: corrida tal cual da <i>relation \"detalle_pedido\" does not exist</i> (06_validacion_consigna.txt). "
    "Se adaptó a <b>pedido_producto</b>. "
    "<b>b)</b> El comando de referencia de pg_dump fue rechazado por la regla final <i>reject</i> de pg_hba.conf "
    "agregada en la U5 (00_primer_intento_pg_dump.txt). Se habilitó SCRAM por TCP sólo para postgres y las tres "
    "bases del TP, con la contraseña en ~/.pgpass. "
    "<b>c)</b> En la primera prueba, backup_foodstore.sh quedó colgado al cerrar la sesión del snapshot "
    "(faltaba \\q) y, al interrumpirlo, dejó un .dump.parcial: se corrigió y se agregó una limpieza con trap.", base))

h.append(Paragraph("5. Mejora para la próxima ejecución", h2))
h.append(Paragraph(
    "<b>Tiempo:</b> restaurar con <b>pg_restore --jobs</b> igual a la cantidad de CPU. Medido con 5 corridas "
    "alternadas en 2 CPU: la mediana de pg_restore bajó de 1.066 a 831 ms (−22 %) y la del RTO de 1,87 a 1,64 s "
    "(−13 %) (08_mejora_jobs.txt). La ganancia crece con el tamaño de la base. "
    "<b>Riesgo:</b> el punto débil es el RPO de hasta 24 h. Se propone activar el archivado de WAL "
    "(recuperación a un punto en el tiempo) o, como mínimo, un segundo respaldo al cierre del turno noche.", base))

h.append(Paragraph("6. Trabajo asistido por IA y cómo se verificó", h2))
h.append(Paragraph(
    "Los scripts y el SQL los generó un asistente de IA (<b>Claude</b>, usado en lugar de OpenCode) a partir de "
    "SPEC_U6.md y de las reglas de AGENTS.md. Nada se aceptó sin ejecutarlo contra la base: cada script se corrió a "
    "mano y se leyó su salida. Además, se escribieron pruebas de falla para el respaldo y la restauración, y se "
    "compararon los conteos contra un snapshot. Las pruebas detectaron los errores del punto 4c. Se comprobó también "
    "que la contraseña no aparece en el log del servidor ni en el repositorio. "
    "VACUUM FULL quedó excluido: maintenance.sql sólo ejecutó ANALYZE categoria, porque nunca había tenido estadísticas; "
    "ninguna tabla superaba el umbral de VACUUM.", base))

doc = SimpleDocTemplate("docs/informe_u6.pdf", pagesize=A4, leftMargin=15 * mm, rightMargin=15 * mm,
                        topMargin=12 * mm, bottomMargin=10 * mm,
                        title="Informe post-incidente TP U6 Food Store", author="Ignacio Martín Rodríguez")
doc.build(h)
