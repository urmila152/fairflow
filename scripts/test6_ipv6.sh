source ./common.sh
OUT=res6; rm -rf $OUT; mkdir -p $OUT
topo2
ip netns exec ns1 ip -6 addr add fd00::1/64 dev veth1 nodad
ip netns exec ns2 ip -6 addr add fd00::2/64 dev veth2 nodad
sleep 1
ip netns exec ns1 ping -6 -c 2 fd00::2 || { echo "IPv6 CONNECTIVITY FAILED"; cleanup; exit 1; }
for mode in deep cake; do
  for i in 1 2 3; do
    set_mode $mode
    ip netns exec ns1 iperf3 -6 -c fd00::2 -t 12 -J > $OUT/${mode}_$i.json &
    sleep 3
    ip netns exec ns1 ping -6 -c 30 -i 0.2 fd00::2 > $OUT/${mode}_$i.ping
    wait; sleep 1
    echo "$mode run $i done"
  done
done
cleanup
python3 - <<'PY' | tee res6/REPORT.txt
import json, glob, re, statistics as st
fmt = lambda v: f"{st.mean(v):.2f}+/-{st.stdev(v):.2f}"
print(f"\n{'IPv6, 20 Mbit/s link':<30}{'deep':>16}{'cake':>16}")
D = {}
for m in ("deep", "cake"):
    a, j, tp = [], [], []
    for f in sorted(glob.glob(f"res6/{m}_*.ping")):
        x = re.search(r"= ([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)", open(f).read())
        a.append(float(x.group(2))); j.append(float(x.group(4)))
    for f in sorted(glob.glob(f"res6/{m}_*.json")):
        tp.append(json.load(open(f))["end"]["sum_received"]["bits_per_second"] / 1e6)
    D[m] = (a, j, tp)
for k, n in enumerate(["Avg delay (ms)", "Jitter (ms)", "Throughput (Mbit/s)"]):
    print(f"{n:<30}{fmt(D['deep'][k]):>16}{fmt(D['cake'][k]):>16}")
PY
