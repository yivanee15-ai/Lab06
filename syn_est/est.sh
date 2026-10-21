#!/bin/bash
# usage: est.sh <top> <files...> : comb area (NAND2 eq) + flop count + critical comb path delay (ns, generic lib)
top=$1; shift
if [ "$top" = "PUYO_TOP" ]; then
cat > /tmp/est_wrap.v <<WR
module EST_TOP(input clk, input in_valid, input [2:0] in_cell, input [2:0] in_puyo_a, input [2:0] in_puyo_b,
  output out_valid, output [4:0] out_best_candidate, output [4:0] out_chain, output [6:0] out_erased);
PUYO_TOP u(.clk(clk), .rst_n(1'b1), .in_valid(in_valid), .in_cell(in_cell), .in_puyo_a(in_puyo_a), .in_puyo_b(in_puyo_b),
  .out_valid(out_valid), .out_best_candidate(out_best_candidate), .out_chain(out_chain), .out_erased(out_erased));
endmodule
WR
set -- /tmp/est_wrap.v "$@"; REAL=PUYO_TOP; top=EST_TOP
fi
D=$(dirname "$(readlink -f "$0")")
cat > /tmp/est_${REAL:-$top}.ys <<YS
read_verilog -sv $@
hierarchy -top $top
proc; flatten; opt -fast
synth -top $top -run begin:fine
opt -full; techmap; opt -fast
async2sync
dfflegalize -cell \$_DFF_P_ x
tee -o /tmp/est_${REAL:-$top}.flops stat
write_blif -impltf /tmp/est_${REAL:-$top}.blif
YS
yosys -q /tmp/est_${REAL:-$top}.ys >/dev/null 2>&1
nff=$(grep -cE "^\.(latch|subckt .*DFF)" /tmp/est_${REAL:-$top}.blif)
cat > /tmp/est_${REAL:-$top}.scr <<ABC
read_library $D/generic.genlib
read_blif /tmp/est_${REAL:-$top}.blif
comb
strash
dc2
strash
dch -f
map
topo
write_blif /tmp/est_${REAL:-$top}.mapped.blif
print_stats
ABC
yosys-abc -f /tmp/est_${REAL:-$top}.scr > /tmp/est_${REAL:-$top}.abc 2>&1
grep -E "Area =|Delay =" /tmp/est_${REAL:-$top}.abc | tail -2
echo "flops: $(grep -E 'DFF' /tmp/est_${REAL:-$top}.flops | awk '{s+=$2} END{print s}')"
