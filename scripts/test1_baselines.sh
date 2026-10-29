source ./common.sh
RUNS=5; OUT=res1; rm -rf $OUT; mkdir -p $OUT
topo2
for mode in deep fqcodel htbstatic cake; do
  for i in $(seq 1 $RUNS); do
    set_mode $mode
    ip netns exec ns1 iperf3 -c 10.0.0.2 -t 12 -J > $OUT/${mode}_$i.json &
    sleep 3
    ip netns exec ns1 ping -c 30 -i 0.2 10.0.0.2 > $OUT/${mode}_$i.ping
    wait; sleep 1
    echo "$mode run $i done"
  done
done
cleanup
python3 - <<'PY'
import json, glob, re, statistics as st
modes = ["deep", "fqcodel", "htbstatic", "cake"]
def load(m):
    a, j, tp = [], [], []
    for f in sorted(glob.glob(f"res1/{m}_*.ping")):
        t = open(f).read()
        x = re.search(r"min/avg/max/mdev = ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)", t)
        a.append(float(x.group(2))); j.append(float(x.group(4)))
    for f in sorted(glob.glob(f"res1/{m}_*.json")):
        tp.append(json.load(open(f))["end"]["sum_received"]["bits_per_second"] / 1e6)
    return a, j, tp
fmt = lambda v: f"{st.mean(v):.2f}+/-{st.stdev(v):.2f}"
print(f"\n{'Metric':<26}" + "".join(f"{m:>16}" for m in modes))
data = {m: load(m) for m in modes}
for k, n in enumerate(["Avg latency (ms)", "Jitter (ms)", "Throughput (Mbit/s)"]):
    print(f"{n:<26}" + "".join(f"{fmt(data[m][k]):>16}" for m in modes))
PY
