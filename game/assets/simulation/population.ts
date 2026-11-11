import {
  type World,
  type Actor,
  type ActorKind,
  type Id,
  type Vec,
  type Header,
  type Population,
  TILE,
  tileKey,
  requireRule,
} from "./model.ts";
import { Draft } from "./transaction.ts";
import { hash, checksum } from "./determinism.ts";
import {
  SKILLS,
  ITEMS,
  RECIPES,
  BUILDINGS,
  RESEARCH,
  CONTENT_VERSION,
} from "../content/catalog.ts";
import { passable, withinOccupation } from "./terrain.ts";
import { newContainer, addItem } from "./inventory.ts";

export const CONTENT_HASH = checksum({
  version: CONTENT_VERSION,
  SKILLS,
  ITEMS,
  RECIPES,
  BUILDINGS,
  RESEARCH,
});
export const slotPosition = (w: World, slot: number): Vec => ({
  x: (slot % w.header.size) * TILE + 128,
  y: Math.floor(slot / w.header.size) * TILE + 128,
});
export const memberId = (first: Id, index: number) =>
  (BigInt(first) + BigInt(index)).toString();
export function makeActor(
  d: Draft,
  kind: ActorKind,
  position: Vec,
  fixedId?: Id,
): Actor {
  const id = fixedId ?? d.id(),
    seed = hash(`${d.header.seed}/person/${id}`);
  const actor: Actor = {
    id,
    kind,
    name:
      kind === "infected"
        ? `感染体 ${id}`
        : kind === "animal"
          ? `野犬 ${id}`
          : `幸存者 ${id}`,
    sex: seed % 2 ? "female" : "male",
    position: { ...position },
    hp: kind === "infected" ? 60 : 100,
    life: "Alive",
    inventory: "",
    skills: Object.fromEntries(Object.keys(SKILLS).map((k) => [k, 0])),
    knowledge: [],
    food: 100,
    water: 100,
    fatigue: 0,
    mood: 70,
    temperature: 37,
    lastNeeds: d.header.tick,
    readyAt: 0,
    intent: { x: 0, y: 0 },
    sneaking: false,
    traits: {},
    pressure: {},
    injuries: [],
    revision: 0,
  };
  actor.inventory = newContainer(d, position, {
    actor: id,
    owner: id,
    capacity: 30000,
  });
  if (kind === "player" || kind === "npc") {
    for (const [item, n] of Object.entries({
      club: 1,
      food: 1,
      water: 1,
      cloth: 2,
    }))
      addItem(d, actor.inventory, item, n, "common-start-template-v1");
    if (kind === "npc")
      actor.profile = {
        personality: {
          caution: seed % 101,
          sociability: (seed >>> 8) % 101,
          ambition: (seed >>> 16) % 101,
        },
        beliefs: [],
        memories: [],
        plan: {
          goal: "survive",
          steps: [],
          cursor: 0,
          reason: "寻找食水与安全落脚地",
          retryAt: 0,
          failures: 0,
        },
        nextThink: d.header.tick + (seed % 40),
        personalGoal: ["建立庇护所", "掌握医药", "寻找同伴", "研究工程"][
          seed % 4
        ],
      };
  }
  d.put("actors", id, actor);
  return actor;
}
const placementCache = new WeakMap<World, Uint8Array>();
function occupiedSlots(w: World): Uint8Array {
  const cached = placementCache.get(w);
  if (cached) return cached;
  const bits = new Uint8Array(Math.ceil((w.header.size * w.header.size) / 8));
  const mark = (slot: number) => {
    bits[slot >> 3] |= 1 << (slot & 7);
  };
  for (const a of Object.values(w.actors))
    if (a.life === "Alive")
      mark(
        Math.floor(a.position.y / TILE) * w.header.size +
          Math.floor(a.position.x / TILE),
      );
  for (const c of Object.values(w.cohorts)) {
    const removed = new Set(c.removed);
    c.slots.forEach((slot, i) => {
      if (!removed.has(i)) mark(slot);
    });
  }
  placementCache.set(w, bits);
  return bits;
}
export function placePending(d: Draft, budget = 1000): void {
  const h = d.header,
    used = occupiedSlots(
      d.world.actors !== d.base.actors || d.world.cohorts !== d.base.cohorts
        ? d.world
        : d.base,
    ).slice(),
    slots: number[] = [];
  const span = h.completedDays === 0 ? Math.min(512, h.size) : h.size,
    area = span * span;
  const offset = Math.floor((h.size - span) / 2),
    salt = hash(h.seed + "/placement") % area;
  let attempts = 0,
    remaining = budget;
  while (
    remaining > 0 &&
    (h.npc.pending || h.infected.pending) &&
    attempts++ < area
  ) {
    const n = (Math.imul(h.placementCursor++, 7919) >>> 0) % area;
    const v = (n + salt) % area,
      x = (v % span) + offset,
      y = Math.floor(v / span) + offset,
      slot = y * h.size + x;
    const p = slotPosition(d.world, slot);
    if (
      (used[slot >> 3] & (1 << (slot & 7))) !== 0 ||
      !passable(d.world, p) ||
      withinOccupation(d.world, p)
    )
      continue;
    used[slot >> 3] |= 1 << (slot & 7);
    remaining--;
    if (h.npc.pending) {
      makeActor(d, "npc", p);
      h.npc.pending--;
      h.npc.placed++;
    } else {
      slots.push(slot);
      h.infected.pending--;
      h.infected.placed++;
    }
  }
  if (slots.length) {
    const first = d.ids(slots.length),
      id = d.id();
    d.put("cohorts", id, {
      id,
      first,
      slots,
      removed: [],
      heard: {},
      sourceDay: h.completedDays,
      revision: 0,
    });
  }
  placementCache.set(d.world, used);
  h.phase =
    h.npc.pending || h.infected.pending
      ? attempts >= area
        ? "CapacityBlocked"
        : "DayBoundary"
      : "Running";
}
export function beginDay(d: Draft): void {
  const day = Math.floor(d.header.tick / d.header.ticksPerDay);
  requireRule(day === d.header.completedDays + 1, "DayAlreadyCommitted");
  requireRule(d.header.dailyKey < day, "DayAlreadyCommitted");
  d.header.dailyKey = day;
  d.header.completedDays = day;
  for (const [p, n] of [
    [d.header.npc, 100],
    [d.header.infected, 10000],
  ] as [Population, number][]) {
    p.daily += n;
    p.alive += n;
    p.pending += n;
  }
  d.header.phase = "DayBoundary";
  d.event(
    "DayBoundary",
    `第 ${day + 1} 日：新增 100 名幸存者、10000 只感染体，正在合法安置。`,
  );
}
export function materialize(d: Draft, cohortId: Id, index: number): Actor {
  const c = d.world.cohorts[cohortId];
  requireRule(
    c && index >= 0 && index < c.slots.length && !c.removed.includes(index),
    "MemberUnavailable",
  );
  const id = memberId(c.first, index);
  requireRule(!d.world.actors[id] && !d.world.deaths[id], "IdentityReused");
  const pos = slotPosition(d.world, c.slots[index]);
  const a = makeActor(d, "infected", pos, id);
  a.heard = c.heard[String(index)];
  const edit = d.edit("cohorts", cohortId);
  edit.removed.push(index);
  edit.removed.sort((a, b) => a - b);
  edit.revision++;
  return a;
}
export function createWorld(
  seed: string,
  options: {
    worldId?: string;
    size?: number;
    ticksPerDay?: number;
    biome?: Header["biome"];
    owner?: string;
  } = {},
): World {
  const population = (initial: number): Population => ({
    initial,
    daily: 0,
    deaths: 0,
    alive: initial,
    placed: 0,
    pending: initial,
  });
  const w: World = {
    header: {
      worldId:
        options.worldId ??
        `world-${hash(`${seed}/${options.biome ?? (["inland", "coast", "dunes"] as const)[hash(seed) % 3]}`).toString(16)}`,
      seed,
      schema: 1,
      simVersion: "ember-sim-1",
      contentHash: CONTENT_HASH,
      biome:
        options.biome ??
        (["inland", "coast", "dunes"] as const)[hash(seed) % 3],
      size: options.size ?? 2048,
      tick: 0,
      completedDays: 0,
      ticksPerDay: options.ticksPerDay ?? 36000,
      phase: "DayBoundary",
      seq: 0,
      nextId: "1",
      rng: {},
      placementCursor: 0,
      npcCursor: 0,
      terrainRevision: 0,
      climate: "normal",
      climateUntil: 72000,
      dailyKey: 0,
      npc: population(99),
      infected: population(10000),
      worldOwner: options.owner ?? "local",
    },
    resources: {},
    actors: {},
    items: {},
    containers: {},
    cohorts: {},
    terrain: {},
    buildings: {},
    jobs: {},
    tasks: {},
    reservations: {},
    companions: {},
    vehicles: {},
    deaths: {},
    bindings: {},
    disasters: {},
    events: [],
    receipts: {},
  };
  requireRule(
    w.header.size >= 128 && (w.header.size & (w.header.size - 1)) === 0,
    "WorldSizeMustBePowerOfTwo",
  );
  const d = new Draft(w);
  let p = {
    x: (w.header.size * TILE) / 2 + 128,
    y: (w.header.size * TILE) / 2 + 128,
  };
  while (!passable(d.world, p)) p = { x: p.x + TILE, y: p.y };
  const player = makeActor(d, "player", p);
  player.name = "旅人";
  d.put("bindings", "seat-1", {
    id: "seat-1",
    actor: player.id,
    player: options.owner ?? "local",
    epoch: 1,
    sequence: 0,
    connected: true,
    dead: false,
    pauseVote: false,
  });
  while (d.header.phase === "DayBoundary") placePending(d, 2000);
  // Physical salvage near the initial exploration area. Nothing is a functioning settlement.
  const supplies: Record<string, number>[] = [
    { wood: 12, stone: 6, cloth: 5, food: 3, water: 2, book_survival: 1 },
    { scrap: 12, wire: 4, gear: 2, reagent: 5, book_tech: 1 },
    { sample: 6, herb: 6, nutrient: 4, book_bio: 1 },
    { cloth: 4, gear: 3, battery: 3, book_aug: 1 },
    { seed: 6, dirty_water: 5, food: 3 },
  ];
  for (let i = 0; i < supplies.length; i++) {
    const position = {
      x: p.x + ((i % 3) + 2) * TILE,
      y: p.y + (Math.floor(i / 3) + 2) * TILE,
    };
    if (!passable(d.world, position)) continue;
    const c = newContainer(d, position);
    for (const [item, n] of Object.entries(supplies[i]))
      addItem(d, c, item, n, "world-generation-salvage");
  }
  const animal = makeActor(d, "animal", {
    x: p.x - 5 * TILE,
    y: p.y + 4 * TILE,
  });
  animal.name = "荒野犬";
  const stagPosition = { x: p.x - 9 * TILE, y: p.y + 3 * TILE };
  if (passable(d.world, stagPosition)) {
    const stag = makeActor(d, "animal", stagPosition);
    stag.name = "荒原鹿";
    stag.traits.size = 3;
  }
  d.event("WorldCreated", "你与所有幸存者从白板开始。世界中没有现成营地。");
  const out = d.finish().world;
  out.header.seq = 0;
  return out;
}
