#!/usr/bin/env python3
"""Anonimiza un fragmento de log de PostgreSQL antes de compartirlo con una IA.

Criterio: el MISMO que usuario_anon (sql/usuario_anon.sql). Cada usuario
se reemplaza por un seudónimo determinista
    U-<primeros 8 hex de md5(ANON_SALT || id)>
de modo que el mismo usuario recibe siempre el mismo seudónimo (se
conservan las correlaciones del log), pero sin la sal (que no está en el
repo) no se puede volver al id ni al email.

Uso: ANON_SALT=... python3 scripts/anonimizar_log.py entrada.log salida.txt
"""
import hashlib
import os
import re
import sys

SAL = os.environ.get("ANON_SALT")
if not SAL:
    sys.exit("Falta ANON_SALT en el entorno (ver .env.example)")


def seudonimo(usuario_id: str) -> str:
    return "U-" + hashlib.md5((SAL + usuario_id).encode()).hexdigest()[:8]


ips: dict[str, str] = {}


def ip_sintetica(m: re.Match) -> str:
    ip = m.group(0)
    ips.setdefault(ip, f"ip-{len(ips) + 1:02d}")
    return ips[ip]


REGLAS = [
    # identificadores de usuario de la aplicación
    # (se conserva el nombre de la columna; sólo cambia el valor)
    (re.compile(r"(usuario_id\s*=\s*)(\d+)"), lambda m: m.group(1) + seudonimo(m.group(2))),
    (re.compile(r"(\bid\s*=\s*)(\d+)"), lambda m: m.group(1) + seudonimo(m.group(2))),
    (re.compile(r"(\bid\s+IN\s*\()([\d,\s]+)(\))", re.I),
     lambda m: m.group(1) + ", ".join(seudonimo(x.strip()) for x in m.group(2).split(",")) + m.group(3)),
    (re.compile(r"(fn_resetear_password\()(\d+)"), lambda m: m.group(1) + seudonimo(m.group(2))),
    # emails y hashes de email
    (re.compile(r"[\w.+-]+@[\w-]+(\.[\w-]+)+"), lambda m: "<email>"),
    (re.compile(r"email_hash=\w+"), lambda m: "email_hash=<redactado>"),
    # literales de texto en sentencias (pueden ser contraseñas o datos personales)
    (re.compile(r"'(?:[^']|'')*'"), lambda m: "'<redactado>'"),
    # direcciones IP → tokens estables
    (re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}\b"), ip_sintetica),
    # rutas del servidor
    (re.compile(r"/[\w./-]*pg_hba\.conf"), lambda m: "<PGDATA>/pg_hba.conf"),
]


def anonimizar(linea: str) -> str:
    for patron, reemplazo in REGLAS:
        linea = patron.sub(reemplazo, linea)
    return linea


def main(entrada: str, salida: str) -> None:
    with open(entrada, encoding="utf-8") as f:
        lineas = [anonimizar(l) for l in f]
    with open(salida, "w", encoding="utf-8") as f:
        f.writelines(lineas)

    # Control: no debe quedar ningún email, IP ni id de usuario en claro
    texto = "".join(lineas)
    restos = re.findall(r"@\w|\b\d{1,3}(?:\.\d{1,3}){3}\b|usuario_id\s*=\s*\d|\bid\s*=\s*\d|\bid\s+IN\s*\(\s*\d"
                        r"|fn_resetear_password\(\d", texto, re.I)
    print(f"{len(lineas)} líneas anonimizadas → {salida}; "
          f"IPs mapeadas: {ips}; restos sin anonimizar: {len(restos)}")
    if restos:
        sys.exit(f"ERROR: quedaron datos en claro: {restos[:5]}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
