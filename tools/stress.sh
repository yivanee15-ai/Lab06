#!/bin/bash
# usage: tools/stress.sh <version_dir> [N per mode]   : build verilator sim once, run many generated pattern sets
V=$(readlink -f "$1"); N=${2:-1500}; R=$(cd "$(dirname "$0")/.." && pwd); name=$(basename $V)
B=/tmp/vl_stress_$name; rm -rf $B
(cd $R/01_RTL && verilator --binary --timing -Wno-fatal -Wno-lint --top-module TESTBED -Mdir $B $(ls $V/*.v | tr '\n' ' ') PATTERN.v TESTBED.v -o simv >/dev/null 2>&1) || { echo build failed; exit 1; }
seed=100
for mode in mix full sparse twocol same chain; do
  d=/tmp/stress_dat/$mode; mkdir -p $d/dat
  python3 $R/tools/gen_stress.py $d/dat $seed $N $mode >/dev/null
  r=$(cd $d && $B/simv | grep -E "PASS|FAIL" | head -2 | tr '\n' ' ')
  r2=$(cd $d && $B/simv +TIGHT | grep -E "PASS|FAIL" | head -1)
  echo "[$name] $mode: $r | tight: $r2"
  seed=$((seed+1))
done
