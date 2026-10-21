from golden import *
from probe_study import height, cand_cells
bs = make_boards(20260101, 600)
D4 = ((1,0),(-1,0),(0,1),(0,-1))

def cell(g, r, c):
    return g[r][c] if 0 <= r < H and 0 <= c < W else 0

def comp_size(g, r, c):
    col = g[r][c]; seen = {(r, c)}; st = [(r, c)]
    while st:
        y, x = st.pop()
        for dy, dx in D4:
            ny, nx = y+dy, x+dx
            if 0 <= ny < H and 0 <= nx < W and (ny, nx) not in seen and g[ny][nx] == col:
                seen.add((ny, nx)); st.append((ny, nx))
    return len(seen)

def nbrs(g, r, c, exclude):
    return [(r+dy, c+dx) for dy, dx in D4 if (r+dy, c+dx) not in exclude and 0 <= r+dy < H and 0 <= c+dx < W]

def level(g, k, a, b, lvl):
    cc = cand_cells(g, k, a, b)
    if cc is None: return None
    ex = {(r, c) for r, c, _ in cc}
    colors = {(r, c): col for r, c, col in cc}
    # same-colour neighbours of the candidate's pieces (base cells only)
    tot_adj = 0; tot_sz = 0; any_adj = False
    # group pieces by colour connectivity (pieces adjacent & same colour merge)
    (r0, c0, x0), (r1, c1, x1) = cc
    merged = (x0 == x1) and abs(r0-r1)+abs(c0-c1) == 1
    pieces = [[(r0, c0, x0), (r1, c1, x1)]] if merged else [[(r0, c0, x0)], [(r1, c1, x1)]]
    res = False
    for grp in pieces:
        cells = {(r, c) for r, c, _ in grp}; x = grp[0][2]
        adj = set()
        for (r, c) in cells:
            for (nr, nc) in nbrs(g, r, c, ex):
                if g[nr][nc] == x: adj.add((nr, nc))
        if lvl == 'c1':          # colours only: at least one matching neighbour
            ok = len(adj) >= 1 and (len(cells) + 0 >= 1)
        elif lvl == 'c2':        # >=2 matching neighbours, or one neighbour that itself has a matching neighbour
            ok = len(adj) >= 2 or any(any(g[nr][nc] == x for nr, nc in nbrs(g, ar, ac, ex | cells)) for ar, ac in adj)
            if len(cells) == 2: ok = len(adj) >= 1 and ok
        else:                    # exact by sizes of distinct components
            seen = set(); size = len(cells)
            for (ar, ac) in adj:
                if (ar, ac) in seen: continue
                # component of base cell
                st = [(ar, ac)]; seen.add((ar, ac))
                while st:
                    y, xx = st.pop(); size += 1
                    for dy, dx in D4:
                        ny, nx = y+dy, xx+dx
                        if 0 <= ny < H and 0 <= nx < W and (ny, nx) not in seen and (ny, nx) not in ex and g[ny][nx] == x:
                            seen.add((ny, nx)); st.append((ny, nx))
            ok = size >= 4
        res = res or ok
    return res

for lvl in ('c1', 'c2', 'exact'):
    f = t = 0; fn = 0
    for g, a, b in bs:
        _, _, _, rows = solve(g, a, b)
        for k in range(22):
            v = level(g, k, a, b, lvl)
            if v is None: continue
            truth = rows[k][0] >= 1
            f += v; t += truth
            if truth and not v: fn += 1
    print(f"{lvl}: avg flagged {f/len(bs):.2f}, true {t/len(bs):.2f}, false negatives {fn}")
