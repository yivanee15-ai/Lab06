#!/bin/bash
# Regenerate patterns, then run the Soft IP test (6 parameter settings) and the TOP test on 01_RTL (Verilator).
# usage: ./run_all.sh [N_TOP_PATTERNS]
set -e
cd "$(dirname "$0")"
python3 tools/gen_pattern.py ${1:-600}
cd 01_RTL
verilator --binary --timing -Wno-fatal -Wno-lint --top-module Pattern_IP -Mdir /tmp/vl_ip PUYO_SOFT_IP.v Pattern_IP.v -o simv >/dev/null 2>&1
/tmp/vl_ip/simv | grep -E "IP "
verilator --binary --timing -Wno-fatal -Wno-lint --top-module TESTBED -Mdir /tmp/vl_top PUYO_TOP.v PUYO_SOFT_IP.v PATTERN.v TESTBED.v -o simv >/dev/null 2>&1
/tmp/vl_top/simv | grep -E "PASS|FAIL"
echo "extra stress sets:  tools/stress.sh versions/v9 1500   |  4-state check: iverilog (see README)"
