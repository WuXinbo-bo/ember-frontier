import { type World, type Id, type Vec, TILE, distance } from "./model.ts";
import { memberId, slotPosition } from "./population.ts";
type Index = { groups: Map<string, Map<Id, number[]>> };
let indexes = new WeakMap<World["cohorts"], Index>();
let slotIndexes = new WeakMap<number[], Map<string, number[]>>();
/** A cache is keyed by immutable data, never worldId: rolled-back candidates cannot poison recovery. */
export function cohortIndex(w: World): Index {
  const prior = indexes.get(w.cohorts);
  if (prior) return prior;
  const groups = new Map<string, Map<Id, number[]>>();
  for (const c of Object.values(w.cohorts)) {
    let cells = slotIndexes.get(c.slots);
    if (!cells) {
      cells = new Map();
      c.slots.forEach((slot, i) => {
        const key = `${Math.floor((slot % w.header.size) / 16)},${Math.floor(Math.floor(slot / w.header.size) / 16)}`;
        let indices = cells!.get(key);
        if (!indices) {
          indices = [];
          cells!.set(key, indices);
        }
        indices.push(i);
      });
      slotIndexes.set(c.slots, cells);
    }
    for (const [key, indices] of cells) {
      let g = groups.get(key);
      if (!g) {
        g = new Map();
        groups.set(key, g);
      }
      g.set(c.id, indices);
    }
  }
  const index = { groups };
  indexes.set(w.cohorts, index);
  return index;
}
export function nearbyMembers(
  w: World,
  p: Vec,
  radius: number,
): { cohort: Id; index: number; id: Id; position: Vec }[] {
  const idx = cohortIndex(w),
    out: { cohort: Id; index: number; id: Id; position: Vec }[] = [];
  const x = p.x / TILE,
    y = p.y / TILE;
  for (
    let cy = Math.floor((y - radius) / 16);
    cy <= Math.floor((y + radius) / 16);
    cy++
  )
    for (
      let cx = Math.floor((x - radius) / 16);
      cx <= Math.floor((x + radius) / 16);
      cx++
    )
      for (const [id, indices] of idx.groups.get(`${cx},${cy}`) ?? []) {
        const c = w.cohorts[id];
        if (!c) continue;
        const removed = new Set(c.removed);
        for (const i of indices)
          if (!removed.has(i)) {
            const pos = slotPosition(w, c.slots[i]);
            if (distance(pos, p) <= radius)
              out.push({
                cohort: id,
                index: i,
                id: memberId(c.first, i),
                position: pos,
              });
          }
      }
  return out;
}
export function clearSpatialCaches() {
  indexes = new WeakMap();
  slotIndexes = new WeakMap();
}
