#!/bin/bash
# Regenerate patterns and run Soft-IP + TOP RTL simulation (iverilog). TOP takes ~2 min.
set -e
cd "$(dirname "$0")"
python3 tools/gen_pattern.py ${1:-600}
cd 01_RTL
iverilog -g2005 -o /tmp/ip.vvp  PUYO_SOFT_IP.v Pattern_IP.v && vvp /tmp/ip.vvp
iverilog -g2005 -o /tmp/top.vvp PUYO_SOFT_IP.v PUYO_TOP.v PATTERN.v TESTBED.v && vvp /tmp/top.vvp
