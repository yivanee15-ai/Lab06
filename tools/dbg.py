from probe2 import *
bs = make_boards(20260101, 600)
shown = 0
for g, a, b in bs:
    if a == b: continue
    _, _, _, rows = solve(g, a, b)
    truth = {k for k, r in enumerate(rows) if r and r[0] >= 1}
    fl, _ = flags(g, a, b)
    fp = fl - truth
    if fp and shown < 2:
        shown += 1
        k = min(fp); cc = cand_cells(g, k, a, b)
        print("A,B =", a, b, "heights", [height(g,c) for c in range(W)], "FP cand", k, "cells", cc)
        ps = probes(g, a, b)
        for i, p in enumerate(ps):
            m = find_groups(p, W, H)
            hit = [(r, c) for (r, c, _) in cc if (r, c) in m]
            if hit:
                print(" probe", i, "hit", hit)
                for r in range(min(H-1, max(r for r,_,_ in cc)+3), -1, -1):
                    print("   ", ''.join(('*' if (r,c) in m else ' ') + (str(p[r][c]) if p[r][c] else '.') for c in range(W)))
