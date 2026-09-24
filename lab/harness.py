import subprocess, threading, queue, time, json, sys
MARK = "__FIN__"
class Session:
    def __init__(self, name):
        self.name = name
        self.p = subprocess.Popen(["psql","-X","-h","/tmp","-U","postgres","-d","copia_trabajo","-P","pager=off"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        self.q = queue.Queue()
        threading.Thread(target=self._rd, daemon=True).start()
        self.pending = None
    def _rd(self):
        for line in self.p.stdout: self.q.put(line.rstrip("\n"))
    def send(self, cmd, timeout=5):
        self.p.stdin.write(cmd + "\n\\echo " + MARK + "\n"); self.p.stdin.flush()
        return self.collect(timeout)
    def collect(self, timeout):
        out = []; end = time.time()+timeout
        while True:
            try: l = self.q.get(timeout=max(0.01, end-time.time()))
            except queue.Empty: return out, False
            if l == MARK: return out, True
            out.append(l)
    def close(self):
        self.p.stdin.write("\\q\n"); self.p.stdin.flush()

class Lab:
    def __init__(self): self.steps=[]; self.s={}; self.blocked={}
    def sess(self, n):
        if n not in self.s: self.s[n]=Session(n)
        return self.s[n]
    def run(self, n, cmd, expect_block=False, note=None):
        t0=time.time()
        out, done = self.sess(n).send(cmd, timeout=(2.5 if expect_block else 15))
        st={"t":len(self.steps)+1,"s":n,"cmd":cmd,"out":out,"done":done,"note":note}
        if not done:
            st["out"] = out + ["-- (la sesión queda BLOQUEADA, sin devolver resultado)"]
            self.blocked[n]=st
        self.steps.append(st); return st
    def resume(self, n, note=None):
        st0=self.blocked.pop(n)
        out, done = self.sess(n).collect(15)
        st={"t":len(self.steps)+1,"s":n,"cmd":None,"resumed_from":st0["t"],"out":out,"done":done,"note":note}
        self.steps.append(st); return st
    def close(self):
        for x in self.s.values(): x.close()
