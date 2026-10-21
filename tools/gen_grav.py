#!/usr/bin/env python3
"""Generate a single-column compaction module (12 cells x 2 bits, keep mask in, survivors out).
usage: gen_grav.py GS tree|seq   -> prints Verilog for modules PUYO_GRAV_COL and PUYO_GRAV"""
import sys
GS = int(sys.argv[1]); MODE = sys.argv[2]
H = 12; NG = H // GS
L = []
def w(s): L.append(s)

w("module PUYO_GRAV_COL (input [23:0] cv, input [11:0] keep, output [23:0] out, output [3:0] total);")
uid = [0]
def new(prefix='t'):
    uid[0] += 1; return f"{prefix}{uid[0]}"

class Blk:  # compacted block: n cell names (2-bit wires) and one-hot count names (n+1)
    def __init__(s, cells, oh): s.cells = cells; s.oh = oh; s.n = len(cells)

def popcount_terms(bits):
    return bits

# ---- leaves
leaves = []
for g in range(NG):
    ks = [f"keep[{GS*g+p}]" for p in range(GS)]
    vs = [f"cv[{2*(GS*g+p)+1}:{2*(GS*g+p)}]" for p in range(GS)]
    # one-hot rank of each cell: rank r_q = number of kept cells before q (as one-hot over 0..q)
    cells = []
    # kept count one-hot via sequential one-hot accumulate
    cnt = [f"1'b1"] + ["1'b0"] * GS   # one-hot of 0
    ranks = []
    cur = cnt
    for q in range(GS):
        ranks.append(cur)
        nxt = []
        for t in range(GS + 1):
            a = cur[t]; b = cur[t-1] if t > 0 else "1'b0"
            nxt.append(f"(({a}) & ~{ks[q]}) | (({b}) & {ks[q]})")
        names = []
        for t, e in enumerate(nxt):
            nm = new('c'); w(f"wire {nm} = {e};"); names.append(nm)
        cur = names
    oh = cur
    for p in range(GS):
        terms = []
        for q in range(p, GS):
            terms.append(f"({{2{{{ks[q]} & {ranks[q][p]}}}}} & {vs[q]})")
        nm = new('v'); w(f"wire [1:0] {nm} = " + " | ".join(terms) + ";"); cells.append(nm)
    leaves.append(Blk(cells, oh))

def merge(A, B):
    n = A.n + B.n
    # suffix OR of A.oh : ge[p] = OR_{a>=p} A.oh[a]
    ge = [None] * (A.n + 2)
    ge[A.n + 1] = "1'b0"
    for a in range(A.n, -1, -1):
        nm = new('g'); w(f"wire {nm} = {A.oh[a]} | {ge[a+1]};"); ge[a] = nm
    cells = []
    for p in range(n):
        terms = []
        if p < A.n: terms.append(f"({{2{{{ge[p+1]}}}}} & {A.cells[p]})")
        for a in range(max(0, p - B.n + 1), min(p, A.n) + 1):
            terms.append(f"({{2{{{A.oh[a]}}}}} & {B.cells[p-a]})")
        nm = new('m'); w(f"wire [1:0] {nm} = " + (" | ".join(terms) if terms else "2'd0") + ";"); cells.append(nm)
    oh = []
    for t in range(n + 1):
        terms = [f"({A.oh[a]} & {B.oh[t-a]})" for a in range(0, A.n + 1) if 0 <= t - a <= B.n]
        nm = new('o'); w(f"wire {nm} = " + (" | ".join(terms) if terms else "1'b0") + ";"); oh.append(nm)
    return Blk(cells, oh)

if MODE == 'seq':
    acc = leaves[0]
    for b in leaves[1:]: acc = merge(acc, b)
else:
    lv = leaves
    while len(lv) > 1:
        nx = []
        for i in range(0, len(lv) - 1, 2): nx.append(merge(lv[i], lv[i+1]))
        if len(lv) % 2: nx.append(lv[-1])
        lv = nx
    acc = lv[0]
for p in range(H):
    w(f"assign out[{2*p+1}:{2*p}] = {acc.cells[p]};")
for bit in range(4):
    terms = [acc.oh[t] for t in range(H + 1) if (t >> bit) & 1]
    w(f"assign total[{bit}] = " + " | ".join(terms) + ";")
w("endmodule\n")
w('''module PUYO_GRAV #(parameter W = 6, parameter H = 12)(
    input  [W*H*2-1:0] board,
    input  [W*H-1:0]   mask,
    input  [4*W-1:0]   hgt,
    output [W*H*2-1:0] board_n,
    output [4*W-1:0]   hgt_n
);
genvar c, j;
generate
    for (c = 0; c < W; c = c + 1) begin : g_col
        wire [23:0] cv;
        wire [11:0] keep;
        wire [23:0] o;
        for (j = 0; j < H; j = j + 1) begin : g_v
            assign cv[2*j +: 2] = board[2*((H-1-j)*W + c) +: 2];
            assign keep[j]      = ~mask[(H-1-j)*W + c] && (j < hgt[4*c +: 4]);   // padding never survives
            assign board_n[2*((H-1-j)*W + c) +: 2] = o[2*j +: 2];
        end
        PUYO_GRAV_COL u_col (.cv(cv), .keep(keep), .out(o), .total(hgt_n[4*c +: 4]));
    end
endgenerate
endmodule''')
print("\n".join(L))
