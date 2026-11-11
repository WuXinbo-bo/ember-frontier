import {
  type Vec,
  type World,
  type Id,
  TILE,
  tileKey,
  distance,
} from "./model.ts";
import { Draft } from "./transaction.ts";
import { tileAt, buildingAt } from "./terrain.ts";
import { nearbyMembers } from "./spatial.ts";

/** Exact, bounded shortest acoustic paths. Visual/audio settings never enter this calculation. */
export function soundField(
  w: World,
  source: Vec,
  budget: number,
): Map<string, number> {
  const sx = Math.floor(source.x / TILE),
    sy = Math.floor(source.y / TILE),
    dist = new Map<string, number>([[`${sx},${sy}`, 0]]);
  const buckets: Array<Array<[number, number]>> = Array.from(
    { length: budget + 1 },
    () => [],
  );
  buckets[0].push([sx, sy]);
  for (let cost = 0; cost <= budget; cost++)
    for (const [x, y] of buckets[cost]) {
      if (dist.get(`${x},${y}`) !== cost) continue;
      for (const [dx, dy] of [
        [1, 0],
        [-1, 0],
        [0, 1],
        [0, -1],
      ]) {
        const nx = x + dx,
          ny = y + dy,
          t = tileAt(w, nx, ny);
        if (t.blocked) continue;
        const wall = buildingAt(w, { x: nx * TILE + 128, y: ny * TILE + 128 });
        const next =
            cost +
            1 +
            (wall &&
            wall.progress === 100 &&
            ["wall", "door"].includes(wall.definition) &&
            !wall.open
              ? 5
              : 0),
          key = `${nx},${ny}`;
        if (next > budget || next >= (dist.get(key) ?? Infinity)) continue;
        dist.set(key, next);
        buckets[next].push([nx, ny]);
      }
    }
  return dist;
}
export function receiverSet(w: World, source: Vec, budget: number): Set<Id> {
  const field = soundField(w, source, budget),
    ids = new Set<Id>();
  for (const a of Object.values(w.actors))
    if (
      a.life === "Alive" &&
      distance(a.position, source) <= budget + 1 &&
      field.has(tileKey(a.position))
    )
      ids.add(a.id);
  for (const m of nearbyMembers(w, source, budget + 1))
    if (field.has(tileKey(m.position))) ids.add(m.id);
  return ids;
}
export function emitSound(
  d: Draft,
  source: Vec,
  budget: number,
  sourceId?: Id,
): void {
  if (budget <= 0) return;
  const field = soundField(d.world, source, budget),
    eventId = d.id(),
    heard = { position: { ...source }, tick: d.header.tick, eventId };
  for (const a of Object.values(d.world.actors))
    if (
      a.life === "Alive" &&
      a.id !== sourceId &&
      distance(a.position, source) <= budget + 1 &&
      field.has(tileKey(a.position))
    ) {
      const edit = d.edit("actors", a.id);
      edit.heard = heard;
      if (edit.profile) {
        edit.profile.beliefs = edit.profile.beliefs.filter(
          (b) => b.kind !== "danger",
        );
        edit.profile.beliefs.push({
          id: eventId,
          kind: "danger",
          position: { ...source },
          tick: d.header.tick,
          source: sourceId ?? "environment",
          confidence: 100,
        });
        edit.profile.nextThink = Math.min(
          edit.profile.nextThink,
          d.header.tick + 1,
        );
      }
      edit.pressure.sound = (edit.pressure.sound ?? 0) + 1;
    }
  for (const m of nearbyMembers(d.world, source, budget + 1))
    if (field.has(tileKey(m.position)))
      d.edit("cohorts", m.cohort).heard[String(m.index)] = heard;
  d.events.push({
    id: eventId,
    tick: d.header.tick,
    kind: "Sound",
    actor: sourceId,
    text: `声响传播 ${budget} 格`,
    position: { ...source },
  });
}
