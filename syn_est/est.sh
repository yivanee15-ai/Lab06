#!/bin/bash
# usage: est.sh <top> <files...> : comb area (NAND2 eq) + flop count + critical comb path delay (ns, generic lib)
top=$1; shift
D=$(dirname "$(readlink -f "$0")")
cat > /tmp/est_$top.ys <<YS
read_verilog -sv $@
hierarchy -top $top
proc; flatten; opt -fast; synth -top $top -run begin:fine
opt -full; techmap; opt -fast
async2sync
dfflegalize -cell \$_DFF_P_ x
tee -o /tmp/est_$top.flops stat
write_blif -impltf /tmp/est_$top.blif
YS
yosys -q /tmp/est_$top.ys >/dev/null 2>&1
nff=$(grep -cE "^\.(latch|subckt .*DFF)" /tmp/est_$top.blif)
cat > /tmp/est_$top.scr <<ABC
read_library $D/generic.genlib
read_blif /tmp/est_$top.blif
comb
strash
dc2
strash
dch -f
map
topo
print_stats
ABC
yosys-abc -f /tmp/est_$top.scr > /tmp/est_$top.abc 2>&1
grep -E "Area =|Delay =" /tmp/est_$top.abc | tail -2
echo "flops: $(grep -E 'DFF' /tmp/est_$top.flops | awk '{s+=$2} END{print s}')"
