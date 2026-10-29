cleanup(){ pkill iperf3 2>/dev/null; for n in ns1 ns2 home isp srv; do ip netns del $n 2>/dev/null; done; sleep 1; }
topo2(){
  cleanup
  ip netns add ns1; ip netns add ns2
  ip link add veth1 type veth peer name veth2
  ip link set veth1 netns ns1; ip link set veth2 netns ns2
  ip netns exec ns1 ip addr add 10.0.0.1/24 dev veth1
  ip netns exec ns2 ip addr add 10.0.0.2/24 dev veth2
  ip netns exec ns1 ip link set veth1 up
  ip netns exec ns2 ip link set veth2 up
  for p in 5201 5202 5203 5204; do ip netns exec ns2 iperf3 -s -p $p -D; done
  sleep 1
}
set_mode(){
  local T="ip netns exec ns1 tc"
  $T qdisc del dev veth1 root 2>/dev/null
  case $1 in
    deep)  $T qdisc add dev veth1 root netem rate 20mbit limit 1000 ;;
    cake)  $T qdisc add dev veth1 root cake bandwidth 20mbit ;;
    fqcodel)
      $T qdisc add dev veth1 root handle 1: htb default 10
      $T class add dev veth1 parent 1: classid 1:10 htb rate 20mbit ceil 20mbit
      $T qdisc add dev veth1 parent 1:10 fq_codel ;;
    htbstatic)
      $T qdisc add dev veth1 root handle 1: htb default 20
      $T class add dev veth1 parent 1: classid 1:1 htb rate 20mbit ceil 20mbit
      $T class add dev veth1 parent 1:1 classid 1:10 htb rate 4mbit ceil 20mbit prio 0
      $T class add dev veth1 parent 1:1 classid 1:20 htb rate 16mbit ceil 20mbit prio 1
      $T qdisc add dev veth1 parent 1:10 handle 10: pfifo limit 1000
      $T qdisc add dev veth1 parent 1:20 handle 20: pfifo limit 1000
      $T filter add dev veth1 parent 1: protocol ip prio 1 u32 match ip protocol 1 0xff flowid 1:10 ;;
  esac
}
