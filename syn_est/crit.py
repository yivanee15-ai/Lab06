#!/usr/bin/env python3
"""Longest path of an abc-mapped blif using generic.genlib delays. usage: crit.py mapped.blif [n_show]"""
import re, sys, os
D = os.path.dirname(os.path.abspath(__file__))
delay = {}
for l in open(D + '/generic.genlib'):
    m = re.match(r'GATE (\S+) \S+ .*', l)
    if m: cur = m.group(1)
    m = re.match(r'PIN \* \S+ \S+ \S+ ([0-9.]+)', l)
    if m: delay[cur] = float(m.group(1))
gates = {}   # out -> (type, [ins])
pis = set()
txt = open(sys.argv[1]).read().replace('\\\n', ' ')
for l in txt.split('\n'):
    t = l.split()
    if not t: continue
    if t[0] == '.inputs': pis.update(t[1:])
    if t[0] == '.gate':
        pins = dict(p.split('=') for p in t[2:])
        out = pins.pop('O')
        gates[out] = (t[1], list(pins.values()))
arr, pred = {}, {}
sys.setrecursionlimit(100000)
def at(n):
    if n in arr: return arr[n]
    if n not in gates:
        arr[n] = 0.0; return 0.0
    g, ins = gates[n]
    best, bp = 0.0, None
    for i in ins:
        a = at(i)
        if a >= best: best, bp = a, i
    arr[n] = best + delay.get(g, 0.1); pred[n] = bp
    return arr[n]
sinks = re.findall(r'\.outputs (.*)', txt)
outs = []
for l in txt.split('\n'):
    if l.startswith('.outputs'): outs += l.split()[1:]
worst = max(outs, key=lambda o: at(o))
lat = []
if len(sys.argv) > 3:
    for l in open(sys.argv[3]):
        if l.startswith('.latch'): lat.append(l.split()[2])
    ins_orig = [l for l in open(sys.argv[3]) if l.startswith('.outputs')]
    nreal = len(ins_orig[0].split()[1:]) if ins_orig else 0
    ix = outs.index(worst) - nreal
    if 0 <= ix < len(lat): print("endpoint flop:", lat[ix])
    # list top-10 slowest endpoints by flop name
    import re as _re
    stem = {}
    for o in outs:
        j = outs.index(o) - nreal
        nm = lat[j] if 0 <= j < len(lat) else o
        k = _re.sub(r'\[.*', '', nm)
        stem[k] = max(stem.get(k, 0), at(o))
    for k, v in sorted(stem.items(), key=lambda x: -x[1])[:14]:
        print("  %.2f  %s" % (v, k))
print("worst endpoint:", worst, "delay %.2f" % arr[worst])
path = []; n = worst
while n is not None:
    path.append((n, gates[n][0] if n in gates else 'PI', arr[n])); n = pred.get(n)
path.reverse()
show = int(sys.argv[2]) if len(sys.argv) > 2 else 12
print("start:", path[0][0]); 
for p in path[-show:]: print("  %-60s %-6s %.2f" % p)
