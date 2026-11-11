import { type World, requireRule } from "./model.ts";
import { ITEMS, SKILLS, BUILDINGS } from "../content/catalog.ts";
import { memberId } from "./population.ts";
import { controlBudget, controlUse } from "./rules.ts";

export function audit(w: World, deep = false): string[] {
  const errors: string[] = [];
  const check = (ok: unknown, message: string) => {
    if (!ok) errors.push(message);
  };
  check(
    Number.isSafeInteger(w.header.tick) && w.header.tick >= 0,
    "invalid world tick",
  );
  check(
    Number.isSafeInteger(w.header.seq) && w.header.seq >= 0,
    "invalid commit sequence",
  );
  const mass = new Map<string, number>();
  for (const [kind, p, initial, daily] of [
    ["npc", w.header.npc, 99, 100],
    ["infected", w.header.infected, 10000, 10000],
  ] as const) {
    check(
      p.alive === initial + daily * w.header.completedDays - p.deaths,
      `${kind}: population formula`,
    );
    check(p.alive === p.placed + p.pending, `${kind}: placement ledger`);
    check(
      Object.values(p).every((n) => Number.isSafeInteger(n) && n >= 0),
      `${kind}: invalid ledger`,
    );
  }
  const npcs = Object.values(w.actors).filter(
    (a) => a.kind === "npc" && a.life === "Alive",
  ).length;
  const infected =
    Object.values(w.actors).filter(
      (a) => a.kind === "infected" && a.life === "Alive",
    ).length +
    Object.values(w.cohorts).reduce(
      (n, c) => n + c.slots.length - c.removed.length,
      0,
    );
  check(npcs === w.header.npc.placed, "npc: represented count");
  check(infected === w.header.infected.placed, "infected: represented count");
  for (const a of Object.values(w.actors)) {
    check(
      Number.isFinite(a.position.x) && Number.isFinite(a.position.y),
      "invalid position",
    );
    check(
      a.hp >= 0 &&
        (a.kind === "infected" || a.kind === "animal" || a.hp <= 100),
      `${a.id}: human HP`,
    );
    check(
      a.life !== "Dead" || (a.hp === 0 && !!w.deaths[a.id]),
      `${a.id}: missing tombstone`,
    );
    check(!!w.containers[a.inventory], `${a.id}: missing inventory`);
    check(a.life !== "Alive" || a.hp > 0, `${a.id}: living body has no health`);
    if (a.mountedOn) {
      const mount = w.actors[a.mountedOn],
        vehicle = w.vehicles[a.mountedOn];
      check(
        mount?.life === "Alive" ||
          (vehicle && Object.values(vehicle.seats).includes(a.id)),
        `${a.id}: invalid mount`,
      );
    }
    if (a.kind === "player" || a.kind === "npc")
      check(
        Object.keys(a.skills).length === 33 &&
          Object.keys(SKILLS).every(
            (id) =>
              Number.isFinite(a.skills[id]) &&
              a.skills[id] >= 0 &&
              a.skills[id] <= 10000,
          ),
        `${a.id}: invalid skills`,
      );
    if (a.kind === "npc")
      check(
        !!a.profile && Object.keys(a.skills).length === 33,
        `${a.id}: incomplete profile`,
      );
  }
  for (const i of Object.values(w.items)) {
    check(!!w.containers[i.container], `${i.id}: orphan item`);
    mass.set(
      i.container,
      (mass.get(i.container) ?? 0) +
        (ITEMS[i.definition]?.mass ?? 0) * i.quantity,
    );
    check(
      !!ITEMS[i.definition] &&
        Number.isSafeInteger(i.quantity) &&
        i.quantity >= 0,
      `${i.id}: item quantity`,
    );
  }
  for (const c of Object.values(w.containers))
    check((mass.get(c.id) ?? 0) <= c.capacity, `${c.id}: capacity exceeded`);
  for (const r of Object.values(w.resources))
    check(
      Number.isSafeInteger(r.remaining) &&
        r.remaining >= 0 &&
        !!ITEMS[r.definition],
      `${r.id}: invalid finite resource`,
    );
  for (const v of Object.values(w.vehicles)) {
    check(
      !!w.containers[v.inventory] && v.fuel >= 0 && v.hp >= 0,
      `${v.id}: invalid vehicle`,
    );
    check(
      new Set(Object.values(v.seats)).size === Object.keys(v.seats).length,
      `${v.id}: duplicate rider`,
    );
    for (const id of Object.values(v.seats))
      check(
        w.actors[id]?.life === "Alive" && w.actors[id]?.mountedOn === v.id,
        `${v.id}: invalid occupant`,
      );
  }
  for (const b of Object.values(w.buildings))
    check(
      !!BUILDINGS[b.definition] &&
        !!w.containers[b.inventory] &&
        b.progress >= 0 &&
        b.progress <= 100,
      `${b.id}: invalid building`,
    );
  for (const b of Object.values(w.bindings)) {
    check(!!w.actors[b.actor], `${b.id}: orphan binding`);
    check(
      !b.dead || w.actors[b.actor]?.life === "Dead",
      `${b.id}: binding death mismatch`,
    );
  }
  check(Object.keys(w.bindings).length <= 4, "too many lifetime seats");
  check(
    new Set(Object.values(w.bindings).map((b) => b.player)).size ===
      Object.keys(w.bindings).length,
    "duplicate principal binding",
  );
  check(
    new Set(Object.values(w.bindings).map((b) => b.actor)).size ===
      Object.keys(w.bindings).length,
    "duplicate character binding",
  );
  for (const a of Object.values(w.actors))
    if (a.life === "Alive")
      check(controlUse(w, a.id) <= controlBudget(a), `${a.id}: control budget`);
  for (const c of Object.values(w.companions)) {
    check(!!w.actors[c.id], `${c.id}: missing companion body`);
    check(
      c.state !== "dead" || w.actors[c.id].life === "Dead",
      `${c.id}: companion death mismatch`,
    );
  }
  if (deep) {
    for (const a of Object.values(w.actors)) {
      const visited = new Set<string>();
      let id: string | undefined = a.id;
      while (id) {
        if (visited.has(id)) {
          check(false, `${a.id}: organization cycle`);
          break;
        }
        visited.add(id);
        id = w.actors[id]?.faction;
      }
    }
    const ids = new Set(Object.keys(w.actors));
    for (const c of Object.values(w.cohorts)) {
      const removed = new Set(c.removed);
      check(removed.size === c.removed.length, `${c.id}: duplicate extraction`);
      check(
        c.removed.every(
          (i) => Number.isSafeInteger(i) && i >= 0 && i < c.slots.length,
        ),
        `${c.id}: invalid member index`,
      );
      check(
        c.slots.every(
          (i) =>
            Number.isSafeInteger(i) &&
            i >= 0 &&
            i < w.header.size * w.header.size,
        ),
        `${c.id}: invalid member position`,
      );
      for (let i = 0; i < c.slots.length; i++)
        if (!removed.has(i)) {
          const id = memberId(c.first, i);
          check(!ids.has(id), `${id}: duplicate representation`);
          ids.add(id);
        }
    }
  }
  return errors;
}
export function assertWorld(w: World, deep = false): void {
  const errors = audit(w, deep);
  requireRule(
    errors.length === 0,
    `InvariantFailure: ${errors.slice(0, 4).join("; ")}`,
  );
}
