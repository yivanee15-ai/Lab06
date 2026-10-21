#!/usr/bin/env python3
"""Generate extra TOP patterns into a directory: gen_stress.py OUTDIR SEED N MODE
MODE: mix | full | sparse | twocol | same | chain"""
import os, sys, random
from golden import *

out, seed, n, mode = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
os.makedirs(out, exist_ok=True)
rng = random.Random(seed)

def board(fill, ncolors):
    g = [[0] * W for _ in range(H)]
    heights = [min(H, max(0, int(rng.gauss(fill * H, 2.5)))) for _ in range(W)]
    for c in range(W):
        for r in range(heights[c]):
            opts = list(range(1, ncolors + 1)); rng.shuffle(opts)
            for col in opts:
                g[r][c] = col
                if not find_groups(g, W, H): break
            else:
                g[r][c] = 0; break
    return g

def pick():
    while True:
        if mode == 'full':     g = board(rng.choice([0.85, 0.95, 1.0]), 4)
        elif mode == 'sparse': g = board(rng.choice([0.05, 0.15, 0.3]), 4)
        elif mode == 'twocol': g = board(rng.choice([0.3, 0.5, 0.7]), 2 if rng.random() < .5 else 3)
        else:                  g = board(rng.choice([0.2, 0.4, 0.6, 0.8, 0.95]), rng.choice([2, 3, 4, 4, 4]))
        if not has_legal(g): continue
        a = rng.randint(1, 4)
        b = a if (mode == 'same' or rng.random() < 0.2) else rng.randint(1, 4)
        if mode == 'chain':
            cur = solve(g, a, b)[1:3]
            for _ in range(250):
                r2, c2 = rng.randrange(H), rng.randrange(W)
                if g[r2][c2] == 0: continue
                old = g[r2][c2]; g[r2][c2] = rng.randint(1, 4)
                if find_groups(g, W, H) or not has_legal(g): g[r2][c2] = old; continue
                s = solve(g, a, b)[1:3]
                if s >= cur: cur = s
                else: g[r2][c2] = old
        return g, a, b

with open(os.path.join(out, "top_in.dat"), "w") as fi, open(os.path.join(out, "top_gold.dat"), "w") as fo:
    for _ in range(n):
        g, a, b = pick()
        assert not find_groups(g, W, H) and g == gravity(g, W, H)
        cand, ch, er, _ = solve(g, a, b)
        fi.write("%x\n%x\n" % (a, b))
        for v in grid_to_flat(g, W, H): fi.write("%x\n" % v)
        fo.write("%02x\n%02x\n%02x\n" % (cand, ch, er))
open(os.path.join(out, "ntop.txt"), "w").write(str(n))
print(mode, seed, n)
