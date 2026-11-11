import type { Id, World, Item } from "./model.ts";
type Index = {
  containers: Record<Id, readonly Id[]>;
  locations: Record<Id, Id | undefined>;
  dirty: Set<Id>;
  depth: number;
  shared: boolean;
};
const caches = new WeakMap<World["items"], Index>();
const flatten = <T>(source: Record<string, T>): Record<string, T> => {
  const out = Object.create(null) as Record<string, T>;
  for (const k in source) out[k] = source[k];
  return out;
};
function writable(index: Index) {
  if (index.depth > 24) {
    index.containers = flatten(index.containers);
    index.locations = flatten(index.locations);
    index.depth = 0;
    index.shared = false;
  } else if (index.shared) {
    index.containers = Object.create(index.containers);
    index.locations = Object.create(index.locations);
    index.depth++;
    index.shared = false;
  }
}
function flush(items: World["items"], index: Index) {
  if (!index.dirty.size) return;
  writable(index);
  for (const id of index.dirty) {
    const old = index.locations[id],
      next = items[id]?.container;
    if (old === next) continue;
    if (old)
      index.containers[old] = (index.containers[old] ?? []).filter(
        (x) => x !== id,
      );
    if (next) index.containers[next] = [...(index.containers[next] ?? []), id];
    index.locations[id] = next;
  }
  index.dirty.clear();
}
function get(items: World["items"]): Index {
  let index = caches.get(items);
  if (index) {
    flush(items, index);
    return index;
  }
  index = {
    containers: Object.create(null),
    locations: Object.create(null),
    dirty: new Set(),
    depth: 0,
    shared: false,
  };
  for (const i of Object.values(items)) {
    index.containers[i.container] ??= [] as Id[];
    (index.containers[i.container] as Id[]).push(i.id);
    index.locations[i.id] = i.container;
  }
  caches.set(items, index);
  return index;
}
/** Called only by the copy-on-write draft. Derived IDs never become persistence truth. */
export function forkItemIndex(
  before: World["items"],
  after: World["items"],
): void {
  const parent = caches.get(before);
  if (!parent) return;
  flush(before, parent);
  parent.shared = true;
  caches.set(after, {
    containers: Object.create(parent.containers),
    locations: Object.create(parent.locations),
    dirty: new Set(),
    depth: parent.depth + 1,
    shared: false,
  });
}
export function dirtyItem(items: World["items"], id: Id): void {
  caches.get(items)?.dirty.add(id);
}
export function indexedItems(items: World["items"], container: Id): Item[] {
  return (get(items).containers[container] ?? [])
    .map((id) => items[id])
    .filter(
      (i): i is Item => !!i && i.container === container && i.quantity > 0,
    );
}
