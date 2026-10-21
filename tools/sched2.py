from probe2 import *
from sched_study import sched
import sys
bs = make_boards(20260101, 600)
acc = {"none": 0, "probe4": 0, "exact": 0}
n = 0
for g, a, b in bs:
    _, _, _, rows = solve(g, a, b)
    chains_all = [r[0] for r in rows if r]
    pos = [c for c in chains_all if c >= 1]
    fl, npb = flags(g, a, b)
    chains_f = [rows[k][0] for k in sorted(fl)]
    # jobs: probes are 1-round jobs issued first
    acc["none"]   += sched(chains_all, 2, 2)
    acc["probe4"] += sched([0]*npb + chains_f, 2, 2)
    acc["exact"]  += sched(pos, 2, 2) + 2      # +2: local filter latency
    n += 1
for k, v in acc.items(): print(f"{k:8s}: avg SIP-pipeline cycles {v/n:.2f}")
