#!/usr/bin/env python3
"""FairFlow demo controller (Round 1 proof of concept).
Watches round-trip time through the shaped path, detects bufferbloat, and re-shapes CAKE by itself.
Run inside the 'home' network namespace. Bounded (MINBW..MAXBW), observable (CSV log), reversible (restores SAFE on exit)."""
import subprocess, sys, time, re, statistics, resource

DEV = "h-i"; TARGET = "10.0.2.2"
MAXBW = 95.0; MINBW = 2.0; SAFE = 95.0
BAD_MS = 15.0; GOOD_MS = 5.0; BAD_N = 2; GOOD_N = 15
DECAY = 0.7; GROW = 1.08; COOLDOWN = 0.8; FALL_MS = 2.0

def apply(bw):
    r = subprocess.run(["tc", "qdisc", "replace", "dev", DEV, "root", "cake", "bandwidth", f"{bw:.2f}mbit"],
                       capture_output=True, text=True)
    return r.returncode == 0

class Ctl:
    def __init__(self):
        self.bw = MAXBW; self.base = None; self.warm = []; self.bad = 0; self.good = 0; self.cool = 0.0; self.hist = []
    def step(self, ts, rtt):
        if self.base is None:
            self.warm.append(rtt)
            if len(self.warm) >= 15: self.base = statistics.median(self.warm)
            return None, self.bw
        self.hist.append(rtt); self.hist = self.hist[-3:]
        if ts < self.cool: return None, self.bw
        # queue already draining after a cut? then wait instead of cutting again (avoids overshoot)
        draining = len(self.hist) == 3 and rtt < self.hist[0] - FALL_MS
        if draining: self.bad = 0; self.good = 0; return None, self.bw
        if rtt > self.base + BAD_MS: self.bad += 1; self.good = 0
        elif rtt < self.base + GOOD_MS: self.good += 1; self.bad = 0
        else: self.bad = 0
        if self.bad >= BAD_N:
            self.bw = max(MINBW, self.bw * DECAY); self.bad = 0; self.good = 0; self.cool = ts + COOLDOWN
            return "decrease", self.bw
        if self.good >= GOOD_N and self.bw < MAXBW:
            self.bw = min(MAXBW, self.bw * GROW); self.good = 0
            return "increase", self.bw
        return None, self.bw

def main():
    logfile, duration = sys.argv[1], float(sys.argv[2])
    ctl = Ctl(); t0 = time.time()
    log = open(logfile, "w"); log.write("ts,event,bw_mbit\n")
    log.write(f"{t0:.3f},start,{ctl.bw:.2f}\n")
    p = subprocess.Popen(["ping", "-D", "-i", "0.2", TARGET], stdout=subprocess.PIPE, text=True)
    pat = re.compile(r"\[(\d+\.\d+)\].*time=([\d.]+) ms")
    try:
        for line in p.stdout:
            m = pat.search(line)
            if m:
                ts, rtt = float(m.group(1)), float(m.group(2))
                ev, bw = ctl.step(ts, rtt)
                if ev:
                    ok = apply(bw)
                    log.write(f"{ts:.3f},{ev if ok else 'apply_failed'},{bw:.2f}\n"); log.flush()
            if time.time() - t0 > duration: break
    finally:
        p.terminate(); p.wait()
        apply(SAFE)                                   # rollback to a known safe state
        ru = resource.getrusage(resource.RUSAGE_SELF); rc = resource.getrusage(resource.RUSAGE_CHILDREN)
        cpu = ru.ru_utime + ru.ru_stime + rc.ru_utime + rc.ru_stime
        log.write(f"{time.time():.3f},rollback_to_safe,{SAFE:.2f}\n")
        log.write(f"{time.time():.3f},cpu_percent,{100*cpu/max(time.time()-t0,1e-9):.2f}\n")
        log.close()

if __name__ == "__main__":
    main()
