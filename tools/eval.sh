#!/bin/bash
# usage: tools/eval.sh <version_dir>   (dir holds PUYO_TOP.v + PUYO_SOFT_IP.v [+ extra .v])
V=$(readlink -f "$1"); R=$(cd "$(dirname "$0")/.." && pwd); name=$(basename $V)
SRC=$(ls $V/*.v | tr '\n' ' ')
cd $R/01_RTL
B=/tmp/vl_$name; rm -rf $B; mkdir -p $B
verilator --binary --timing -Wno-fatal -Wno-lint --top-module Pattern_IP -Mdir $B/ip $V/PUYO_SOFT_IP.v Pattern_IP.v -o simv >$B/ip.log 2>&1 && $B/ip/simv | grep -E "IP |FAIL" 
verilator --binary --timing -Wno-fatal -Wno-lint --top-module TESTBED -Mdir $B/top $SRC PATTERN.v TESTBED.v -o simv >$B/top.log 2>&1 || { tail -20 $B/top.log; exit 1; }
$B/top/simv | grep -E "PASS|FAIL" | head -6 | tee $B/sim.out
lat=$(grep -oE "avg latency = [0-9.]+" $B/sim.out | grep -oE "[0-9.]+$")
est=$($R/syn_est/est.sh PUYO_TOP $SRC)
echo "$est"
area=$(grep -oE "area =[ 0-9.]+" /tmp/est_PUYO_TOP.abc | tail -1 | grep -oE "[0-9.]+")
dly=$(grep -oE "delay = *[0-9.]+" /tmp/est_PUYO_TOP.abc | tail -1 | grep -oE "[0-9.]+")
ff=$(grep -E 'DFF' /tmp/est_PUYO_TOP.flops | awk '{s+=$2} END{print s}')
python3 - <<PY
a=$area+6*$ff; t=$dly+0.30; l=${lat:-0}
print(f"[{'$name'}] comb={$area:.0f} flops={$ff} area={a:.0f}  T={t:.2f}ns  avgLat={l}  score(A*T*L)={a*t*l/1e3:.0f}k")
PY
