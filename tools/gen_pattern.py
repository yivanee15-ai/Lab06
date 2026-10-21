import os, random, sys
from golden import *

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "01_RTL", "dat")
os.makedirs(OUT, exist_ok=True)
NTOP = int(sys.argv[1]) if len(sys.argv) > 1 else 600

def crafted():
    """Hand-made corner cases (grid[row_from_bottom][col])."""
    cs = []
    def empty(): return [[0]*W for _ in range(H)]
    # 1: empty board
    cs.append((empty(), 1, 2))
    # 2: simple: three 1s in col0 + A=1 on top -> 1-chain, 4 erased (spec example style)
    g = empty(); g[0][0]=g[1][0]=g[2][0]=1
    cs.append((g, 1, 2))
    # 3: classic 2-chain: col0 = 2,2,2? build staircase
    g = empty()
    g[0][0]=1; g[0][1]=1; g[0][2]=1          # row of 1s at bottom (need 4th)
    g[1][3]=2; g[1][4]=2                      # 2 2 on top of something
    g[0][3]=3; g[0][4]=3
    cs.append((g, 1, 2))
    # 4: full board of a checker-free pattern -> only a few legal moves
    g = empty()
    for c in range(W):
        for r in range(H):
            g[r][c] = ((c + r) % 2) * 1 + 1 + (( (c // 1) + (r // 2)) % 2) * 2 % 3
    # force no group
    for c in range(W):
        for r in range(H):
            for col in (1,2,3,4):
                g[r][c] = col
                if not find_groups(g, W, H): break
    cs.append((g, 3, 4))
    # 5: columns 0 full, col1 has 11 (vertical illegal there), horizontal ok
    g = empty()
    for r in range(H):
        for col in (1,2,3,4):
            g[r][0] = col
            if not find_groups(g, W, H): break
    for r in range(11):
        for col in (4,3,2,1):
            g[r][1] = col
            if not find_groups(g, W, H): break
    cs.append((g, 2, 3))
    # 6: diagonal-only adjacency must NOT erase
    g = empty(); g[0][0]=1; g[0][1]=3; g[1][1]=1; g[0][2]=3; g[1][2]=4; g[2][2]=1
    cs.append((g, 1, 3))
    return [c for c in cs if not find_groups(c[0], W, H) and has_legal(c[0])]

def main():
    boards = crafted() + make_boards(20260101, NTOP)
    with open(os.path.join(OUT, "top_in.dat"), "w") as fi, open(os.path.join(OUT, "top_gold.dat"), "w") as fo:
        stats = {}
        for g, a, b in boards:
            assert not find_groups(g, W, H), "input board must have no removable group"
            assert g == gravity(g, W, H), "input board must be gravity-stable"
            cand, ch, er, _ = solve(g, a, b)
            fi.write("%x\n%x\n" % (a, b))
            for v in grid_to_flat(g, W, H):
                fi.write("%x\n" % v)
            fo.write("%02x\n%02x\n%02x\n" % (cand, ch, er))
            stats[ch] = stats.get(ch, 0) + 1
    print("TOP patterns:", len(boards), "chain histogram:", dict(sorted(stats.items())))

    # Soft-IP patterns: arbitrary boards (random, floating cells allowed, dense colours -> many groups)
    rng = random.Random(7)
    for (w, h) in [(3,4),(4,6),(5,8),(6,10),(6,12),(8,12)]:
        n = w*h
        cnt, hist = 400, [0]*3
        with open(os.path.join(OUT, f"ip_{w}x{h}_in.dat"), "w") as fi, \
             open(os.path.join(OUT, f"ip_{w}x{h}_mask.dat"), "w") as fm, \
             open(os.path.join(OUT, f"ip_{w}x{h}_num.dat"), "w") as fn:
            for t in range(cnt):
                ncol = rng.choice([2, 2, 3, 4])
                dens = rng.choice([0.5, 0.8, 1.0])
                flat = [rng.randint(1, ncol) if rng.random() < dens else 0 for _ in range(n)]
                if t == 0: flat = [0]*n
                if t == 1: flat = [1]*n
                g = flat_to_grid(flat, w, h)
                m = find_groups(g, w, h)
                mask = 0
                for (r, c) in m:
                    mask |= 1 << ((h-1-r)*w + c)
                bv = 0
                for i, v in enumerate(flat):
                    bv |= v << (3*i)
                fi.write("%x\n" % bv); fm.write("%x\n" % mask); fn.write("%x\n" % len(m))
        print(f"IP {w}x{h}: {cnt} vectors")
    open(os.path.join(OUT, "ntop.txt"), "w").write(str(len(boards)))

main()
