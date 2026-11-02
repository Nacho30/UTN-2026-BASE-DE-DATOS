"""Sustituto mínimo de `sqlite3 BASE < SCRIPT` para entornos sin el CLI.

Uso:  python3 sqlite_cli.py foodstore_movil.db script.sql

Se escribió porque el entorno donde se generó la evidencia no tenía el
CLI de sqlite3 y no se podía instalar. Los scripts del TP NO dependen de
esto: corren tal cual con el sqlite3 oficial o en DB Browser for SQLite.

Imita lo que usan los scripts:
  * sentencias SQL separadas por ';' (sqlite3.complete_statement),
    en modo autocommit para que BEGIN / COMMIT / ROLLBACK del script
    manden (isolation_level=None);
  * igual que el CLI sin -bail, un error se informa y se sigue con la
    sentencia siguiente;
  * .print TEXTO, .headers, .mode (ignorados: la salida es siempre en
    columnas con encabezado) e .import --csv --skip 1 ARCHIVO TABLA
    (como el CLI, inserta los campos como texto y la afinidad de la
    columna los convierte).
"""
import csv
import shlex
import sqlite3
import sys


def mostrar(cur):
    filas = cur.fetchall()
    if not filas:
        return
    cab = [d[0] for d in cur.description]
    txt = [["" if v is None else str(v) for v in f] for f in filas]
    anchos = [max(len(c), *(len(f[i]) for f in txt)) for i, c in enumerate(cab)]
    print("  ".join(c.ljust(a) for c, a in zip(cab, anchos)).rstrip())
    print("  ".join("-" * a for a in anchos))
    for f in txt:
        print("  ".join(v.ljust(a) for v, a in zip(f, anchos)).rstrip())


def importar(con, args, nlinea):
    partes = shlex.split(args)
    opciones = [p for p in partes if p.startswith("--")]
    resto = [p for p in partes if not p.startswith("--")]
    skip = 0
    if "--skip" in opciones:
        skip = int(resto.pop(0))
    archivo, tabla = resto
    ncols = len(con.execute(f'PRAGMA table_info("{tabla}")').fetchall())
    with open(archivo, newline="", encoding="utf-8") as f:
        filas = list(csv.reader(f))[skip:]
    insertadas = 0
    for n, fila in enumerate(filas, start=skip + 1):
        try:
            con.execute(f'INSERT INTO "{tabla}" VALUES ({",".join("?" * ncols)})', fila)
            insertadas += 1
        except sqlite3.Error as e:
            print(f"{archivo}:{n}: INSERT failed: {e}")
    return insertadas


def main(base, script):
    con = sqlite3.connect(base, isolation_level=None)
    buf, inicio = "", 0
    with open(script, encoding="utf-8") as f:
        lineas = f.read().splitlines()
    for n, linea in enumerate(lineas, start=1):
        if not buf.strip():
            s = linea.strip()
            if not s or s.startswith("--"):
                continue
            if s.startswith("."):
                cmd, _, args = s.partition(" ")
                if cmd == ".print":
                    print(args.strip().strip("'\""))
                elif cmd == ".import":
                    importar(con, args, n)
                elif cmd in (".headers", ".mode", ".bail"):
                    pass
                else:
                    print(f"(dot-command no soportado por este sustituto: {cmd})")
                continue
            inicio = n
        buf += linea + "\n"
        if sqlite3.complete_statement(buf):
            try:
                cur = con.execute(buf)
                if cur.description:
                    mostrar(cur)
            except sqlite3.Error as e:
                print(f"Runtime error near line {inicio}: {e}")
            buf = ""
    con.close()


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
