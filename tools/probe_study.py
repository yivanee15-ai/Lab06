from golden import *
import random

def height(g, c): return sum(1 for r in range(H) if g[r][c])

def spots(g):
    return [(height(g, c), c) for c in range(W)]

def cand_cells(g, k, a, b):
    """cells (row,col,color) a candidate occupies, or None if illegal."""
    h = [height(g, c) for c in range(W)]
    if k < 6:   c=k;    return None if h[c]>10 else [(h[c],c,b),(h[c]+1,c,a)]
    if k < 12:  c=k-6;  return None if h[c]>10 else [(h[c],c,a),(h[c]+1,c,b)]
    if k < 17:  l=k-12; return None if h[l]>11 or h[l+1]>11 else [(h[l],l,a),(h[l+1],l+1,b)]
    l=k-17;             return None if h[l]>11 or h[l+1]>11 else [(h[l],l,b),(h[l+1],l+1,a)]

def probe_boards(g, a, b, mode):
    """list of (board, ...) probe boards. mode selects the scheme."""
    h = [height(g, c) for c in range(W)]
    def put(cells):
        p = [row[:] for row in g]
        for (r, c, col) in cells:
            if r < H: p[r][c] = col
        return p
    px, py = [], []
    for c in range(W):
        if c % 2 == 0: px += [(h[c], c, a), (h[c]+1, c, b)]; py += [(h[c], c, b), (h[c]+1, c, a)]
        else:          px += [(h[c], c, b), (h[c]+1, c, a)]; py += [(h[c], c, a), (h[c]+1, c, b)]
    if mode == 2 or a != b:
        return [put(px), put(py)]
    # a == b : 4 probes  (V even, V odd, H even-left, H odd-left)
    ve = [(h[c], c, a) for c in (0,2,4)] + [(h[c]+1, c, a) for c in (0,2,4)]
    vo = [(h[c], c, a) for c in (1,3,5)] + [(h[c]+1, c, a) for c in (1,3,5)]
    he = [(h[c], c, a) for c in range(W)]          # H(0),H(2),H(4) ; neighbours merge when heights equal
    ho = [(h[c], c, a) for c in range(1, 5)]       # H(1),H(3) (cols 1..4)
    return [put(ve), put(vo), put(he), put(ho)]

def flagged(g, a, b, mode):
    fl = set()
    for p in probe_boards(g, a, b, mode):
        m = find_groups(p, W, H)
        for k in range(22):
            cc = cand_cells(g, k, a, b)
            if cc and any((r, c) in m for (r, c, _) in cc): fl.add(k)
    return fl

if __name__ == "__main__":
    bs = make_boards(20260101, 600)
    for mode in (2, 4):
        tot_f = tot_t = tot_fp = 0; same = same_f = same_n = 0
        for g, a, b in bs:
            _, _, _, rows = solve(g, a, b)
            truth = {k for k, r in enumerate(rows) if r and r[0] >= 1}
            fl = flagged(g, a, b, mode)
            assert truth <= fl, ("false negative", truth - fl)
            tot_f += len(fl); tot_t += len(truth)
            if a == b: same_f += len(fl); same_n += 1
        print(f"mode {mode}: avg flagged {tot_f/len(bs):.2f} vs true {tot_t/len(bs):.2f}; A==B patterns {same_n}, avg flagged there {same_f/max(1,same_n):.2f}")
