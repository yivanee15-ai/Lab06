from golden import *
import heapq
bs = make_boards(20260101, 600)
pats = []
for g, a, b in bs:
    _, _, _, rows = solve(g, a, b)
    L = [r for r in rows if r]
    pats.append(([r[0] for r in L if r[0] >= 1], len(L)))

def sched(chains, k, s, issue_gap=1):
    """k contexts, s pipeline stages per round, 1 SIP round issued per cycle. returns cycle when last round result leaves."""
    # each candidate needs c+1 rounds; the last (empty) round detects the end.
    todo = [c + 1 for c in chains]
    ctx = []                     # (next_ready_time, rounds_left)
    t = 0; last = 0
    free_slots = k
    ready = []                   # heap of (ready_time, rounds_left)
    pending = list(todo)
    busy_cycle = set()
    # event loop by cycle
    active = []                  # [ready_time, rounds_left]
    while pending or active:
        # issue new candidates into free contexts
        while pending and len(active) < k:
            active.append([t, pending.pop(0)])
        # SIP slot this cycle: pick one ready context
        cand = [x for x in active if x[0] <= t]
        if cand:
            x = cand[0]
            x[1] -= 1
            x[0] = t + s
            last = t + s
            if x[1] == 0: active.remove(x)
        t += 1
    return last

for (k, s) in [(1,1),(2,2),(3,3),(4,2),(4,3),(4,4),(6,2),(6,3),(8,2)]:
    tot = sum(sched(c, k, s) for c, _ in pats) / len(pats)
    print(f"contexts={k} stages={s}: avg cycles to finish positives = {tot:.2f}")
print("avg positives:", sum(len(c) for c,_ in pats)/len(pats))
