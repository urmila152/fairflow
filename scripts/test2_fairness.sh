source ./common.sh
RUNS=5; OUT=res2; rm -rf $OUT; mkdir -p $OUT
MODES="deep fqcodel htbstatic cake"
topo2
for mode in $MODES; do
  for i in $(seq 1 $RUNS); do
    set_mode $mode
    for p in 5201 5202 5203; do
      ip netns exec ns1 iperf3 -c 10.0.0.2 -p $p -t 14 -J > $OUT/${mode}_${i}_tcp$p.json &
    done
    sleep 3
    ip netns exec ns1 iperf3 -c 10.0.0.2 -p 5204 -u -b 1M -l 200 -t 8 -J > $OUT/${mode}_${i}_udp.json &
    ip netns exec ns1 ping -c 40 -i 0.2 10.0.0.2 > $OUT/${mode}_${i}.ping
    wait; sleep 1
    echo "$mode run $i done"
  done
done
cleanup
python3 - <<'PY'
import json, re, statistics as st
modes = ["deep", "fqcodel", "htbstatic", "cake"]; RUNS = 5
jain = lambda x: sum(x) ** 2 / (len(x) * sum(v * v for v in x))
fmt = lambda v: f"{st.mean(v):.2f}+/-{st.stdev(v):.2f}" if len(v) > 1 else "n/a"
keys = ["TCP total (Mbit/s)", "Jain fairness (1=equal)", "Game UDP jitter (ms)", "Game UDP loss (%)", "Ping avg (ms)"]
rows = {k: {m: [] for m in modes} for k in keys}
for m in modes:
    for i in range(1, RUNS + 1):
        try:
            tcp = [json.load(open(f"res2/{m}_{i}_tcp{p}.json"))["end"]["sum_received"]["bits_per_second"] / 1e6 for p in (5201, 5202, 5203)]
            u = json.load(open(f"res2/{m}_{i}_udp.json"))["end"]["sum"]
            t = open(f"res2/{m}_{i}.ping").read()
            avg = float(re.search(r"= [\d.]+/([\d.]+)/", t).group(1))
            rows[keys[0]][m].append(sum(tcp))
            rows[keys[1]][m].append(jain(tcp))
            rows[keys[2]][m].append(u.get("jitter_ms", float("nan")))
            rows[keys[3]][m].append(u.get("lost_percent", float("nan")))
            rows[keys[4]][m].append(avg)
        except Exception as e:
            print("skip", m, i, e)
print(f"\n{'Metric':<26}" + "".join(f"{m:>16}" for m in modes))
for k, d in rows.items():
    print(f"{k:<26}" + "".join(f"{fmt(d[m]):>16}" for m in modes))
PY
