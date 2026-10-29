RUNS=5; OUT=res4; rm -rf $OUT; mkdir -p $OUT
cleanup4(){ pkill iperf3 2>/dev/null; for n in a b r s; do ip netns del $n 2>/dev/null; done; sleep 1; }
cleanup4
for n in a b r s; do ip netns add $n; done
ip link add a0 type veth peer name ra
ip link add b0 type veth peer name rb
ip link add rs type veth peer name s0
ip link set a0 netns a; ip link set ra netns r
ip link set b0 netns b; ip link set rb netns r
ip link set rs netns r; ip link set s0 netns s
ip netns exec a ip addr add 10.1.1.2/24 dev a0
ip netns exec r ip addr add 10.1.1.1/24 dev ra
ip netns exec b ip addr add 10.1.2.2/24 dev b0
ip netns exec r ip addr add 10.1.2.1/24 dev rb
ip netns exec r ip addr add 10.1.3.1/24 dev rs
ip netns exec s ip addr add 10.1.3.2/24 dev s0
for x in "a a0" "b b0" "r ra" "r rb" "r rs" "s s0"; do set -- $x; ip netns exec $1 ip link set $2 up; done
ip netns exec a ip route add default via 10.1.1.1
ip netns exec b ip route add default via 10.1.2.1
ip netns exec s ip route add 10.1.1.0/24 via 10.1.3.1
ip netns exec s ip route add 10.1.2.0/24 via 10.1.3.1
ip netns exec r sysctl -qw net.ipv4.ip_forward=1
ip netns exec s iperf3 -s -p 5201 -D
ip netns exec s iperf3 -s -p 5202 -D
sleep 1
ip netns exec a ping -c 2 10.1.3.2 || { echo "CONNECTIVITY FAILED (a)"; cleanup4; exit 1; }
ip netns exec b ping -c 2 10.1.3.2 || { echo "CONNECTIVITY FAILED (b)"; cleanup4; exit 1; }
for mode in flows dual-srchost; do
  for i in $(seq 1 $RUNS); do
    ip netns exec r tc qdisc replace dev rs root cake bandwidth 20mbit $mode
    ip netns exec a iperf3 -c 10.1.3.2 -p 5201 -t 12 -J > $OUT/${mode}_${i}_A.json &
    ip netns exec b iperf3 -c 10.1.3.2 -p 5202 -P 8 -t 12 -J > $OUT/${mode}_${i}_B.json &
    wait; sleep 1
    echo "$mode run $i done"
  done
done
cleanup4
python3 - <<'PY'
import json, statistics as st
fmt = lambda v: f"{st.mean(v):.2f}+/-{st.stdev(v):.2f}"
jain = lambda x: sum(x) ** 2 / (len(x) * sum(v * v for v in x))
res = {}
for m in ["flows", "dual-srchost"]:
    A, B, S, J = [], [], [], []
    for i in range(1, 6):
        a = json.load(open(f"res4/{m}_{i}_A.json"))["end"]["sum_received"]["bits_per_second"] / 1e6
        b = json.load(open(f"res4/{m}_{i}_B.json"))["end"]["sum_received"]["bits_per_second"] / 1e6
        A.append(a); B.append(b); S.append(100 * a / (a + b)); J.append(jain([a, b]))
    res[m] = (A, B, S, J)
rows = ["Person A, 1 upload (Mbit/s)", "Person B, 8 uploads (Mbit/s)", "Person A share of link (%)", "Fairness between people (Jain)"]
print(f"\n{'Metric':<34}{'per-flow fairness':>20}{'per-person fairness':>22}")
for k, n in enumerate(rows):
    print(f"{n:<34}{fmt(res['flows'][k]):>20}{fmt(res['dual-srchost'][k]):>22}")
PY
