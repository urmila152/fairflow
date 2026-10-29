#!/bin/bash
RUNS=5
OUT=results; mkdir -p $OUT
cleanup(){ ip netns exec ns2 pkill iperf3 2>/dev/null; ip netns del ns1 2>/dev/null; ip netns del ns2 2>/dev/null; }
cleanup
ip netns add ns1; ip netns add ns2
ip link add veth1 type veth peer name veth2
ip link set veth1 netns ns1; ip link set veth2 netns ns2
ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth1
ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth2
ip netns exec ns1 ip link set veth1 up
ip netns exec ns2 ip link set veth2 up
ip netns exec ns2 iperf3 -s -D
sleep 1
for mode in baseline cake; do
  for i in $(seq 1 $RUNS); do
    if [ $mode = baseline ]; then
      ip netns exec ns1 tc qdisc replace dev veth1 root netem rate 20mbit limit 1000
    else
      ip netns exec ns1 tc qdisc replace dev veth1 root cake bandwidth 20mbit
    fi
    ip netns exec ns1 iperf3 -c 10.0.0.2 -t 12 -J > $OUT/${mode}_$i.json &
    sleep 3
    ip netns exec ns1 ping -c 30 -i 0.2 10.0.0.2 > $OUT/${mode}_$i.ping
    wait
    echo "$mode run $i done"
  done
done
cleanup
python3 - <<'PYEOF'
import json, glob, re, statistics as st
def load(mode):
    avg, mx, jit, loss, tp = [], [], [], [], []
    for f in sorted(glob.glob(f"results/{mode}_*.ping")):
        t = open(f).read()
        m = re.search(r"min/avg/max/mdev = ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)", t)
        l = re.search(r"([\d.]+)% packet loss", t)
        avg.append(float(m.group(2))); mx.append(float(m.group(3)))
        jit.append(float(m.group(4))); loss.append(float(l.group(1)))
    for f in sorted(glob.glob(f"results/{mode}_*.json")):
        d = json.load(open(f))
        tp.append(d["end"]["sum_received"]["bits_per_second"] / 1e6)
    return avg, mx, jit, loss, tp
def fmt(v): return f"{st.mean(v):.2f} +/- {st.stdev(v):.2f}"
print(f"\n{'Metric':<28}{'Baseline':>22}{'CAKE':>22}")
names = ["Avg latency (ms)", "Max latency (ms)", "Jitter / mdev (ms)", "Packet loss (%)", "Download throughput (Mbit/s)"]
b, c = load("baseline"), load("cake")
for n, x, y in zip(names, b, c):
    print(f"{n:<28}{fmt(x):>22}{fmt(y):>22}")
PYEOF
