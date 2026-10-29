source ./common.sh
RUNS=${RUNS:-3}; OUT=res5; rm -rf $OUT; mkdir -p $OUT
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
for x in "home h-i" "isp i-h" "isp i-s" "srv s-i"; do set -- $x; ip netns exec $1 ip link set $2 up; done
ip netns exec isp sysctl -qw net.ipv4.ip_forward=1
ip netns exec home ip route add 10.0.2.0/24 via 10.0.1.2
ip netns exec srv  ip route add 10.0.1.0/24 via 10.0.2.1
ip netns exec srv iperf3 -s -D; sleep 1
ip netns exec home ping -c 2 10.0.2.2 || { echo "CONNECTIVITY FAILED"; cleanup; exit 1; }
run(){
  local mode=$1 i=$2
  ip netns exec isp  tc qdisc replace dev i-s root netem rate 100mbit limit 1000
  ip netns exec home tc qdisc replace dev h-i root cake bandwidth 95mbit
  ip netns exec home iperf3 -c 10.0.2.2 -t 34 -J > $OUT/${mode}_$i.json &
  sleep 2
  if [ $mode = auto ]; then ip netns exec home python3 controller.py $OUT/auto_$i.log 31 & fi
  ip netns exec home ping -D -c 150 -i 0.2 10.0.2.2 > $OUT/${mode}_$i.ping &
  sleep 6
  date +%s.%N > $OUT/${mode}_$i.drop
  ip netns exec isp tc qdisc replace dev i-s root netem rate 20mbit limit 1000
  wait; sleep 1
  echo "$mode run $i done"
}
for mode in static auto; do for i in $(seq 1 $RUNS); do run $mode $i; done; done
cleanup
python3 analyze5.py | tee $OUT/REPORT.txt
