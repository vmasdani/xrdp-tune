#!/usr/bin/env python3
# Hidden CPU steal check: spins on one vCPU and splits every stall into time the guest
# scheduler kept this process waiting and the rest, i.e. time the vCPU itself was not
# running because the host took it. Useful when top shows 0% steal.
# Run: taskset -c 0 python3 -I cpu-steal-check.py [seconds]    (default 5)
# Healthy host: "taken by the host" close to 0%. On 2026-10-13 this VPS showed 33-62%,
# with pauses of 190-350 ms.
import time, sys, os
def ss():
    a = open('/proc/self/schedstat').read().split(); return int(a[0]), int(a[1])
dur = float(sys.argv[1]) if len(sys.argv) > 1 else 5
cpus = sorted(os.sched_getaffinity(0))
c0, r0 = ss(); t0 = last = time.perf_counter(); gaps = []
while True:
    now = time.perf_counter()
    d = now - last
    if d > 0.0005: gaps.append(d)
    last = now
    if now - t0 > dur: break
c1, r1 = ss(); wall = now - t0
g = sum(gaps); rd = min((r1 - r0) / 1e9, g); host = g - rd
pct = lambda x: 100 * x / wall

where = "vCPU %d" % cpus[0] if len(cpus) == 1 else "not pinned, may move between vCPUs %s" % cpus
print("CPU stall test: %s, %.1f s busy loop" % (where, wall))
print()
print("  Loop actually ran                  %5.2f s  %3.0f%%" % (wall - g, pct(wall - g)))
print("  Loop stalled (pauses > 0.5 ms)     %5.2f s  %3.0f%%  in %d pauses" % (g, pct(g), len(gaps)))
print("    waiting behind other processes  %5.2f s  %3.0f%%  this VPS's own load" % (rd, pct(rd)))
print("    vCPU taken by the host          %5.2f s  %3.0f%%  hidden steal, top shows 0%%" % (host, pct(host)))
print()
bins = [(0.0005, 0.005, "0.5-5 ms"), (0.005, 0.02, "5-20 ms"), (0.02, 0.1, "20-100 ms"), (0.1, 1e9, "over 100 ms")]
print("  Pause sizes     " + "   ".join("%s: %d" % (n, sum(lo < x <= hi for x in gaps)) for lo, hi, n in bins))
print("  Longest pauses  " + (", ".join("%d ms" % round(x * 1000) for x in sorted(gaps)[-3:][::-1]) or "none"))
print()

if pct(host) < 5:
    verdict = "OK. The host gives this vCPU nearly all of its time."
elif pct(host) < 20:
    verdict = "NOTICEABLE host contention. Expect occasional lag spikes."
else:
    verdict = "SEVERE host contention. The host takes %.0f%% of this vCPU, so the desktop and every process run slow. Ask the provider to move the VPS to a less loaded host." % pct(host)
print("Verdict: " + verdict)
if pct(rd) >= 20:
    print("Own load is high too (%.0f%% waiting behind other processes). Close busy programs." % pct(rd))
if len(cpus) > 1:
    print("For a clean per-vCPU number, pin it: taskset -c 0 python3 -I %s" % sys.argv[0])
