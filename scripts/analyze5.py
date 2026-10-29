import glob, re, json, statistics as st
def pings(f):
    out = []
    for line in open(f):
        m = re.search(r"\[(\d+\.\d+)\].*time=([\d.]+) ms", line)
        if m: out.append((float(m.group(1)), float(m.group(2))))
    return out
def conv_time(p, drop):
    seen = False
    for i, (t, v) in enumerate(p):
        if t < drop: continue
        if v > 15: seen = True
        w = p[i:i+5]
        if seen and len(w) == 5 and all(x[1] < 5 for x in w): return t - drop
    return None if seen else 0.0
def events(f):
    ev = []
    for line in list(open(f))[1:]:
        ts, e, v = line.strip().split(",")
        ev.append((float(ts), e, float(v)))
    return ev
R = {m: {k: [] for k in ["b", "w1", "w2", "w3", "worst", "conv", "det", "n", "lo", "hi", "tp", "cpu"]} for m in ("static", "auto")}
for m in ("static", "auto"):
    for f in sorted(glob.glob(f"res5/{m}_*.ping")):
        base = f[:-5]
        drop = float(open(base + ".drop").read()); p = pings(f); r = R[m]
        win = lambda a, b: [v for t, v in p if a <= t - drop < b]
        for k, (a, b) in zip(["b", "w1", "w2", "w3"], [(-99, 0), (0, 2), (2, 10), (10, 99)]):
            if win(a, b): r[k].append(st.mean(win(a, b)))
        r["worst"].append(max(win(0, 99)))
        c = conv_time(p, drop); r["conv"].append(c)
        try:
            d = json.load(open(base + ".json")); t0 = d["start"]["timestamp"]["timesecs"]
            tp = [i["sum"]["bits_per_second"] / 1e6 for i in d["intervals"] if t0 + i["sum"]["start"] >= drop + 10]
            if tp: r["tp"].append(st.mean(tp))
        except Exception: pass
        if m == "auto":
            ev = events(base + ".log")
            ch = [e for e in ev if e[1] in ("decrease", "increase")]
            dec = [e for e in ch if e[1] == "decrease" and e[0] >= drop]
            if dec: r["det"].append(dec[0][0] - drop)
            r["n"].append(len([e for e in ch if e[0] >= drop]))
            late = [e[2] for e in ch if e[0] >= drop + 10]
            if ch: r["lo"].append(min(late) if late else ch[-1][2]); r["hi"].append(max(late) if late else ch[-1][2])
            cp = [e[2] for e in ev if e[1] == "cpu_percent"]
            if cp: r["cpu"].append(cp[0])
def f(v, nd=1):
    v = [x for x in v if x is not None]
    if not v: return "never"
    return f"{st.mean(v):.{nd}f}" + (f"+/-{st.stdev(v):.{nd}f}" if len(v) > 1 else "")
def row(name, key, nd=1, only_auto=False):
    s = "n/a" if only_auto else f(R["static"][key], nd)
    print(f"{name:<40}{s:>20}{f(R['auto'][key], nd):>20}")
print(f"\n{'Metric':<40}{'static (no controller)':>20}{'auto (controller)':>20}")
row("Delay before drop (ms)", "b"); row("Delay 0-2 s after drop (ms)", "w1")
row("Delay 2-10 s after drop (ms)", "w2"); row("Delay 10 s+ after drop (ms)", "w3")
row("Worst delay after drop (ms)", "worst"); row("Time until delay < 5 ms (s)", "conv")
row("Detection time, first cut (s)", "det", only_auto=True)
row("Shaper changes after the drop", "n", 0, only_auto=True)
row("Lowest shaper rate after +10 s (Mbit/s)", "lo", 1, True); row("Highest shaper rate after +10 s (Mbit/s)", "hi", 1, True)
row("Download throughput after +10 s (Mbit/s)", "tp", 2)
row("Controller CPU (% of one core)", "cpu", 2, True)
