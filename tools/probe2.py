from golden import *
from probe_study import height, cand_cells

def probes(g, a, b):
    """list of probe boards. each places one piece per used column."""
    h = [height(g, c) for c in range(W)]
    def mk(cells):
        p = [row[:] for row in g]
        for (r, c, col) in cells:
            if r < H: p[r][c] = col
        return p
    out = []
    if a != b:
        for swap in (0, 1):
            for t in (0, 1):                     # spot type: S0 (row h) or S1 (row h+1)
                cells = []
                for c in range(W):
                    col = (a, b)[(c + swap) % 2]
                    cells.append((h[c] + t, c, col))
                out.append(mk(cells))
    else:
        # one colour: pieces on alternate columns only; vertical pairs and horizontal pairs handled as units
        ve = [(h[c], c, a) for c in (0, 2, 4)] + [(h[c]+1, c, a) for c in (0, 2, 4)]
        vo = [(h[c], c, a) for c in (1, 3, 5)] + [(h[c]+1, c, a) for c in (1, 3, 5)]
        h03 = [(h[l], l, a) for l in (0, 1, 3, 4)]          # H(0), H(3)
        h14 = [(h[l], l, a) for l in (1, 2, 4, 5)]          # H(1), H(4)
        h2  = [(h[l], l, a) for l in (2, 3)]                # H(2)
        out = [mk(ve), mk(vo), mk(h03), mk(h14), mk(h2)]
    return out

def flags(g, a, b):
    ps = probes(g, a, b)
    ms = [find_groups(p, W, H) for p in ps]
    fl = set()
    for k in range(22):
        cc = cand_cells(g, k, a, b)
        if cc is None: continue
        if any(any((r, c) in m for (r, c, _) in cc) for m in ms): fl.add(k)
    return fl, len(ps)

if __name__ == "__main__":
    bs = make_boards(20260101, 600)
    tf = tt = 0; nd = 0; fn = 0; sp = {True: [0, 0], False: [0, 0]}
    for g, a, b in bs:
        _, _, _, rows = solve(g, a, b)
        truth = {k for k, r in enumerate(rows) if r and r[0] >= 1}
        fl, npb = flags(g, a, b)
        if not truth <= fl: fn += 1
        tf += len(fl); tt += len(truth)
        sp[a == b][0] += len(fl); sp[a == b][1] += 1
    print(f"avg flagged {tf/len(bs):.2f}  true {tt/len(bs):.2f}  patterns with false negatives: {fn}")
    for k, v in sp.items(): print("A==B" if k else "A!=B", "avg flagged", v[0]/v[1], "n", v[1])
