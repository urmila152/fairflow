# FairFlow: Adaptive QoS for Home Broadband (TELIPORT S4, Case Study 3)

Lab experiments and a first controller prototype. All results are from an emulated Linux lab
(network namespaces, veth, tc/netem, iperf3, ping); see docs/environment.txt.

## Reproduce (Linux with tc, CAKE, netem, iperf3, python3; run as root)
    cd scripts
    sudo bash test1_baselines.sh    # deep queue vs fq_codel vs static HTB vs CAKE
    sudo bash test2_fairness.sh     # 3 bulk flows + game-like UDP flow
    sudo bash test3_capdrop.sh      # link drop, scripted re-shape
    sudo bash test4_household.sh    # per-flow vs per-person fairness
    sudo bash test5_estimator.sh    # controller detects link drop by itself (needs controller.py, analyze5.py)
    sudo bash test6_ipv6.sh         # IPv6 queue test
Each script deletes and recreates its own results folder. Raw outputs from our runs are in data/.
Numbers will differ somewhat on other machines.

## Limits
Emulated virtual links, not real gateway hardware. ICMP round-trip time is both the controller's
signal and the latency measure. The deep-queue baseline is deliberately deep. Controller tested on
IPv4 only, 3 runs. Classifier, call-quality verifier, intent API and dashboard are not built yet.
Results integrity: see docs/MANIFEST.sha256.
