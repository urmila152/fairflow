source ./common.sh
RUNS=3; OUT=res3; rm -rf $OUT; mkdir -p $OUT
cleanup
ip netns add home; ip netns add isp; ip netns add srv
ip link add h-i type veth peer name i-h
ip link add i-s type veth peer name s-i
ip link set h-i netns home; ip link set i-h netns isp
ip link set i-s netns isp;  ip link set s-i netns srv
ip netns exec home ip addr add 10.0.1.1/24 dev h-i
ip netns exec isp  ip addr add 10.0.1.2/24 dev i-h
ip netns exec isp  ip addr add 10.0.2.1/24 dev i-s
ip netns exec srv  ip addr add 10.0.2.2/24 dev s-i
ip netns exec home ip link set h-i up
ip netns exec isp  ip link set i-h up
ip netns exec isp  ip link set i-s up
ip netns exec srv  ip link set s-i up
ip netns exec isp sysctl -qw net.ipv4.ip_forward=1
ip netns exec home ip route add 10.0.2.0/24 via 10.0.1.2
ip netns exec srv  ip route add 10.0.1.0/24 via 10.0.2.1
ip netns exec srv iperf3 -s -D; sleep 1
echo "Checking connectivity..."
ip netns exec home ping -c 2 10.0.2.2 || { echo "CONNECTIVITY FAILED"; cleanup; exit 1; }
run(){
  local mode=$1 i=$2
  ip netns exec isp  tc qdisc replace dev i-s root netem rate 100mbit limit 1000
  ip netns exec home tc qdisc replace dev h-i root cake bandwidth 95mbit
  ip netns exec home iperf3 -c 10.0.2.2 -t 34 -J > $OUT/${mode}_$i.json &
  sleep 2
  ip netns exec home ping -D -c 150 -i 0.2 10.0.2.2 > $OUT/${mode}_$i.ping &
  sleep 6
  date +%s.%N > $OUT/${mode}_$i.drop
  ip netns exec isp tc qdisc replace dev i-s root netem rate 20mbit limit 1000
  if [ $mode = adaptive ]; then
    sleep 2
    ip netns exec home tc qdisc replace dev h-i root cake bandwidth 18mbit
  fi
  wait; sleep 1
  echo "$mode run $i done"
}
for mode in static adaptive; do for i in $(seq 1 $RUNS); do run $mode $i; done; done
cleanup
python3 - <<'PY'
import glob, re, statistics as st
names = ["Before drop", "0-2 s after drop", "2-10 s after drop", "10 s+ after drop"]
def win(mode):
    res = [[] for _ in names]
    for f in sorted(glob.glob(f"res3/{mode}_*.ping")):
        drop = float(open(f.replace(".ping", ".drop")).read())
        b = [[] for _ in names]
        for line in open(f):
            m = re.search(r"\[(\d+\.\d+)\].*time=([\d.]+) ms", line)
            if not m: continue
            t = float(m.group(1)) - drop; v = float(m.group(2))
            k = 0 if t < 0 else 1 if t < 2 else 2 if t < 10 else 3
            b[k].append(v)
        for k in range(4):
            if b[k]: res[k].append(st.mean(b[k]))
    return res
s, a = win("static"), win("adaptive")
print(f"\n{'Avg latency (ms)':<22}{'static shaper':>16}{'adaptive shaper':>18}")
for k, n in enumerate(names):
    sv = f"{st.mean(s[k]):.1f}" if s[k] else "n/a"
    av = f"{st.mean(a[k]):.1f}" if a[k] else "n/a"
    print(f"{n:<22}{sv:>16}{av:>18}")
PY
