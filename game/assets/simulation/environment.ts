import {
  type World,
  type Vec,
  type Resource,
  type Actor,
  TILE,
  distance,
  requireRule,
} from "./model.ts";
import { hash } from "./determinism.ts";
import { tileAt } from "./terrain.ts";
import { Draft } from "./transaction.ts";
import { addItem, weight } from "./inventory.ts";
import { ITEMS, SKILLS } from "../content/catalog.ts";
const deposits = [
  ["wood", 32],
  ["stone", 24],
  ["herb", 12],
  ["food", 8],
  ["scrap", 20],
  ["cloth", 12],
  ["dirty_water", 24],
  ["seed", 12],
  ["reagent", 10],
  ["sample", 8],
  ["fuel", 10],
  ["book_survival", 1],
  ["book_tech", 1],
  ["book_bio", 1],
  ["book_aug", 1],
  ...Object.keys(SKILLS).map((id) => [`book_skill_${id}`, 1] as const),
] as const;
/** Finite deterministic deposits exist independently of rendering and chunk loading. */
export function resourceAt(
  w: World,
  x: number,
  y: number,
): Resource | undefined {
  if (x < 0 || y < 0 || x >= w.header.size || y >= w.header.size) return;
  const id = `deposit/${x}/${y}`,
    saved = w.resources[id];
  if (saved) return saved.remaining > 0 ? saved : undefined;
  const h = hash(`${w.header.seed}/deposit/${x}/${y}`);
  if (h % 43 !== 0) return;
  const tile = tileAt(w, x, y);
  if (tile.blocked || tile.water > 40) return;
  const [definition, remaining] = deposits[(h >>> 8) % deposits.length];
  return {
    id,
    definition,
    position: { x: x * TILE + 128, y: y * TILE + 128 },
    remaining,
    revision: 0,
    traits: {},
    pressure: 0,
  };
}
export function nearbyResources(w: World, p: Vec, radius = 10): Resource[] {
  const result: Resource[] = [];
  const cx = Math.floor(p.x / TILE),
    cy = Math.floor(p.y / TILE);
  for (let y = cy - radius; y <= cy + radius; y++)
    for (let x = cx - radius; x <= cx + radius; x++) {
      const r = resourceAt(w, x, y);
      if (r && distance(r.position, p) <= radius) result.push(r);
    }
  return result;
}
export function gather(d: Draft, a: Actor, x: number, y: number) {
  requireRule(
    Number.isSafeInteger(x) && Number.isSafeInteger(y),
    "InvalidPosition",
  );
  const r = resourceAt(d.world, x, y);
  requireRule(r, "ResourceDepleted");
  requireRule(distance(a.position, r.position) <= 2.5, "OutOfRange");
  requireRule(a.readyAt <= d.header.tick, "Cooldown");
  requireRule(
    weight(d.world, a.inventory) + ITEMS[r.definition].mass <=
      d.world.containers[a.inventory].capacity,
    "OutputCapacity",
  );
  d.put("resources", r.id, {
    ...r,
    remaining: r.remaining - 1,
    revision: r.revision + 1,
  });
  addItem(d, a.inventory, r.definition, 1, `deposit/${r.id}`);
  a.readyAt = d.header.tick + 30;
  a.fatigue = Math.min(100, a.fatigue + 1);
  const skill =
    r.definition === "wood"
      ? "logging"
      : r.definition === "stone"
        ? "mining"
        : r.definition === "herb"
          ? "herbalism"
          : "gathering";
  a.skills[skill] = Math.min(10000, a.skills[skill] + 2);
  d.event(
    "Gather",
    `采集 ${ITEMS[r.definition].name}，此资源点剩余 ${r.remaining - 1}`,
    a.id,
  );
}
