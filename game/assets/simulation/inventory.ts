import {
  type World,
  type Id,
  type Item,
  type Vec,
  requireRule,
  distance,
} from "./model.ts";
import { indexedItems } from "./inventory-index.ts";
import { Draft } from "./transaction.ts";
import { ITEMS } from "../content/catalog.ts";

export const inventoryItems = (w: World, container: Id): Item[] =>
  indexedItems(w.items, container);
export const countItem = (w: World, container: Id, definition: string) =>
  inventoryItems(w, container)
    .filter((i) => i.definition === definition)
    .reduce((a, i) => a + i.quantity, 0);
export const weight = (w: World, container: Id) =>
  inventoryItems(w, container).reduce(
    (a, i) => a + ITEMS[i.definition].mass * i.quantity,
    0,
  );
export function containerPosition(w: World, id: Id): Vec {
  const c = w.containers[id];
  requireRule(c, "ContainerMissing");
  return c.actor ? w.actors[c.actor].position : c.position;
}
export function newContainer(
  d: Draft,
  position: Vec,
  options: { actor?: Id; owner?: Id; capacity?: number } = {},
): Id {
  const id = d.id();
  d.put("containers", id, {
    id,
    position: { ...position },
    capacity: 50000,
    state: "normal",
    revision: 0,
    ...options,
  });
  return id;
}
export function addItem(
  d: Draft,
  container: Id,
  definition: string,
  quantity: number,
  provenance: string,
): Id {
  requireRule(
    ITEMS[definition] && Number.isSafeInteger(quantity) && quantity > 0,
    "InvalidItem",
  );
  requireRule(d.world.containers[container], "ContainerMissing");
  const id = d.id();
  d.put("items", id, {
    id,
    definition,
    quantity,
    container,
    condition: 100,
    revision: 0,
    provenance,
  });
  d.edit("containers", container).revision++;
  return id;
}
export function available(w: World, item: Item, ownJob?: Id): number {
  return (
    item.quantity -
    Object.values(w.reservations)
      .filter(
        (r) =>
          r.resource === item.id &&
          r.job !== ownJob &&
          r.expires > w.header.tick,
      )
      .reduce((s, r) => s + r.amount, 0)
  );
}
export function take(
  d: Draft,
  container: Id,
  definition: string,
  quantity: number,
  ownJob?: Id,
): void {
  const items = inventoryItems(d.world, container).filter(
    (i) => i.definition === definition,
  );
  requireRule(
    items.reduce((n, i) => n + available(d.world, i, ownJob), 0) >= quantity,
    "MissingMaterial",
  );
  let left = quantity;
  for (const original of items) {
    const n = Math.min(left, available(d.world, original, ownJob));
    if (n <= 0) continue;
    const i = d.edit("items", original.id);
    i.quantity -= n;
    i.revision++;
    left -= n;
    if (!left) break;
  }
  d.edit("containers", container).revision++;
}
export function pay(
  d: Draft,
  container: Id,
  cost: Record<string, number>,
): void {
  for (const [item, n] of Object.entries(cost))
    requireRule(
      inventoryItems(d.world, container)
        .filter((i) => i.definition === item)
        .reduce((s, i) => s + available(d.world, i), 0) >= n,
      "MissingMaterial",
    );
  for (const [item, n] of Object.entries(cost)) take(d, container, item, n);
}
export function transfer(
  d: Draft,
  actorId: Id,
  itemId: Id,
  destination: Id,
  amount: number,
  taskId?: Id,
): void {
  const actor = d.world.actors[actorId],
    source = d.world.items[itemId],
    target = d.world.containers[destination];
  requireRule(source && target, "ItemMissing");
  requireRule(
    Number.isSafeInteger(amount) &&
      amount > 0 &&
      amount <= available(d.world, source),
    "InvalidQuantity",
  );
  const from = d.world.containers[source.container];
  requireRule(
    !from.owner || from.owner === actorId || from.owner === actor.faction,
    "PermissionDenied",
  );
  const task = taskId ? d.world.tasks[taskId] : undefined;
  const delivery =
    task &&
    task.assignee === actorId &&
    task.destination === destination &&
    task.target === source.definition &&
    ["Accepted", "Executing"].includes(task.state);
  requireRule(
    from.state === "normal" && target.state === "normal",
    "ContainerInaccessible",
  );
  requireRule(
    delivery ||
      !target.owner ||
      target.owner === actorId ||
      target.owner === actor.faction,
    "PermissionDenied",
  );
  requireRule(
    distance(actor.position, containerPosition(d.world, source.container)) <=
      2.8 &&
      distance(actor.position, containerPosition(d.world, destination)) <= 2.8,
    "OutOfRange",
  );
  requireRule(
    weight(d.world, destination) + amount * ITEMS[source.definition].mass <=
      target.capacity,
    "CapacityExceeded",
  );
  requireRule(source.container !== destination, "SameContainer");
  const old = source.container;
  if (amount === source.quantity) {
    const i = d.edit("items", itemId);
    i.container = destination;
    i.revision++;
  } else {
    const i = d.edit("items", itemId);
    i.quantity -= amount;
    i.revision++;
    const id = addItem(
      d,
      destination,
      source.definition,
      amount,
      source.provenance,
    );
    d.edit("items", id).condition = source.condition;
  }
  d.edit("containers", old).revision++;
  d.edit("containers", destination).revision++;
  d.event(
    "ItemTransferred",
    `搬运 ${ITEMS[source.definition].name} ×${amount}`,
    actorId,
  );
}
