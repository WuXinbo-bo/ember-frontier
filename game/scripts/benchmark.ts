import { performance } from "node:perf_hooks";
import { cpus, totalmem, platform, arch, release } from "node:os";
import { mkdir, writeFile } from "node:fs/promises";
import {
  createWorld,
  beginDay,
  placePending,
  memberId,
  slotPosition,
} from "../assets/simulation/population.ts";
import { Draft } from "../assets/simulation/transaction.ts";
import { assertWorld } from "../assets/simulation/invariants.ts";
import { soundField, receiverSet } from "../assets/simulation/acoustics.ts";
import { project } from "../assets/application/projection.ts";
import { diffView } from "../assets/application/replication.ts";
import { advance } from "../assets/simulation/rules.ts";
import { TILE } from "../assets/simulation/model.ts";
const summarize = (values: number[]) => {
  const v = [...values].sort((a, b) => a - b);
  return {
    n: v.length,
    p50: v[Math.floor(v.length * 0.5)],
    p95: v[Math.min(v.length - 1, Math.floor(v.length * 0.95))],
    max: v.at(-1),
  };
};
const t = performance.now();
let w = createWorld("population-benchmark", { size: 2048, biome: "inland" });
const initialMs = performance.now() - t,
  snapshots: unknown[] = [],
  placements: number[] = [];
for (let day = 1; day <= 100; day++) {
  const start = performance.now(),
    d = new Draft(w);
  d.header.tick = d.header.ticksPerDay * day;
  beginDay(d);
  w = d.finish().world;
  while (w.header.phase === "DayBoundary") {
    const d = new Draft(w);
    placePending(d, 1000);
    w = d.finish().world;
  }
  if (w.header.phase !== "Running")
    throw new Error(`CapacityBlockedAtDay:${day}`);
  placements.push(performance.now() - start);
  if (day === 30 || day === 100) {
    const auditAt = performance.now();
    assertWorld(w, true);
    snapshots.push({
      day,
      npc: w.header.npc.alive,
      infected: w.header.infected.alive,
      cohorts: Object.keys(w.cohorts).length,
      auditMs: performance.now() - auditAt,
      jsonBytes: Buffer.byteLength(JSON.stringify(w)),
      heapUsed: process.memoryUsage().heapUsed,
    });
  }
}
const self = w.actors[w.bindings["seat-1"].actor],
  soundAt = performance.now(),
  heard = receiverSet(w, self.position, 12),
  soundMs = performance.now() - soundAt,
  field = soundField(w, self.position, 12),
  reference = new Set<string>();
for (const a of Object.values(w.actors))
  if (
    a.life === "Alive" &&
    field.has(
      `${Math.floor(a.position.x / TILE)},${Math.floor(a.position.y / TILE)}`,
    )
  )
    reference.add(a.id);
for (const c of Object.values(w.cohorts)) {
  const removed = new Set(c.removed);
  c.slots.forEach((slot, i) => {
    const p = slotPosition(w, slot);
    if (
      !removed.has(i) &&
      field.has(`${Math.floor(p.x / TILE)},${Math.floor(p.y / TILE)}`)
    )
      reference.add(memberId(c.first, i));
  });
}
if (
  heard.size !== reference.size ||
  [...heard].some((id) => !reference.has(id))
)
  throw new Error("AcousticReferenceMismatch");
const tickTimes: number[] = [],
  projectionTimes: number[] = [];
let before = project(w, "local", "session-only"),
  fullBytes = 0,
  deltaBytes = 0;
for (let n = 0; n < 20; n++) {
  const a = performance.now();
  w = advance(w)!.world;
  tickTimes.push(performance.now() - a);
  const b = performance.now(),
    after = project(w, "local", "session-only");
  projectionTimes.push(performance.now() - b);
  fullBytes += Buffer.byteLength(JSON.stringify(after));
  deltaBytes += Buffer.byteLength(JSON.stringify(diffView(before, after)));
  before = after;
}
const report = {
  at: new Date().toISOString(),
  scope:
    "Population ledger/placement at 30 and 100 completed days, zero deaths. 20 representative reducer ticks only: NOT a 100-day gameplay or phone/FPS benchmark.",
  environment: {
    node: process.version,
    platform: platform(),
    arch: arch(),
    release: release(),
    cpu: cpus()[0].model,
    logicalCores: cpus().length,
    totalMemory: totalmem(),
  },
  initialMs,
  populationSnapshots: snapshots,
  placementMs: summarize(placements),
  simulationTickMs: summarize(tickTimes),
  projectionMs: summarize(projectionTimes),
  acoustics: {
    radius: 12,
    receiverCount: heard.size,
    referenceCount: reference.size,
    equal: true,
    soundMs,
  },
  replication: {
    samples: 20,
    fullBytes,
    deltaBytes,
    reduction: 1 - deltaBytes / fullBytes,
  },
  peakProcess: process.memoryUsage(),
};
await mkdir("artifacts/architecture", { recursive: true });
await writeFile(
  "artifacts/architecture/benchmark.json",
  JSON.stringify(report, null, 2),
);
console.log(JSON.stringify(report, null, 2));
