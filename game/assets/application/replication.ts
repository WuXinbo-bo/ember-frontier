import type { View } from "./projection.ts";

const collections = [
  "actors",
  "tiles",
  "buildings",
  "containers",
  "items",
  "jobs",
  "tasks",
  "companions",
  "resources",
  "vehicles",
  "events",
] as const;
type Collection = (typeof collections)[number];
type Entry = { id?: string; x?: number; y?: number };
export interface ViewDelta {
  worldId: string;
  base: number;
  next: number;
  scalars: Partial<Omit<View, Collection>>;
  collections: Partial<
    Record<Collection, { upsert: unknown[]; remove: string[] }>
  >;
}
const key = (v: Entry) => v.id ?? `${v.x},${v.y}`;
const same = (a: unknown, b: unknown) =>
  JSON.stringify(a) === JSON.stringify(b);
/** Deltas are produced only from already-filtered per-player projections. */
export function diffView(before: View, after: View): ViewDelta {
  if (before.worldId !== after.worldId) throw new Error("DifferentWorld");
  const delta: ViewDelta = {
    worldId: after.worldId,
    base: before.seq,
    next: after.seq,
    scalars: {},
    collections: {},
  };
  for (const name of Object.keys(after) as (keyof View)[]) {
    if ((collections as readonly string[]).includes(name)) {
      const field = name as Collection;
      const previous = new Map(
        (before[field] as Entry[]).map((v) => [key(v), v]),
      );
      const now = new Map((after[field] as Entry[]).map((v) => [key(v), v]));
      const upsert = [...now]
        .filter(([id, v]) => !same(previous.get(id), v))
        .map(([, v]) => v);
      const remove = [...previous.keys()].filter((id) => !now.has(id));
      if (upsert.length || remove.length)
        delta.collections[field] = { upsert, remove };
    } else if (!same(before[name], after[name]))
      (delta.scalars as Record<string, unknown>)[name] = after[name];
  }
  return delta;
}
export function applyViewDelta(base: View, delta: ViewDelta): View {
  if (
    base.worldId !== delta.worldId ||
    base.seq !== delta.base ||
    delta.next < delta.base
  )
    throw new Error("ProjectionBaselineMismatch");
  const next = { ...base, ...delta.scalars, seq: delta.next };
  for (const field of collections) {
    const patch = delta.collections[field];
    if (!patch) continue;
    const map = new Map((base[field] as Entry[]).map((v) => [key(v), v]));
    patch.remove.forEach((id) => map.delete(id));
    for (const item of patch.upsert as Entry[]) map.set(key(item), item);
    (next as unknown as Record<string, unknown>)[field] = [...map.values()];
  }
  return next;
}
/** Explicit client acknowledgements; missing/evicted baselines always produce a full snapshot. */
export class ProjectionStream {
  private history = new Map<number, View>();
  private acknowledged?: number;
  acknowledge(worldId: string, seq: number) {
    const v = this.history.get(seq);
    if (v?.worldId === worldId && seq >= (this.acknowledged ?? -1))
      this.acknowledged = seq;
  }
  reset() {
    this.acknowledged = undefined;
    this.history.clear();
  }
  packet(view: View, forceFull = false): { view?: View; delta?: ViewDelta } {
    const base =
      this.acknowledged === undefined
        ? undefined
        : this.history.get(this.acknowledged);
    this.history.set(view.seq, view);
    for (const seq of [...this.history.keys()].slice(0, -16))
      this.history.delete(seq);
    if (forceFull || !base || base.worldId !== view.worldId) return { view };
    return { delta: diffView(base, view) };
  }
}
