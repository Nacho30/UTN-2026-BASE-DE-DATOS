# Laboratorio TP2 Parte 2 — Food Store. Abre dos (o tres) procesos psql y les envía
# los comandos en el orden exacto de la columna T del informe.
import json, subprocess, time, os
from harness import Lab
HERE = os.path.dirname(os.path.abspath(__file__))
def reset():
    subprocess.run(["psql","-X","-q","-h","/tmp","-U","postgres","-d","copia_trabajo","-f",os.path.join(HERE,"reset.sql")],check=True)
R={}
def exp(key, fn):
    reset(); L=Lab(); fn(L); L.close(); time.sleep(0.3); R[key]=L.steps

Q_PRECIO="SELECT id_producto, nombre, precio FROM producto WHERE id_producto = 1;"
def e1(level):
    def f(L):
        L.run("A","BEGIN;"); L.run("A",f"SET TRANSACTION ISOLATION LEVEL {level};")
        L.run("A",Q_PRECIO)
        L.run("B","UPDATE producto SET precio = 9000 WHERE id_producto = 1;  -- autocommit")
        L.run("A",Q_PRECIO)
        L.run("A","COMMIT;")
        L.run("A",Q_PRECIO)
    return f
exp("e1_rc", e1("READ COMMITTED")); exp("e1_rr", e1("REPEATABLE READ"))

Q_VENTAS="SELECT count(*) AS lineas, sum(cantidad) AS unidades FROM pedido_producto WHERE id_producto = 4;"
def e2(level):
    def f(L):
        L.run("A","BEGIN;"); L.run("A",f"SET TRANSACTION ISOLATION LEVEL {level};")
        L.run("A",Q_VENTAS)
        L.run("B","INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES (2, 4, 3, 2500);  -- autocommit")
        L.run("A",Q_VENTAS)
        L.run("A","COMMIT;")
        L.run("A",Q_VENTAS)
    return f
exp("e2_rc", e2("READ COMMITTED")); exp("e2_rr", e2("REPEATABLE READ")); exp("e2_ser", e2("SERIALIZABLE"))

DIAG=("SELECT pid, pg_blocking_pids(pid) AS bloqueado_por, wait_event_type, wait_event, state "
      "FROM pg_stat_activity WHERE datname = 'copia_trabajo' AND pid <> pg_backend_pid() ORDER BY pid;")
Q_LOCK="SELECT id_producto, nombre, stock FROM producto WHERE id_producto = 2 FOR UPDATE;"
def e3(level_b, nowait=False):
    def f(L):
        L.run("A","SELECT pg_backend_pid();"); L.run("B","SELECT pg_backend_pid();")
        L.run("A","BEGIN;")
        L.run("A",Q_LOCK)
        L.run("B","BEGIN;")
        if level_b:
            L.run("B",f"SET TRANSACTION ISOLATION LEVEL {level_b};")
            L.run("B","SELECT id_producto, stock FROM producto WHERE id_producto = 1;  -- toma el snapshot de la transacción")
        if nowait:
            L.run("B",Q_LOCK.replace("FOR UPDATE;","FOR UPDATE NOWAIT;"))
            L.run("B","\\echo :LAST_ERROR_SQLSTATE")
            L.run("B","ROLLBACK;"); L.run("A","ROLLBACK;"); return
        L.run("B",Q_LOCK, expect_block=True)
        L.run("C",DIAG)
        L.run("A","UPDATE producto SET stock = stock - 1 WHERE id_producto = 2;")
        L.run("A","COMMIT;")
        L.resume("B")
        if level_b: L.run("B","\\echo :LAST_ERROR_SQLSTATE")
        L.run("B","COMMIT;" if not level_b else "ROLLBACK;")
    return f
exp("e3_rc", e3(None)); exp("e3_rr", e3("REPEATABLE READ")); exp("e3_nowait", e3(None, nowait=True))

LIN="INSERT INTO pedido_producto (id_pedido, id_producto, cantidad, precio_unitario) VALUES ({}, {}, 1, {});"
PR={1:8500, 2:11000}
def e4(level, ordered=False):
    def f(L):
        L.run("A","BEGIN;"); L.run("B","BEGIN;")
        if level:
            L.run("A",f"SET TRANSACTION ISOLATION LEVEL {level};"); L.run("B",f"SET TRANSACTION ISOLATION LEVEL {level};")
        orderA=[1,2]; orderB=[1,2] if ordered else [2,1]
        L.run("A",LIN.format(2,orderA[0],PR[orderA[0]]))
        L.run("B",LIN.format(4,orderB[0],PR[orderB[0]]), expect_block=ordered)
        if not ordered:
            L.run("A",LIN.format(2,orderA[1],PR[orderA[1]]), expect_block=True)
            L.run("B",LIN.format(4,orderB[1],PR[orderB[1]]), expect_block=True)
            time.sleep(1.5)
            for n in list(L.blocked): L.resume(n)
            L.run("B","\\echo :LAST_ERROR_SQLSTATE")
            L.run("A","COMMIT;"); L.run("B","COMMIT;")
        else:
            L.run("A",LIN.format(2,orderA[1],PR[orderA[1]]))
            L.run("A","COMMIT;")
            L.resume("B")
            L.run("B",LIN.format(4,orderB[1],PR[orderB[1]]))
            L.run("B","COMMIT;")
            L.run("B","SELECT id_producto, stock FROM producto WHERE id_producto IN (1, 2) ORDER BY id_producto;")
    return f
exp("e4_rc", e4(None)); exp("e4_ser", e4("SERIALIZABLE")); exp("e4_orden", e4(None, ordered=True))
reset()
json.dump(R, open(os.path.join(HERE,"resultados.json"),"w"), ensure_ascii=False, indent=1)
for k,steps in R.items():
    print("\n#####", k)
    for s in steps:
        print(f"[{s['t']}] {s['s']}> " + (s['cmd'] if s['cmd'] else f"(se destraba el paso {s['resumed_from']})"))
        [print("    "+o) for o in s['out']]
