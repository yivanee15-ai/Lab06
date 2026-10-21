"""Golden model for Puyo Puyo Placement Solver (Lab06).
Board: list of rows, row 0 = BOTTOM, row H-1 = TOP; each row a list of W colors.
Flattened (spec) order: top-left first, row-major, top row first.
"""
import random

W, H = 6, 12


def flat_to_grid(flat, w, h):
    """flat index i = (top-based row)*w + col  ->  grid[bottom_row][col]"""
    g = [[0] * w for _ in range(h)]
    for i, v in enumerate(flat):
        tr, c = divmod(i, w)
        g[h - 1 - tr][c] = v
    return g


def grid_to_flat(g, w, h):
    return [g[h - 1 - tr][c] for tr in range(h) for c in range(w)]


def find_groups(g, w, h):
    """One erase round: returns set of (r,c) in components of size>=4 (BFS, 4-neighbour)."""
    seen, out = set(), set()
    for r in range(h):
        for c in range(w):
            if g[r][c] == 0 or (r, c) in seen:
                continue
            col, comp, st = g[r][c], [], [(r, c)]
            seen.add((r, c))
            while st:
                y, x = st.pop()
                comp.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and (ny, nx) not in seen and g[ny][nx] == col:
                        seen.add((ny, nx))
                        st.append((ny, nx))
            if len(comp) >= 4:
                out.update(comp)
    return out


def gravity(g, w, h):
    n = [[0] * w for _ in range(h)]
    for c in range(w):
        k = 0
        for r in range(h):
            if g[r][c]:
                n[k][c] = g[r][c]
                k += 1
    return n


def place(g, cand, a, b, w=W, h=H):
    """Return new grid or None if illegal. Candidate table from spec (w=6)."""
    g = [row[:] for row in g]
    height = lambda c: sum(1 for r in range(h) if g[r][c])
    nv = w  # number of vertical ids per orientation
    nh = w - 1
    if cand < nv:                       # A above B, column = id
        c, top, bot = cand, a, b
    elif cand < 2 * nv:                 # B above A
        c, top, bot = cand - nv, b, a
    else:
        c = None
    if c is not None:
        hh = height(c)
        if h - hh < 2:
            return None
        g[hh][c], g[hh + 1][c] = bot, top
        return g
    if cand < 2 * nv + nh:              # A left of B
        l, left, right = cand - 2 * nv, a, b
    else:                               # B left of A
        l, left, right = cand - 2 * nv - nh, b, a
    hl, hr = height(l), height(l + 1)
    if hl >= h or hr >= h:
        return None
    g[hl][l], g[hr][l + 1] = left, right
    return g


def evaluate(g, w=W, h=H):
    chain = erased = 0
    while True:
        m = find_groups(g, w, h)
        if not m:
            return chain, erased
        chain += 1
        erased += len(m)
        for (r, c) in m:
            g[r][c] = 0
        g = gravity(g, w, h)


def solve(g, a, b):
    best = None  # (chain, erased, -id)
    rows = []
    for cand in range(22):
        p = place(g, cand, a, b)
        if p is None:
            rows.append(None)
            continue
        ch, er = evaluate(p)
        rows.append((ch, er))
        key = (ch, er, -cand)
        if best is None or key > best:
            best = key
    return best[2] * -1, best[0], best[1], rows


# ---------- board generators ----------
def rand_stable_board(rng, fill, w=W, h=H):
    """Random gravity-stable board with no removable group; fill = target avg height fraction."""
    g = [[0] * w for _ in range(h)]
    heights = [min(h, max(0, int(rng.gauss(fill * h, 2)))) for _ in range(w)]
    for c in range(w):
        for r in range(heights[c]):
            opts = [1, 2, 3, 4]
            rng.shuffle(opts)
            for col in opts:
                g[r][c] = col
                if not find_groups(g, w, h):
                    break
            else:
                g[r][c] = 0
                break
        # keep column contiguous (gravity-stable) -- break above leaves zeros on top only
    return g


def has_legal(g):
    return any(place(g, k, 1, 2) is not None for k in range(22))


def make_boards(seed, n):
    rng = random.Random(seed)
    out = []
    # 1) hill-climb for long chains
    def score(g, a, b):
        return solve(g, a, b)[1:3]
    while len(out) < n:
        mode = len(out) % 4
        fill = [0.25, 0.5, 0.7, 0.9][mode]
        g = rand_stable_board(rng, fill)
        if not has_legal(g):
            continue
        a, b = rng.randint(1, 4), rng.randint(1, 4)
        if mode >= 2:
            # mutate to raise chain length
            cur = score(g, a, b)
            for _ in range(150):
                r2, c2 = rng.randrange(H), rng.randrange(W)
                if g[r2][c2] == 0:
                    continue
                old = g[r2][c2]
                g[r2][c2] = rng.randint(1, 4)
                if find_groups(g, W, H) or not has_legal(g):
                    g[r2][c2] = old
                    continue
                s = score(g, a, b)
                if s >= cur:
                    cur = s
                else:
                    g[r2][c2] = old
        out.append((g, a, b))
    return out


if __name__ == "__main__":
    # sanity self-checks against spec facts
    g = [[0] * W for _ in range(H)]
    assert find_groups(g, W, H) == set()
    print("golden ok")
