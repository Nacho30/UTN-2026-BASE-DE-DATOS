#!/usr/bin/env python3
"""Reenviador TCP para el simulacro de la Parte C.

Escucha en 127.0.0.1:6543 y reenvía a 127.0.0.1:5432 usando 127.0.0.2
como dirección de ORIGEN. Así el servidor ve la conexión del "atacante"
como proveniente de otro equipo (host=127.0.0.2), aunque todo corra en
la misma máquina de desarrollo. No toca la red externa.
"""
import socket
import threading

ESCUCHA = ("127.0.0.1", 6543)
DESTINO = ("127.0.0.1", 5432)
ORIGEN = ("127.0.0.2", 0)


def bombear(a, b):
    try:
        while (datos := a.recv(65536)):
            b.sendall(datos)
    except OSError:
        pass
    finally:
        for s in (a, b):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def atender(cliente):
    servidor = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    servidor.bind(ORIGEN)
    servidor.connect(DESTINO)
    threading.Thread(target=bombear, args=(cliente, servidor), daemon=True).start()
    threading.Thread(target=bombear, args=(servidor, cliente), daemon=True).start()


def main():
    oyente = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    oyente.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    oyente.bind(ESCUCHA)
    oyente.listen()
    while True:
        cliente, _ = oyente.accept()
        atender(cliente)


if __name__ == "__main__":
    main()
