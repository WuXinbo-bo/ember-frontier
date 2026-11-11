import {
  type World,
  type Actor,
  type Id,
  type Vec,
  type Command,
  type Candidate,
  RuleError,
  requireRule,
  distance,
  TILE,
  tileKey,
} from "./model.ts";
import { Draft } from "./transaction.ts";
import { stable, boundedInt, hash } from "./determinism.ts";
import { BUILDINGS, ITEMS, RECIPES, RESEARCH } from "../content/catalog.ts";
import {
  newContainer,
  addItem,
  inventoryItems,
  countItem,
  pay,
  take,
  transfer,
  weight,
  containerPosition,
} from "./inventory.ts";
import {
  passable,
  findPath,
  tileAt,
  buildingAt,
  clearLine,
} from "./terrain.ts";
import { emitSound } from "./acoustics.ts";
import { beginDay, placePending, materialize } from "./population.ts";
import { nearbyMembers } from "./spatial.ts";
import { vehicleAction, stepVehicles } from "./vehicles.ts";
import { developmentPlan } from "./development.ts";
import { gather, resourceAt } from "./environment.ts";
import { choosePlan, observe } from "./cognition.ts";

const text = (x: unknown, max = 100): string => {
  requireRule(
    typeof x === "string" && x.length > 0 && x.length <= max,
    "InvalidText",
  );
  return x;
};
const num = (x: unknown, min = 0, max = 1e9): number => {
  requireRule(boundedInt(x, min, max), "InvalidNumber");
  return x;
};
const position = (w: World, data: Record<string, unknown>): Vec => ({
  x: num(data.x, 0, w.header.size * TILE - 1),
  y: num(data.y, 0, w.header.size * TILE - 1),
});
const nearestStation = (w: World, a: Actor, definition: string) =>
  Object.values(w.buildings).find(
    (b) =>
      b.definition === definition &&
      b.progress === 100 &&
      b.hp > 0 &&
      distance(a.position, b.position) <= 3 &&
      b.owner === a.id,
  );
export function learn(a: Actor, skill: string, xp: number): void {
  if (skill in a.skills)
    a.skills[skill] = Math.min(10000, a.skills[skill] + xp);
}
export function controlBudget(a: Actor): number {
  const tame = Math.min(6, Math.floor(a.skills.taming / 100) * 2),
    bio = [3, 2, 1].find((t) => a.knowledge.includes(`bio.control.${t}`)) ?? 0;
  return Math.max(tame, bio * 2);
}
export function controlUse(w: World, actor: Id): number {
  return Object.values(w.companions)
    .filter(
      (c) =>
        c.controller === actor &&
        ["follow", "guard", "retreat"].includes(c.state),
    )
    .reduce((n, c) => n + c.cost, 0);
}
const activeCompanions = (w: World, id: Id) =>
  Object.values(w.companions).filter(
    (c) =>
      c.controller === id && ["follow", "guard", "retreat"].includes(c.state),
  );

export function die(d: Draft, id: Id, cause: string): void {
  const prior = d.world.actors[id];
  if (!prior || prior.life === "Dead" || d.world.deaths[id]) return;
  const a = d.edit("actors", id);
  a.hp = 0;
  a.life = "Dead";
  a.intent = { x: 0, y: 0 };
  a.mountedOn = undefined;
  for (const vehicle of Object.values(d.world.vehicles))
    for (const [seat, occupant] of Object.entries(vehicle.seats))
      if (occupant === id) {
        delete d.edit("vehicles", vehicle.id).seats[seat];
        d.edit("vehicles", vehicle.id).revision++;
      }
  for (const rider of Object.values(d.world.actors))
    if (rider.mountedOn === id) {
      const r = d.edit("actors", rider.id);
      r.mountedOn = undefined;
      r.intent = { x: 0, y: 0 };
    }
  a.revision++;
  const loot = newContainer(d, a.position, {
    capacity: Number.MAX_SAFE_INTEGER,
  });
  const items = inventoryItems(d.world, a.inventory).map((i) => i.id);
  for (const item of items) {
    const edit = d.edit("items", item);
    edit.container = loot;
    edit.revision++;
  }
  d.put("deaths", id, {
    id,
    tick: d.header.tick,
    cause,
    loot,
    originalItems: items,
  });
  const p =
    a.kind === "npc"
      ? d.header.npc
      : a.kind === "infected"
        ? d.header.infected
        : undefined;
  if (p) {
    p.deaths++;
    p.alive--;
    p.placed--;
  }
  for (const r of Object.values(d.world.reservations))
    if (r.holder === id) d.remove("reservations", r.id);
  for (const j of Object.values(d.world.jobs))
    if (j.actor === id && j.state !== "Complete" && j.state !== "Cancelled") {
      const edit = d.edit("jobs", j.id);
      edit.state = "Paused";
      edit.reason = "ActorDead";
      d.edit("containers", j.inputs).owner = undefined;
    }
  for (const c of Object.values(d.world.companions))
    if (c.id === id || c.controller === id) {
      const edit = d.edit("companions", c.id);
      edit.state = c.id === id ? "dead" : "emergency";
      edit.controller = undefined;
      edit.revision++;
    }
  for (const b of Object.values(d.world.bindings))
    if (b.actor === id) {
      const edit = d.edit("bindings", b.id);
      edit.dead = true;
    }
  for (const t of Object.values(d.world.tasks))
    if (t.issuer === id && t.state !== "Settled") {
      const edit = d.edit("tasks", t.id);
      edit.state = "Cancelled";
      edit.reason = "IssuerDead";
    }
  d.event("Death", `${a.name} 永久死亡：${cause}。原物品保留在遗物中。`, id);
  const seats = Object.values(d.world.bindings);
  if (seats.length && seats.every((b) => b.dead)) {
    d.header.phase = "Ended";
    d.header.result = "所有已绑定玩家已死亡；本局结束。";
  }
}
export function hurt(d: Draft, id: Id, damage: number, cause: string): void {
  const prior = d.world.actors[id];
  if (!prior || prior.life === "Dead") return;
  const armor =
    prior.kind === "infected"
      ? Math.min(0.5, (prior.traits.armor ?? 0) / 100)
      : countItem(d.world, prior.inventory, "armor") > 0
        ? 0.35
        : 0;
  const a = d.edit("actors", id);
  a.hp = Math.max(0, a.hp - Math.max(1, Math.round(damage * (1 - armor))));
  a.revision++;
  a.pressure.combat = (a.pressure.combat ?? 0) + damage;
  if (a.hp === 0) die(d, id, cause);
}
function consume(d: Draft, a: Actor, itemId: Id): void {
  const item = d.world.items[itemId];
  requireRule(
    item && item.container === a.inventory && item.quantity > 0,
    "ItemMissing",
  );
  const def = ITEMS[item.definition];
  requireRule(def.food || def.water || def.heal, "NotConsumable");
  take(d, a.inventory, item.definition, 1);
  a.food = Math.min(100, a.food + (def.food ?? 0));
  a.water = Math.min(100, a.water + (def.water ?? 0));
  a.hp = Math.min(100, a.hp + (def.heal ?? 0));
  if (def.heal) a.injuries = a.injuries.filter((i) => i !== "bleeding");
  a.revision++;
  d.event("Consumed", `使用 ${def.name}`, a.id);
}
function startJob(
  d: Draft,
  a: Actor,
  kind: "craft" | "build" | "research",
  definition: string,
  target?: Id,
): Id {
  const def =
    kind === "craft"
      ? RECIPES[definition]
      : kind === "research"
        ? RESEARCH[definition]
        : BUILDINGS[definition];
  requireRule(def, "DefinitionMissing");
  requireRule(
    !Object.values(d.world.jobs).some(
      (j) => j.actor === a.id && ["Working", "Paused"].includes(j.state),
    ),
    "Busy",
  );
  const knowledge =
    kind === "craft" ? RECIPES[definition].knowledge : undefined;
  if (knowledge)
    requireRule(a.knowledge.includes(knowledge), "KnowledgeMissing");
  if (kind === "research") {
    requireRule(!a.knowledge.includes(definition), "AlreadyResearched");
    requireRule(
      RESEARCH[definition].prerequisites.every((k) => a.knowledge.includes(k)),
      "KnowledgeMissing",
    );
  }
  const stationName =
    kind === "craft"
      ? RECIPES[definition].workstation
      : kind === "research"
        ? RESEARCH[definition].workstation
        : undefined;
  const station = stationName
    ? nearestStation(d.world, a, stationName)
    : undefined;
  requireRule(!stationName || station, "WorkstationMissing");
  if (station)
    requireRule(
      !Object.values(d.world.reservations).some(
        (r) => r.resource === station.id && r.expires > d.header.tick,
      ),
      "WorkstationReserved",
    );
  for (const [item, n] of Object.entries(def.cost))
    requireRule(countItem(d.world, a.inventory, item) >= n, "MissingMaterial");
  const id = d.id(),
    inputs = newContainer(d, a.position, { owner: a.id });
  for (const [defId, n] of Object.entries(def.cost)) {
    let left = n;
    for (const item of inventoryItems(d.world, a.inventory).filter(
      (i) => i.definition === defId,
    )) {
      const qty = Math.min(left, item.quantity);
      if (qty > 0) transfer(d, a.id, item.id, inputs, qty);
      left -= qty;
      if (!left) break;
    }
  }
  d.put("jobs", id, {
    id,
    kind,
    definition,
    actor: a.id,
    target,
    workstation: station?.id,
    inputs,
    done: 0,
    required: def.ticks,
    state: "Working",
    consumed: false,
    revision: 0,
  });
  if (station) {
    const rid = d.id();
    d.put("reservations", rid, {
      id: rid,
      holder: a.id,
      resource: station.id,
      amount: 1,
      job: id,
      expires: d.header.tick + def.ticks + 200,
    });
  }
  d.event(
    "JobStarted",
    `${def.name}：已投入真实材料，工作需 ${def.ticks / 20} 秒。`,
    a.id,
  );
  return id;
}
function attack(
  d: Draft,
  a: Actor,
  targetId: Id,
  weaponId?: Id,
  hunting = false,
): void {
  let target = d.world.actors[targetId];
  if (!target) {
    const found = nearbyMembers(d.world, a.position, 40).find(
      (m) => m.id === targetId,
    );
    if (found) target = materialize(d, found.cohort, found.index);
  }
  requireRule(
    target && target.life === "Alive" && target.id !== a.id,
    "TargetUnavailable",
  );
  requireRule(
    (target.kind === "infected" || (hunting && target.kind === "animal")) &&
      !d.world.companions[target.id]?.controller,
    "FriendlyTarget",
  );
  requireRule(a.readyAt <= d.header.tick, "Cooldown");
  const item = weaponId
    ? d.world.items[weaponId]
    : inventoryItems(d.world, a.inventory).find(
        (i) => ITEMS[i.definition].damage,
      );
  const def = item
    ? ITEMS[item.definition]
    : {
        name: "徒手",
        mass: 0,
        damage: 8,
        range: 1.5,
        noise: 4,
        ammo: undefined,
      };
  requireRule(!item || item.container === a.inventory, "PermissionDenied");
  requireRule(def.damage, "NotAWeapon");
  requireRule(
    distance(a.position, target.position) <= (def.range ?? 1.5),
    "OutOfRange",
  );
  requireRule(clearLine(d.world, a.position, target.position), "LineBlocked");
  if (def.ammo) take(d, a.inventory, def.ammo, 1);
  else {
    requireRule(a.fatigue < 95, "Exhausted");
    a.fatigue = Math.min(100, a.fatigue + 2);
  }
  a.readyAt = d.header.tick + 14;
  a.revision++;
  learn(a, def.ammo ? "shooting" : "melee", 3);
  hurt(d, target.id, def.damage, "战斗");
  emitSound(d, a.position, def.noise ?? 4, a.id);
  d.event("Attack", `命中 ${target.name}`, a.id);
}
function executeAction(
  d: Draft,
  a: Actor,
  kind: string,
  data: Record<string, unknown>,
): void {
  if (vehicleAction(d, a, kind, data)) {
    a.revision++;
    return;
  }
  switch (kind) {
    case "VehicleFire": {
      const v = d.world.vehicles[a.mountedOn ?? ""];
      requireRule(
        v && v.hp > 0 && v.modules.includes("gun_module"),
        "VehicleWeaponMissing",
      );
      requireRule(
        v.seats.gunner === a.id || (!v.seats.gunner && v.seats.driver === a.id),
        "WrongSeat",
      );
      requireRule(
        (v.readyAt ?? 0) <= d.header.tick && a.readyAt <= d.header.tick,
        "Cooldown",
      );
      const targetId = text(data.target);
      let target = d.world.actors[targetId];
      if (!target) {
        const m = nearbyMembers(d.world, v.position, 20).find(
          (m) => m.id === targetId,
        );
        if (m) target = materialize(d, m.cohort, m.index);
      }
      requireRule(
        target?.life === "Alive" &&
          target.kind === "infected" &&
          !d.world.companions[target.id]?.controller,
        "TargetUnavailable",
      );
      requireRule(
        distance(v.position, target.position) <= 20 &&
          clearLine(d.world, v.position, target.position),
        "LineBlocked",
      );
      requireRule(v.fuel >= 2, "FuelEmpty");
      take(d, v.inventory, "ammo", 1);
      const edit = d.edit("vehicles", v.id);
      edit.fuel -= 2;
      edit.readyAt = d.header.tick + 20;
      edit.revision++;
      a.readyAt = d.header.tick + 20;
      hurt(d, target.id, 45, "车载射击");
      emitSound(d, v.position, 42, a.id);
      learn(a, "shooting", 3);
      break;
    }
    case "Gather":
      gather(
        d,
        a,
        num(data.x, 0, d.header.size - 1),
        num(data.y, 0, d.header.size - 1),
      );
      emitSound(d, a.position, 6, a.id);
      break;
    case "Move": {
      a.intent = { x: num(data.x, -1, 1), y: num(data.y, -1, 1) };
      a.sneaking = data.sneaking === true;
      break;
    }
    case "Transfer": {
      const itemId = text(data.item),
        dest = text(data.destination),
        n = num(data.amount, 1, 100000);
      const item = d.world.items[itemId];
      transfer(d, a.id, itemId, dest, n);
      break;
    }
    case "Consume":
      consume(d, a, text(data.item));
      break;
    case "Read": {
      const item = d.world.items[text(data.item)];
      requireRule(
        item && item.container === a.inventory && item.quantity > 0,
        "ItemMissing",
      );
      const knowledge = ITEMS[item.definition].knowledge;
      requireRule(knowledge, "NotABook");
      requireRule(!a.knowledge.includes(knowledge), "AlreadyRead");
      requireRule(
        !Object.values(d.world.jobs).some(
          (j) => j.actor === a.id && ["Working", "Paused"].includes(j.state),
        ),
        "Busy",
      );
      const id = d.id(),
        inputs = newContainer(d, a.position, { owner: a.id });
      d.put("jobs", id, {
        id,
        kind: "read",
        definition: knowledge,
        actor: a.id,
        target: item.id,
        inputs,
        done: 0,
        required: 200,
        state: "Working",
        consumed: true,
        revision: 0,
      });
      a.fatigue = Math.min(100, a.fatigue + 4);
      d.event("Reading", `开始阅读：${ITEMS[item.definition].name}`, a.id);
      break;
    }
    case "Craft":
      startJob(d, a, "craft", text(data.definition));
      break;
    case "Research":
      startJob(d, a, "research", text(data.definition));
      break;
    case "Build": {
      const defId = text(data.definition),
        def = BUILDINGS[defId];
      requireRule(def, "DefinitionMissing");
      const p = position(d.world, data);
      requireRule(distance(a.position, p) <= 4, "OutOfRange");
      requireRule(
        (defId === "bridge" || passable(d.world, p)) && !buildingAt(d.world, p),
        "PlacementBlocked",
      );
      requireRule(
        !Object.values(d.world.actors).some(
          (x) => x.life === "Alive" && tileKey(x.position) === tileKey(p),
        ),
        "PlacementOccupied",
      );
      requireRule(
        !nearbyMembers(d.world, p, 1).some(
          (x) => tileKey(x.position) === tileKey(p),
        ),
        "PlacementOccupied",
      );
      const id = d.id(),
        inv = newContainer(d, p, { owner: a.id });
      d.put("buildings", id, {
        id,
        definition: defId,
        position: p,
        owner: a.id,
        progress: 0,
        hp: def.hp,
        revision: 0,
        powered: false,
        storedEnergy: 0,
        inventory: inv,
        occupied: false,
      });
      startJob(d, a, "build", defId, id);
      break;
    }
    case "CancelJob": {
      const j = d.world.jobs[text(data.job)];
      requireRule(j && j.actor === a.id, "PermissionDenied");
      requireRule(
        j.state !== "Complete" && j.state !== "Cancelled",
        "JobClosed",
      );
      d.edit("jobs", j.id).state = "Cancelled";
      // Return only unconsumed inputs. Excess stays in the real worksite container.
      for (const i of inventoryItems(d.world, j.inputs)) {
        if (
          distance(a.position, containerPosition(d.world, j.inputs)) <= 2.8 &&
          weight(d.world, a.inventory) +
            ITEMS[i.definition].mass * i.quantity <=
            d.world.containers[a.inventory].capacity
        )
          transfer(d, a.id, i.id, a.inventory, i.quantity);
      }
      if (
        j.kind === "modify" &&
        j.target &&
        d.world.actors[j.target]?.life === "Alive"
      ) {
        const c = d.edit("companions", j.target);
        c.state = "captured";
        c.controller = undefined;
        c.revision++;
      }
      if (
        j.kind === "build" &&
        j.target &&
        d.world.buildings[j.target]?.progress === 0
      )
        d.remove("buildings", j.target);
      for (const r of Object.values(d.world.reservations))
        if (r.job === j.id) d.remove("reservations", r.id);
      d.event("JobCancelled", "任务取消，已消耗的材料不返还。", a.id);
      break;
    }
    case "Hunt":
      attack(
        d,
        a,
        text(data.target),
        data.weapon ? text(data.weapon) : undefined,
        true,
      );
      break;
    case "Butcher": {
      const corpse = d.world.actors[text(data.target)],
        death = corpse && d.world.deaths[corpse.id];
      requireRule(
        corpse &&
          death &&
          corpse.life === "Dead" &&
          !death.harvested &&
          ["animal", "infected"].includes(corpse.kind),
        "TargetUnavailable",
      );
      requireRule(
        distance(a.position, d.world.containers[death.loot].position) <= 2.5 &&
          a.readyAt <= d.header.tick,
        "OutOfRange",
      );
      const def = corpse.kind === "animal" ? "meat" : "sample";
      requireRule(
        weight(d.world, a.inventory) + ITEMS[def].mass * 2 <=
          d.world.containers[a.inventory].capacity,
        "OutputCapacity",
      );
      addItem(d, a.inventory, def, 2, `body/${corpse.id}`);
      d.edit("deaths", corpse.id).harvested = true;
      a.readyAt = d.header.tick + 60;
      learn(a, "hunting", 10);
      break;
    }
    case "Attack":
      attack(
        d,
        a,
        text(data.target),
        data.weapon ? text(data.weapon) : undefined,
      );
      break;
    case "Rest":
      requireRule(a.readyAt <= d.header.tick, "Cooldown");
      requireRule(nearbyMembers(d.world, a.position, 6).length === 0, "Unsafe");
      a.intent = { x: 0, y: 0 };
      a.fatigue = Math.max(0, a.fatigue - 5);
      a.readyAt = d.header.tick + 100;
      requireRule(
        !Object.values(d.world.actors).some(
          (x) =>
            x.kind === "infected" &&
            x.life === "Alive" &&
            distance(x.position, a.position) < 6,
        ),
        "Unsafe",
      );
      break;
    case "ToggleDoor": {
      const b = d.world.buildings[text(data.building)];
      requireRule(
        b &&
          b.definition === "door" &&
          b.owner === a.id &&
          b.progress === 100 &&
          b.hp > 0 &&
          distance(b.position, a.position) <= 3,
        "PermissionDenied",
      );
      const edit = d.edit("buildings", b.id);
      edit.open = !edit.open;
      edit.revision++;
      d.header.terrainRevision++;
      emitSound(d, b.position, 4, a.id);
      break;
    }
    case "RepairBuilding": {
      const b = d.world.buildings[text(data.building)];
      requireRule(
        b &&
          b.owner === a.id &&
          distance(b.position, a.position) <= 3 &&
          a.readyAt <= d.header.tick,
        "PermissionDenied",
      );
      pay(d, a.inventory, { wood: 1, scrap: 1 });
      const edit = d.edit("buildings", b.id);
      edit.hp = Math.min(BUILDINGS[b.definition].hp, b.hp + 50);
      edit.revision++;
      a.readyAt = d.header.tick + 100;
      break;
    }
    case "RecoverLoot": {
      const c = d.world.containers[text(data.container)];
      requireRule(
        c &&
          !c.actor &&
          (!c.owner || c.owner === a.id) &&
          distance(c.position, a.position) <= 3,
        "PermissionDenied",
      );
      requireRule(
        tileAt(
          d.world,
          Math.floor(c.position.x / TILE),
          Math.floor(c.position.y / TILE),
        ).water <= 40,
        "StillSubmerged",
      );
      requireRule(a.readyAt <= d.header.tick, "Cooldown");
      d.edit("containers", c.id).state = "normal";
      a.readyAt = d.header.tick + 120;
      a.fatigue = Math.min(100, a.fatigue + 8);
      break;
    }
    case "Power": {
      const b = d.world.buildings[text(data.building)];
      requireRule(
        b &&
          b.owner === a.id &&
          b.progress === 100 &&
          distance(b.position, a.position) <= 3,
        "PermissionDenied",
      );
      requireRule(b.definition === "generator", "NotAGenerator");
      const edit = d.edit("buildings", b.id);
      edit.powered = !edit.powered;
      edit.revision++;
      break;
    }
    case "Capture": {
      const id = text(data.target);
      let target = d.world.actors[id];
      if (!target) {
        const m = nearbyMembers(d.world, a.position, 3).find(
          (m) => m.id === id,
        );
        if (m) target = materialize(d, m.cohort, m.index);
      }
      requireRule(
        target &&
          target.life === "Alive" &&
          ["infected", "animal"].includes(target.kind),
        "TargetUnavailable",
      );
      requireRule(distance(a.position, target.position) < 2.5, "OutOfRange");
      requireRule(!d.world.companions[id], "AlreadyCaptured");
      if (target.kind === "infected") {
        requireRule(a.knowledge.includes("bio.control.1"), "KnowledgeMissing");
        requireRule(target.hp <= 20, "TargetNotRestrained");
      } else
        requireRule(
          countItem(d.world, a.inventory, "food") >= 1,
          "MissingMaterial",
        );
      pay(
        d,
        a.inventory,
        target.kind === "infected" ? { cloth: 2 } : { food: 1, cloth: 1 },
      );
      const grade =
        target.kind === "infected"
          ? "ordinary"
          : target.traits.size >= 3
            ? "large"
            : "medium";
      d.put("companions", id, {
        id,
        owner: a.id,
        type: target.kind === "infected" ? "controlled" : "pet",
        grade,
        cost: grade === "large" ? 3 : 2,
        training: 0,
        loyalty: 40,
        stability: 50,
        state: "captured",
        saddle: false,
        retention: 80,
        retainedTraits: {},
        maintenanceTick: d.header.tick,
        revision: 0,
      });
      d.edit("actors", id).intent = { x: 0, y: 0 };
      learn(a, "trapping", 20);
      d.event("Capture", "已约束原有个体，人口与生命不增加。", a.id);
      break;
    }
    case "Train": {
      const c = d.world.companions[text(data.target)];
      requireRule(
        c && c.owner === a.id && c.type === "pet" && c.state !== "dead",
        "PermissionDenied",
      );
      requireRule(c.training < 3, "TrainingComplete");
      requireRule(
        !Object.values(d.world.jobs).some(
          (j) =>
            (j.actor === a.id || j.target === c.id) &&
            ["Working", "Paused"].includes(j.state),
        ),
        "Busy",
      );
      requireRule(
        distance(a.position, d.world.actors[c.id].position) < 3,
        "OutOfRange",
      );
      requireRule(
        !Object.values(d.world.jobs).some(
          (j) => j.target === c.id && j.state === "Working",
        ),
        "Busy",
      );
      pay(d, a.inventory, { food: 1, water: 1 });
      const id = d.id(),
        inputs = newContainer(d, a.position);
      d.put("jobs", id, {
        id,
        kind: "train",
        definition: "train",
        actor: a.id,
        target: c.id,
        inputs,
        done: 0,
        required: 240,
        state: "Working",
        consumed: true,
        revision: 0,
      });
      break;
    }
    case "Modify": {
      const c = d.world.companions[text(data.target)];
      requireRule(
        c &&
          c.owner === a.id &&
          c.type === "controlled" &&
          c.state === "captured",
        "TargetUnavailable",
      );
      requireRule(a.knowledge.includes("bio.control.1"), "KnowledgeMissing");
      requireRule(
        !Object.values(d.world.jobs).some(
          (j) => j.actor === a.id && ["Working", "Paused"].includes(j.state),
        ),
        "Busy",
      );
      requireRule(
        nearestStation(d.world, a, "biolab") &&
          nearestStation(d.world, a, "isolation"),
        "WorkstationMissing",
      );
      requireRule(
        distance(a.position, d.world.actors[c.id].position) <= 3,
        "OutOfRange",
      );
      const owned = Object.values(d.world.companions).filter(
        (x) =>
          x.owner === a.id &&
          x.type === "controlled" &&
          !["dead", "free", "captured"].includes(x.state),
      ).length;
      const tier =
        [3, 2, 1].find((t) => a.knowledge.includes(`bio.control.${t}`)) ?? 0;
      requireRule(owned < [0, 1, 3, 4][tier], "ControlOwnershipLimit");
      pay(d, a.inventory, {
        control_core: 1,
        stabilizer: 2,
        nutrient: 2,
        battery: 1,
      });
      const edit = d.edit("companions", c.id);
      edit.state = "isolated";
      edit.retention = num(data.retention ?? 80, 70, 90);
      edit.retainedTraits = Object.fromEntries(
        Object.entries(d.world.actors[c.id].traits)
          .slice(0, 1)
          .map(([k, v]) => [k, Math.floor((v * edit.retention) / 100)]),
      );
      const id = d.id(),
        inputs = newContainer(d, a.position);
      d.put("jobs", id, {
        id,
        kind: "modify",
        definition: "modify",
        actor: a.id,
        target: c.id,
        workstation: nearestStation(d.world, a, "biolab")!.id,
        inputs,
        done: 0,
        required: 500,
        state: "Working",
        consumed: true,
        revision: 0,
      });
      break;
    }
    case "Deploy": {
      const c = d.world.companions[text(data.target)];
      requireRule(
        c &&
          c.owner === a.id &&
          ["rest", "follow", "guard", "retreat"].includes(c.state),
        "CompanionUnavailable",
      );
      requireRule(
        c.type === "pet"
          ? c.training >= 1
          : a.knowledge.includes("bio.control.1"),
        "TrainingMissing",
      );
      requireRule(
        distance(a.position, d.world.actors[c.id].position) <= 12,
        "OutOfRange",
      );
      requireRule(!c.controller || c.controller === a.id, "AlreadyControlled");
      const active = activeCompanions(d.world, a.id).filter(
        (x) => x.id !== c.id,
      );
      requireRule(
        active.length < 3 &&
          active.reduce((n, x) => n + x.cost, 0) + c.cost <= controlBudget(a),
        "ControlBudgetExceeded",
      );
      const edit = d.edit("companions", c.id);
      edit.controller = a.id;
      edit.state = "follow";
      edit.revision++;
      break;
    }
    case "CompanionOrder": {
      const c = d.world.companions[text(data.target)];
      requireRule(
        c && c.controller === a.id && c.state !== "dead",
        "PermissionDenied",
      );
      const order = text(data.order);
      requireRule(
        ["follow", "guard", "retreat", "rest"].includes(order),
        "InvalidOrder",
      );
      requireRule(
        c.stability >= 40 || order === "rest" || order === "retreat",
        "StabilityLow",
      );
      const edit = d.edit("companions", c.id);
      edit.state = order as typeof edit.state;
      edit.orderPosition = { ...a.position };
      if (order === "rest") edit.controller = undefined;
      edit.revision++;
      break;
    }
    case "Mount": {
      const c = d.world.companions[text(data.target)];
      requireRule(
        c && c.type === "pet" && c.controller === a.id && c.state === "follow",
        "PermissionDenied",
      );
      requireRule(
        c.grade === "large" &&
          c.training >= 2 &&
          a.skills.driving >= 100 &&
          a.skills.taming >= 100,
        "RidingQualification",
      );
      requireRule(
        distance(a.position, d.world.actors[c.id].position) <= 1.5,
        "OutOfRange",
      );
      if (!c.saddle) {
        pay(d, a.inventory, { saddle: 1 });
        d.edit("companions", c.id).saddle = true;
      }
      a.mountedOn = c.id;
      break;
    }
    case "Dismount":
      requireRule(!d.world.vehicles[a.mountedOn ?? ""], "UseVehicleExit");
      a.mountedOn = undefined;
      break;
    case "OfferCompanion": {
      const c = d.world.companions[text(data.target)],
        to = d.world.actors[text(data.to)];
      requireRule(
        c &&
          c.owner === a.id &&
          to?.life === "Alive" &&
          to.kind === "player" &&
          distance(to.position, a.position) <= 3,
        "PermissionDenied",
      );
      d.edit("companions", c.id).transferOffer = to.id;
      break;
    }
    case "AcceptCompanion":
    case "TakeControl": {
      const c = d.world.companions[text(data.target)],
        body = c && d.world.actors[c.id];
      requireRule(
        c && body?.life === "Alive" && distance(body.position, a.position) <= 3,
        "TargetUnavailable",
      );
      requireRule(
        kind === "AcceptCompanion"
          ? c.transferOffer === a.id
          : c.state === "emergency" &&
              (!d.world.bindings["seat-1"] ||
                !Object.values(d.world.bindings).some(
                  (b) => b.actor === c.owner && b.connected && !b.dead,
                )),
        "PermissionDenied",
      );
      requireRule(
        c.type === "pet"
          ? c.training >= 1
          : a.knowledge.includes("bio.control.1"),
        "TrainingMissing",
      );
      requireRule(
        activeCompanions(d.world, a.id).length < 3 &&
          controlUse(d.world, a.id) + c.cost <= controlBudget(a),
        "ControlBudgetExceeded",
      );
      const edit = d.edit("companions", c.id);
      edit.owner = a.id;
      edit.controller = a.id;
      edit.transferOffer = undefined;
      edit.state = "follow";
      edit.revision++;
      break;
    }
    case "PublishTask": {
      const def = text(data.definition);
      requireRule(ITEMS[def], "DefinitionMissing");
      const destination = text(data.destination);
      requireRule(
        d.world.containers[destination]?.owner === a.id,
        "PermissionDenied",
      );
      const reward = text(data.reward ?? "food"),
        quantity = num(data.rewardQuantity ?? 1, 1, 100);
      requireRule(ITEMS[reward], "DefinitionMissing");
      const id = d.id();
      let left = quantity;
      for (const i of inventoryItems(d.world, a.inventory).filter(
        (i) => i.definition === reward,
      )) {
        const n = Math.min(
          left,
          i.quantity -
            Object.values(d.world.reservations)
              .filter((r) => r.resource === i.id)
              .reduce((s, r) => s + r.amount, 0),
        );
        if (n > 0) {
          const rid = d.id();
          d.put("reservations", rid, {
            id: rid,
            holder: a.id,
            resource: i.id,
            amount: n,
            job: id,
            expires: d.header.tick + d.header.ticksPerDay,
          });
          left -= n;
        }
        if (!left) break;
      }
      requireRule(left === 0, "RewardMissing");
      d.put("tasks", id, {
        id,
        issuer: a.id,
        kind: "collect",
        target: def,
        amount: num(data.amount, 1, 100),
        delivered: 0,
        destination,
        reward: { definition: reward, quantity },
        state: "Published",
        revision: 0,
      });
      learn(a, "leadership", 10);
      break;
    }
    case "AcceptTask": {
      const t = d.world.tasks[text(data.task)];
      requireRule(t && t.state === "Published", "TaskUnavailable");
      const edit = d.edit("tasks", t.id);
      edit.assignee = a.id;
      edit.state = "Accepted";
      edit.revision++;
      break;
    }
    case "DeliverTask": {
      const t = d.world.tasks[text(data.task)];
      requireRule(
        t && t.assignee === a.id && ["Accepted", "Executing"].includes(t.state),
        "TaskUnavailable",
      );
      const needed = t.amount - t.delivered;
      let left = needed;
      requireRule(left > 0, "DeliveryComplete");
      for (const item of inventoryItems(d.world, a.inventory).filter(
        (i) => i.definition === t.target,
      )) {
        const n = Math.min(left, item.quantity);
        if (n > 0) {
          transfer(d, a.id, item.id, t.destination, n, t.id);
          left -= n;
          d.edit("tasks", t.id).delivered += n;
        }
        if (left === 0) break;
      }
      requireRule(left < needed, "MissingMaterial");
      d.edit("tasks", t.id).state = "Executing";
      break;
    }
    case "SettleTask": {
      const t = d.world.tasks[text(data.task)];
      requireRule(
        t && t.assignee === a.id && ["Accepted", "Executing"].includes(t.state),
        "TaskUnavailable",
      );
      requireRule(
        t.delivered >= t.amount &&
          countItem(d.world, t.destination, t.target) >= t.amount,
        "DeliveryIncomplete",
      );
      requireRule(
        distance(a.position, containerPosition(d.world, t.destination)) <= 3,
        "OutOfRange",
      );
      const issuer = d.world.actors[t.issuer];
      requireRule(issuer?.life === "Alive", "IssuerDead");
      requireRule(
        weight(d.world, a.inventory) +
          ITEMS[t.reward.definition].mass * t.reward.quantity <=
          d.world.containers[a.inventory].capacity,
        "OutputCapacity",
      );
      take(d, issuer.inventory, t.reward.definition, t.reward.quantity, t.id);
      addItem(
        d,
        a.inventory,
        t.reward.definition,
        t.reward.quantity,
        `reward/${t.id}`,
      );
      d.edit("tasks", t.id).state = "Settled";
      for (const r of Object.values(d.world.reservations))
        if (r.job === t.id) d.remove("reservations", r.id);
      d.event("TaskSettled", "实物验收完成，奖励支付一次。", a.id);
      break;
    }
    case "CancelTask": {
      const t = d.world.tasks[text(data.task)];
      requireRule(
        t && t.issuer === a.id && t.state !== "Settled",
        "PermissionDenied",
      );
      d.edit("tasks", t.id).state = "Cancelled";
      for (const r of Object.values(d.world.reservations))
        if (r.job === t.id) d.remove("reservations", r.id);
      break;
    }
    case "Recruit": {
      const target = d.world.actors[text(data.target)];
      requireRule(
        target?.profile && target.life === "Alive" && target.id !== a.id,
        "TargetUnavailable",
      );
      requireRule(distance(a.position, target.position) < 3, "OutOfRange");
      const trust = target.profile.memories.filter(
        (m) => m.kind === "gift" && m.subject === a.id,
      ).length;
      requireRule(
        trust >= 2 && target.profile.personality.sociability >= 25,
        "ConsentMissing",
      );
      let leader: Actor | undefined = a;
      const seen = new Set<string>();
      while (leader) {
        requireRule(
          leader.id !== target.id && !seen.has(leader.id),
          "OrganizationCycle",
        );
        seen.add(leader.id);
        leader = leader.faction ? d.world.actors[leader.faction] : undefined;
      }
      d.edit("actors", target.id).faction = a.id;
      d.event("Recruited", `${target.name} 同意同行。`, a.id);
      break;
    }
    case "Gift": {
      const target = d.world.actors[text(data.target)];
      requireRule(
        target?.profile && target.life === "Alive" && target.id !== a.id,
        "TargetUnavailable",
      );
      requireRule(distance(a.position, target.position) < 3, "OutOfRange");
      requireRule(
        weight(d.world, target.inventory) + ITEMS.food.mass <=
          d.world.containers[target.inventory].capacity,
        "OutputCapacity",
      );
      pay(d, a.inventory, { food: 1 });
      addItem(d, target.inventory, "food", 1, `gift/${a.id}`);
      const t = d.edit("actors", target.id);
      if (
        !t.profile!.memories.some(
          (m) =>
            m.kind === "gift" &&
            m.subject === a.id &&
            d.header.tick - m.tick < 600,
        )
      )
        t.profile!.memories.push({
          kind: "gift",
          tick: d.header.tick,
          subject: a.id,
        });
      learn(a, "negotiation", 5);
      break;
    }
    case "AcceptInvitation": {
      const leader = a.invitedBy && d.world.actors[a.invitedBy];
      requireRule(
        leader &&
          leader.life === "Alive" &&
          distance(a.position, leader.position) < 4,
        "InvitationUnavailable",
      );
      a.faction = leader.id;
      a.invitedBy = undefined;
      break;
    }
    case "Pause": {
      requireRule(
        data.paused !== true ||
          nearbyMembers(d.world, a.position, 6).length === 0,
        "Unsafe",
      );
      requireRule(
        data.paused !== true ||
          !Object.values(d.world.actors).some(
            (x) =>
              x.kind === "infected" &&
              x.life === "Alive" &&
              distance(x.position, a.position) < 6,
          ),
        "Unsafe",
      );
      for (const b of Object.values(d.world.bindings))
        if (b.actor === a.id)
          d.edit("bindings", b.id).pauseVote = data.paused === true;
      const seats = Object.values(d.world.bindings).filter(
        (b) => b.connected && !b.dead,
      );
      d.header.phase = seats.every((b) => b.pauseVote) ? "Paused" : "Running";
      break;
    }
    default:
      throw new RuleError("UnknownCommand");
  }
  a.revision++;
}
export function reduceCommand(
  world: World,
  command: Command,
  principal: string,
): Candidate {
  const empty = (code: string): Candidate => ({
    world,
    patch: { header: world.header, tables: {}, events: [], receipts: {} },
    receipt: {
      ok: false,
      code,
      commandId: String(command?.id ?? "invalid"),
      seq: world.header.seq,
      fingerprint: "",
    },
  });
  if (
    !command ||
    typeof command !== "object" ||
    !command.data ||
    typeof command.data !== "object" ||
    Array.isArray(command.data)
  )
    return empty("InvalidCommand");
  const binding = Object.values(world.bindings).find(
    (b) => b.player === principal,
  );
  if (!binding || binding.actor !== command.actor || !binding.connected)
    return empty("Unauthorized");
  if (binding.epoch !== command.epoch) return empty("StaleSession");
  if (
    typeof command.id !== "string" ||
    !command.id.length ||
    command.id.length > 160 ||
    !boundedInt(command.sequence, 1, Number.MAX_SAFE_INTEGER)
  )
    return empty("InvalidCommand");
  const fingerprint = stable(command);
  if (fingerprint.length > 12288) return empty("PayloadTooLarge");
  const key = JSON.stringify([principal, binding.epoch, command.id]);
  const prior = world.receipts[key];
  if (prior) {
    if (prior.fingerprint !== fingerprint)
      throw new RuleError("CommandIdReused");
    return {
      world,
      patch: { header: world.header, tables: {}, events: [], receipts: {} },
      receipt: prior,
    };
  }
  if (command.sequence <= binding.sequence) return empty("StaleSequence");
  const d = new Draft(world);
  try {
    requireRule(
      world.actors[binding.actor]?.life === "Alive" && !binding.dead,
      "ActorDead",
    );
    requireRule(
      world.header.phase === "Running" ||
        (world.header.phase === "Paused" && command.kind === "Pause"),
      "WorldNotRunning",
    );
    for (const [id, revision] of Object.entries(command.expected ?? {})) {
      const actual =
        world.items[id]?.revision ??
        world.containers[id]?.revision ??
        world.buildings[id]?.revision ??
        world.actors[id]?.revision;
      requireRule(actual === revision, "VersionConflict");
    }
    if (command.kind === "Transfer") {
      const item = world.items[String(command.data.item)],
        dest = String(command.data.destination);
      requireRule(
        item &&
          command.expected?.[item.id] !== undefined &&
          command.expected?.[item.container] !== undefined &&
          command.expected?.[dest] !== undefined,
        "VersionsRequired",
      );
    }
    d.edit("bindings", binding.id).sequence = command.sequence;
    executeAction(
      d,
      d.edit("actors", binding.actor),
      command.kind,
      command.data,
    );
    return d.finish(
      { ok: true, code: "OK", commandId: command.id, seq: 0, fingerprint },
      key,
    );
  } catch (e) {
    if (!(e instanceof RuleError)) throw e;
    const rejected = new Draft(world);
    rejected.edit("bindings", binding.id).sequence = command.sequence;
    return rejected.finish(
      { ok: false, code: e.code, commandId: command.id, seq: 0, fingerprint },
      key,
    );
  }
}

function moveToward(d: Draft, a: Actor, target: Vec, speed = 26): boolean {
  if (distance(a.position, target) < 0.15) return true;
  const path = findPath(
    d.world,
    a.position,
    target,
    countItem(d.world, a.inventory, "raft") ? "raft" : "walk",
    800,
  );
  if (path === null) return false;
  const p = path[0] ?? target,
    dx = p.x - a.position.x,
    dy = p.y - a.position.y,
    n = Math.max(1, Math.hypot(dx, dy));
  const next = {
    x: Math.round(a.position.x + (dx / n) * Math.min(speed, n)),
    y: Math.round(a.position.y + (dy / n) * Math.min(speed, n)),
  };
  if (
    passable(
      d.world,
      next,
      countItem(d.world, a.inventory, "raft") ? "raft" : "walk",
    )
  ) {
    a.position = next;
    a.revision++;
  }
  return false;
}
export function stepJobs(d: Draft): void {
  for (const original of Object.values(d.world.jobs)) {
    if (original.state === "Complete" || original.state === "Cancelled")
      continue;
    const a = d.world.actors[original.actor];
    if (!a || a.life === "Dead") continue;
    const station = original.workstation
      ? d.world.buildings[original.workstation]
      : undefined;
    const target = original.target
      ? (d.world.buildings[original.target] ?? d.world.actors[original.target])
      : undefined;
    const at =
      station?.position ??
      target?.position ??
      d.world.containers[original.inputs].position;
    const reason =
      original.kind === "read" &&
      (!d.world.items[original.target!]?.quantity ||
        d.world.items[original.target!]?.container !== a.inventory)
        ? "BookMissing"
        : target && "life" in target && target.life === "Dead"
          ? "TargetDead"
          : target && "hp" in target && target.hp <= 0
            ? "TargetDestroyed"
            : distance(a.position, at) > 4
              ? "WorkerAway"
              : station && station.hp <= 0
                ? "WorkstationDestroyed"
                : station &&
                    BUILDINGS[station.definition].power &&
                    !station.powered
                  ? "NoPower"
                  : station &&
                      Object.values(d.world.reservations).some(
                        (r) =>
                          r.resource === station.id &&
                          r.job !== original.id &&
                          r.expires > d.header.tick,
                      )
                    ? "WorkstationReserved"
                    : a.readyAt > d.header.tick
                      ? "Busy"
                      : undefined;
    const j = d.edit("jobs", original.id);
    j.reason = reason;
    j.state = reason ? "Paused" : "Working";
    if (reason) continue;
    if (
      station &&
      !Object.values(d.world.reservations).some(
        (r) => r.resource === station.id && r.job === j.id,
      )
    ) {
      const rid = d.id();
      d.put("reservations", rid, {
        id: rid,
        holder: a.id,
        resource: station.id,
        amount: 1,
        job: j.id,
        expires: d.header.tick + 200,
      });
    }
    if (!j.consumed) {
      for (const item of inventoryItems(d.world, j.inputs))
        take(d, j.inputs, item.definition, item.quantity);
      j.consumed = true;
    }
    j.done++;
    j.revision++;
    for (const r of Object.values(d.world.reservations))
      if (r.job === j.id)
        d.edit("reservations", r.id).expires = d.header.tick + 200;
    if (j.kind === "build" && j.target)
      d.edit("buildings", j.target).progress = Math.floor(
        (j.done / j.required) * 100,
      );
    if (j.done % 40 === 0) emitSound(d, at, j.kind === "build" ? 8 : 4, a.id);
    if (j.done < j.required) continue;
    if (j.kind === "craft") {
      const r = RECIPES[j.definition];
      const total = Object.entries(r.output).reduce(
        (s, [id, n]) => s + ITEMS[id].mass * n,
        0,
      );
      if (
        weight(d.world, a.inventory) + total >
        d.world.containers[a.inventory].capacity
      ) {
        j.state = "Paused";
        j.reason = "OutputCapacity";
        j.done = j.required - 1;
        continue;
      }
      for (const [id, n] of Object.entries(r.output))
        addItem(d, a.inventory, id, n, `job/${j.id}`);
      learn(d.edit("actors", a.id), r.skill, 25);
    }
    if (j.kind === "read") {
      const reader = d.edit("actors", a.id);
      if (!reader.knowledge.includes(j.definition)) {
        reader.knowledge.push(j.definition);
        learn(
          reader,
          j.definition.startsWith("skill.")
            ? j.definition.slice(6)
            : "learning",
          50,
        );
      }
    }
    if (j.kind === "research") {
      d.edit("actors", a.id).knowledge.push(j.definition);
      learn(d.edit("actors", a.id), "learning", 30);
    }
    if (j.kind === "build" && j.target) {
      const b = d.edit("buildings", j.target);
      b.progress = 100;
      b.revision++;
      d.header.terrainRevision++;
      learn(d.edit("actors", a.id), "construction", 30);
    }
    if (j.kind === "train" && j.target) {
      const c = d.edit("companions", j.target);
      c.training++;
      c.loyalty = Math.min(100, c.loyalty + 20);
      c.state = "rest";
      learn(d.edit("actors", a.id), "taming", 100);
    }
    if (j.kind === "modify" && j.target) {
      const c = d.edit("companions", j.target);
      c.state = "rest";
      c.stability = 85;
      c.revision++;
      d.edit("actors", j.target).traits = { ...c.retainedTraits };
    }
    j.state = "Complete";
    for (const r of Object.values(d.world.reservations))
      if (r.job === j.id) d.remove("reservations", r.id);
    d.event(
      "JobComplete",
      `完成：${RECIPES[j.definition]?.name ?? BUILDINGS[j.definition]?.name ?? RESEARCH[j.definition]?.name ?? j.definition}`,
      a.id,
    );
  }
}
function stepNeeds(d: Draft): void {
  if (d.header.tick % 100) return;
  for (const prior of Object.values(d.world.actors))
    if (prior.life === "Alive" && prior.kind !== "infected") {
      const elapsed = d.header.tick - prior.lastNeeds;
      if (elapsed < 100) continue;
      const a = d.edit("actors", prior.id),
        units = Math.floor(elapsed / 100);
      a.lastNeeds += units * 100;
      a.food = Math.max(0, a.food - units);
      a.water = Math.max(
        0,
        a.water - units * (d.header.climate === "hot" ? 3 : 2),
      );
      a.temperature =
        d.header.climate === "hot" ? 39 : d.header.climate === "cold" ? 34 : 37;
      if (a.food === 0 || a.water === 0) hurt(d, a.id, units, "饥渴");
      if (a.temperature < 35 || a.temperature > 38) {
        const adapted =
          a.knowledge.includes("augmentation.environment.1") &&
          countItem(d.world, a.inventory, "battery") > 0;
        if (adapted && d.header.tick % 1000 === 0)
          take(d, a.inventory, "battery", 1);
        hurt(d, a.id, adapted ? 1 : 2, "极端气候");
        a.pressure[a.temperature < 35 ? "cold" : "heat"] =
          (a.pressure[a.temperature < 35 ? "cold" : "heat"] ?? 0) + 1;
      }
      const tile = tileAt(
        d.world,
        Math.floor(a.position.x / TILE),
        Math.floor(a.position.y / TILE),
      );
      if (tile.water > 80 && !countItem(d.world, a.inventory, "raft"))
        hurt(d, a.id, 5, "溺水");
      if (a.injuries.includes("bleeding")) hurt(d, a.id, 1, "出血");
    }
}
function stepNpcs(parent: Draft): void {
  const npcs = Object.values(parent.world.actors).filter(
    (a) => a.kind === "npc" && a.life === "Alive",
  );
  if (!npcs.length) return;
  const budget = Math.min(npcs.length, 8);
  for (let n = 0; n < budget; n++) {
    const old = npcs[parent.header.npcCursor++ % npcs.length];
    const d = new Draft(parent.world);
    if (!old.profile || old.profile.nextThink > d.header.tick) continue;
    const a = d.edit("actors", old.id),
      p = a.profile!;
    p.nextThink = d.header.tick + 10;
    if (p.plan.retryAt > d.header.tick) continue;
    p.beliefs = observe(d.world, a);
    if (
      p.plan.cursor >= p.plan.steps.length ||
      p.plan.goal === "scout" ||
      p.beliefs.some(
        (b) => b.kind === "danger" && distance(b.position, a.position) < 4,
      )
    )
      p.plan = choosePlan(p.beliefs, {
        position: a.position,
        food: a.food,
        water: a.water,
        fatigue: a.fatigue,
        hp: a.hp,
        ...p.personality,
        canEat: countItem(d.world, a.inventory, "food") > 0,
        canDrink: countItem(d.world, a.inventory, "water") > 0,
        tick: d.header.tick,
      });
    if (
      ["scout", "cooperate", "supply", "work"].includes(p.plan.goal) ||
      p.plan.cursor >= p.plan.steps.length
    ) {
      const dev = developmentPlan(p.beliefs, {
        position: a.position,
        tick: d.header.tick,
        inventory: inventoryItems(d.world, a.inventory).reduce(
          (o, i) => {
            o[i.definition] = (o[i.definition] ?? 0) + i.quantity;
            return o;
          },
          {} as Record<string, number>,
        ),
        knowledge: a.knowledge,
        buildings: p.beliefs
          .filter((b) => b.kind === "shelter")
          .map((b) => b.definition!),
        working: Object.values(d.world.jobs).some(
          (j) => j.actor === a.id && ["Working", "Paused"].includes(j.state),
        ),
        route: (["tech", "bio", "augmentation"] as const)[
          p.personality.ambition % 3
        ],
        food: a.food,
        water: a.water,
      });
      if (dev && p.plan.goal !== "retreat") p.plan = dev;
    }
    const step = p.plan.steps[p.plan.cursor];
    if (!step) {
      parent.absorb(d);
      continue;
    }
    try {
      if (step.kind === "move" && step.position) {
        const path = findPath(d.world, a.position, step.position, "walk", 800);
        if (path === null) throw new RuleError("RouteChanged");
        if (distance(a.position, step.position) < 2) p.plan.cursor++;
        else moveToward(d, a, step.position, 130);
      }
      if (step.kind === "consume-food" || step.kind === "consume-water") {
        const def = step.kind === "consume-food" ? "food" : "water",
          i = inventoryItems(d.world, a.inventory).find(
            (i) => i.definition === def,
          );
        if (!i) throw new RuleError("NoMaterial");
        consume(d, a, i.id);
        p.plan.cursor++;
      }
      if (step.kind === "rest") {
        a.fatigue = Math.max(0, a.fatigue - 2);
        if (a.fatigue < 30) p.plan.cursor++;
      }
      if (step.kind === "loot" && step.target) {
        const item = inventoryItems(d.world, step.target).find((i) =>
          step.definition
            ? i.definition === step.definition
            : ITEMS[i.definition].food ||
              ITEMS[i.definition].water ||
              ITEMS[i.definition].knowledge,
        );
        if (!item) throw new RuleError("TargetGone");
        transfer(d, a.id, item.id, a.inventory, 1);
        p.plan.cursor++;
      }
      if (step.kind === "gather" && step.position) {
        gather(
          d,
          a,
          Math.floor(step.position.x / TILE),
          Math.floor(step.position.y / TILE),
        );
        emitSound(d, a.position, 6, a.id);
        p.plan.cursor++;
      }
      if (step.kind === "read" && step.definition) {
        const book = inventoryItems(d.world, a.inventory).find(
          (i) => i.definition === step.definition,
        );
        if (!book) throw new RuleError("ItemMissing");
        executeAction(d, a, "Read", { item: book.id });
        p.plan.cursor++;
      }
      if (step.kind === "build" && step.definition && step.position) {
        executeAction(d, a, "Build", {
          definition: step.definition,
          ...step.position,
        });
        p.plan.cursor++;
      }
      if (step.kind === "craft" && step.definition) {
        executeAction(d, a, "Craft", { definition: step.definition });
        p.plan.cursor++;
      }
      if (step.kind === "research" && step.definition) {
        executeAction(d, a, "Research", { definition: step.definition });
        p.plan.cursor++;
      }
      if (step.kind === "wait") p.plan.cursor++;
      if (step.kind === "scout") {
        const dir = hash(`${a.id}/${Math.floor(d.header.tick / 200)}`) % 4;
        moveToward(
          d,
          a,
          {
            x: a.position.x + [4, -4, 0, 0][dir] * TILE,
            y: a.position.y + [0, 0, 4, -4][dir] * TILE,
          },
          130,
        );
      }
      p.memories = p.memories.slice(-30);
      parent.absorb(d);
    } catch (e) {
      if (!(e instanceof RuleError)) throw e;
      p.plan.failures++;
      p.plan.reason = e.code;
      p.plan.retryAt = d.header.tick + Math.min(600, 40 * p.plan.failures);
      p.plan.steps = [];
      p.memories.push({ tick: d.header.tick, kind: e.code });
      parent.edit("actors", old.id).profile = p;
    }
  }
}
function stepCombatAndMovement(d: Draft): void {
  const humans = Object.values(d.world.actors).filter(
    (a) => a.life === "Alive" && (a.kind === "player" || a.kind === "npc"),
  );
  const players = humans.filter((a) => a.kind === "player");
  if (d.header.tick % 10 === 1)
    for (const p of players)
      for (const m of nearbyMembers(d.world, p.position, 22))
        materialize(d, m.cohort, m.index);
  if (d.header.tick % 10 === 0) {
    let budget = 16;
    for (const c of Object.values(d.world.cohorts)) {
      for (const [index, heard] of Object.entries(c.heard)) {
        if (budget <= 0) break;
        if (
          d.header.tick - heard.tick < 800 &&
          !c.removed.includes(Number(index))
        ) {
          materialize(d, c.id, Number(index));
          budget--;
        }
      }
      if (budget <= 0) break;
    }
  }
  for (const original of Object.values(d.world.actors))
    if (original.life === "Alive") {
      if (
        original.kind === "player" &&
        !d.world.vehicles[original.mountedOn ?? ""] &&
        (original.intent.x || original.intent.y) &&
        original.readyAt <= d.header.tick
      ) {
        const a = d.edit("actors", original.id),
          speed =
            (a.sneaking ? 16 : 32) /
            Math.max(1, Math.hypot(a.intent.x, a.intent.y));
        const p = {
          x: Math.round(a.position.x + a.intent.x * speed),
          y: Math.round(a.position.y + a.intent.y * speed),
        };
        if (
          passable(
            d.world,
            p,
            countItem(d.world, a.inventory, "raft") ? "raft" : "walk",
          )
        )
          a.position = p;
        if (d.header.tick % 10 === 0)
          emitSound(d, a.position, a.sneaking ? 2 : 5, a.id);
        if (a.mountedOn) {
          const mount = d.world.actors[a.mountedOn];
          if (mount?.life === "Alive")
            d.edit("actors", mount.id).position = { ...a.position };
          else a.mountedOn = undefined;
        }
      }
      if (
        original.kind === "infected" &&
        (!d.world.companions[original.id] ||
          d.world.companions[original.id].state === "free") &&
        d.header.tick % 4 === 0
      ) {
        const a = d.edit("actors", original.id);
        const targets = humans.filter(
          (h) =>
            h.life === "Alive" &&
            distance(h.position, a.position) < 7 &&
            clearLine(d.world, a.position, h.position),
        );
        const target = targets.sort(
          (x, y) =>
            distance(x.position, a.position) - distance(y.position, a.position),
        )[0];
        if (
          target &&
          distance(target.position, a.position) < 1.4 &&
          a.readyAt <= d.header.tick
        ) {
          hurt(d, target.id, 8, "感染体袭击");
          a.readyAt = d.header.tick + 24;
        } else if (target) moveToward(d, a, target.position, 36);
        else if (a.heard && d.header.tick - a.heard.tick < 800)
          moveToward(d, a, a.heard.position, 32);
      }
    }
}
function stepBuildings(d: Draft): void {
  if (d.header.tick % 20) return;
  const generators = Object.values(d.world.buildings).filter(
    (b) =>
      b.definition === "generator" &&
      b.progress === 100 &&
      b.hp > 0 &&
      b.powered,
  );
  for (const old of generators) {
    const b = d.edit("buildings", old.id);
    if (b.storedEnergy <= 0) {
      if (countItem(d.world, b.inventory, "fuel")) {
        take(d, b.inventory, "fuel", 1);
        b.storedEnergy = 500;
      } else {
        b.powered = false;
        continue;
      }
    }
    b.storedEnergy = Math.max(0, b.storedEnergy - 1);
    emitSound(d, b.position, 30, b.owner);
  }
  for (const old of Object.values(d.world.buildings))
    if (old.hp > 0 && old.progress === 100) {
      const def = BUILDINGS[old.definition];
      if (def.power) {
        const gen = generators.find(
          (g) =>
            g.powered &&
            d.world.buildings[g.id].storedEnergy > 0 &&
            distance(g.position, old.position) <= 8,
        );
        const b = d.edit("buildings", old.id);
        b.powered = !!gen;
        if (gen)
          d.edit("buildings", gen.id).storedEnergy = Math.max(
            0,
            d.world.buildings[gen.id].storedEnergy - def.power,
          );
      }
      if (def.occupation) {
        const enemies = Object.values(d.world.actors).some(
          (a) =>
            a.kind === "infected" &&
            a.life === "Alive" &&
            !d.world.companions[a.id] &&
            distance(a.position, old.position) <= def.occupation!,
        );
        const cohort =
          nearbyMembers(d.world, old.position, def.occupation).length > 0;
        if (!old.occupied && !enemies && !cohort)
          d.edit("buildings", old.id).occupied = true;
      }
    }
}
function stepCompanions(d: Draft): void {
  for (const old of Object.values(d.world.companions)) {
    if (old.state === "dead" || old.state === "free") continue;
    const prior = d.world.actors[old.id];
    if (!prior || prior.life === "Dead") continue;
    const c = d.edit("companions", old.id),
      a = d.edit("actors", old.id),
      owner = c.controller ? d.world.actors[c.controller] : undefined;
    if (d.header.tick - c.maintenanceTick >= 600) {
      c.maintenanceTick = d.header.tick;
      const caretaker = d.world.actors[c.owner];
      const cost = c.type === "pet" ? "food" : "stabilizer";
      if (
        caretaker?.life === "Alive" &&
        distance(caretaker.position, a.position) <= 4 &&
        countItem(d.world, caretaker.inventory, cost) > 0
      ) {
        take(d, caretaker.inventory, cost, 1);
        c.stability = Math.min(100, c.stability + 5);
      } else {
        c.stability = Math.max(0, c.stability - 8);
        d.event("Maintenance", `${a.name} 缺少维护补给`, c.owner);
      }
    }
    if (c.stability === 0) {
      c.state = "free";
      c.controller = undefined;
      d.event("ControlLost", "维护长期中断，个体已脱离控制。", c.owner);
    } else if (c.stability < 20) c.state = "emergency";
    else if (c.stability < 40 && c.state === "follow") c.state = "retreat";
    if (
      owner?.life === "Alive" &&
      ["follow", "retreat"].includes(c.state) &&
      d.header.tick % 4 === 0
    ) {
      if (distance(owner.position, a.position) > 12) {
        c.state = "emergency";
        continue;
      }
      if (distance(owner.position, a.position) > 2)
        moveToward(d, a, owner.position, 52);
    }
    if (
      owner?.life === "Alive" &&
      ["follow", "guard"].includes(c.state) &&
      c.stability >= 40 &&
      d.header.tick % 8 === 0
    ) {
      const enemy = Object.values(d.world.actors).find(
        (e) =>
          e.kind === "infected" &&
          e.life === "Alive" &&
          !d.world.companions[e.id] &&
          distance(e.position, a.position) < 1.5,
      );
      if (enemy && a.readyAt <= d.header.tick) {
        hurt(d, enemy.id, 12, "伙伴攻击");
        hurt(d, a.id, 4, "感染体反击");
        emitSound(d, a.position, 8, a.id);
        a.readyAt = d.header.tick + 30;
      }
    }
  }
}
function stepDisasters(d: Draft): void {
  if (d.header.tick >= d.header.climateUntil) {
    d.header.climate = (["normal", "normal", "hot", "cold", "rain"] as const)[
      d.random("climate", 5)
    ];
    d.header.climateUntil =
      d.header.tick +
      d.header.ticksPerDay * (1 + d.random("climate-duration", 3));
    d.event("Climate", `气候转为 ${d.header.climate}`);
  }
  if (
    d.header.tick % d.header.ticksPerDay ===
      Math.floor(d.header.ticksPerDay * 0.6) &&
    d.random("disaster-roll", 4) === 0
  ) {
    const player = Object.values(d.world.actors).find(
      (a) => a.kind === "player" && a.life === "Alive",
    );
    if (player) {
      const eligible =
        d.header.biome === "coast"
          ? ["rain", "earthquake", "tornado", "tsunami"]
          : ["rain", "earthquake", "tornado"];
      const id = d.id();
      d.put("disasters", id, {
        id,
        kind: eligible[d.random("disaster-kind", eligible.length)] as "rain",
        position: { x: player.position.x + 10 * TILE, y: player.position.y },
        radius: 6,
        stage: "forecast",
        due: d.header.tick + 400,
        applied: [],
        permanent: d.random("disaster-permanent", 2) === 1,
      });
      d.event("DisasterForecast", "发现灾害征兆：请离开低地、停机并准备撤离。");
    }
  }
  for (const old of Object.values(d.world.disasters))
    if (old.stage !== "closed" && old.due <= d.header.tick) {
      const event = d.edit("disasters", old.id);
      if (event.stage === "forecast") {
        event.stage = "impact";
        event.due = d.header.tick + 200;
        const x0 = Math.floor(event.position.x / TILE),
          y0 = Math.floor(event.position.y / TILE);
        for (let y = y0 - event.radius; y <= y0 + event.radius; y++)
          for (let x = x0 - event.radius; x <= x0 + event.radius; x++) {
            const key = `${x},${y}`;
            if (event.applied.includes(key)) continue;
            const prior = d.world.terrain[key];
            const baseWater = prior?.baseWater ?? prior?.water ?? 0,
              baseBlocked =
                (prior?.baseBlocked ?? prior?.blocked ?? false) ||
                (event.permanent &&
                  event.kind === "tornado" &&
                  (x + y) % 7 === 0),
              temporary = {
                ...prior?.temporary,
                [event.id]: {
                  water: ["rain", "tsunami"].includes(event.kind) ? 100 : 0,
                  blocked:
                    !event.permanent &&
                    event.kind === "tornado" &&
                    (x + y) % 7 === 0,
                },
              };
            d.put("terrain", key, {
              elevation:
                (prior?.elevation ?? 0) +
                (event.permanent &&
                ["earthquake", "tsunami"].includes(event.kind)
                  ? -180
                  : 0),
              water: Math.max(
                baseWater,
                ...Object.values(temporary).map((t) => t.water),
              ),
              blocked:
                baseBlocked || Object.values(temporary).some((t) => t.blocked),
              damage: 50,
              revision: (prior?.revision ?? 0) + 1,
              permanent: !!prior?.permanent || event.permanent,
              source: event.id,
              baseWater,
              baseBlocked,
              temporary,
            });
            event.applied.push(key);
          }
        d.header.terrainRevision++;
        for (const m of nearbyMembers(d.world, event.position, event.radius))
          materialize(d, m.cohort, m.index);
        for (const b of Object.values(d.world.buildings))
          if (distance(b.position, event.position) <= event.radius) {
            const edit = d.edit("buildings", b.id);
            edit.hp = Math.max(0, edit.hp - 60);
            edit.revision++;
            if (edit.hp === 0) edit.occupied = false;
          }
        for (const a of Object.values(d.world.actors))
          if (
            a.life === "Alive" &&
            distance(a.position, event.position) <= event.radius
          ) {
            hurt(d, a.id, event.kind === "rain" ? 5 : 25, event.kind);
            d.edit("actors", a.id).pressure[event.kind] =
              (a.pressure[event.kind] ?? 0) + 20;
          }
        for (const c of Object.values(d.world.containers))
          if (
            !c.actor &&
            distance(c.position, event.position) <= event.radius
          ) {
            const edit = d.edit("containers", c.id);
            edit.state = event.kind === "earthquake" ? "buried" : "submerged";
            edit.revision++;
          }
        emitSound(d, event.position, 32);
        d.event("DisasterImpact", "灾害已改变地形和通路；影响会随存档保留。");
      } else if (event.stage === "impact") {
        event.stage = "recovery";
        event.due = d.header.tick + 400;
      } else {
        for (const key of event.applied) {
          const t = d.world.terrain[key];
          if (t?.temporary?.[event.id]) {
            const edit = d.edit("terrain", key);
            delete edit.temporary![event.id];
            edit.water = Math.max(
              edit.baseWater ?? 0,
              ...Object.values(edit.temporary!).map((t) => t.water),
            );
            edit.blocked =
              !!edit.baseBlocked ||
              Object.values(edit.temporary!).some((t) => t.blocked);
            edit.revision++;
          }
        }
        d.header.terrainRevision++;
        event.stage = "closed";
        d.event("DisasterClosed", "临时水位回落；永久地貌变化不会撤销。");
      }
    }
}
export function advance(world: World): Candidate | null {
  if (
    world.header.phase === "Paused" ||
    world.header.phase === "Ended" ||
    world.header.phase === "CapacityBlocked"
  )
    return null;
  const d = new Draft(world);
  if (d.header.phase === "DayBoundary") {
    placePending(d, 1000);
    return d.finish();
  }
  d.header.tick++;
  if (d.header.tick % d.header.ticksPerDay === 0) {
    beginDay(d);
    return d.finish();
  }
  stepDisasters(d);
  stepVehicles(d);
  stepCombatAndMovement(d);
  stepNeeds(d);
  stepJobs(d);
  stepNpcs(d);
  stepBuildings(d);
  stepCompanions(d);
  if (d.header.tick % 600 === 0)
    for (const old of Object.values(d.world.actors))
      if (
        old.kind === "infected" &&
        old.life === "Alive" &&
        (old.pressure.combat ?? 0) > 30 &&
        !old.traits.armor
      ) {
        const a = d.edit("actors", old.id);
        a.traits.armor = 10;
        a.pressure.combat = 0;
        d.event("Evolution", "局部战斗压力促成防御演化", a.id);
      }
  for (const r of Object.values(d.world.reservations))
    if (r.expires <= d.header.tick) {
      const task = d.world.tasks[r.job];
      if (task && !["Settled", "Cancelled"].includes(task.state)) {
        const t = d.edit("tasks", task.id);
        t.state = "Cancelled";
        t.reason = "RewardReservationExpired";
        t.revision++;
      }
      d.remove("reservations", r.id);
    }
  if (
    d.header.completedDays >= 30 &&
    !d.header.result &&
    Object.values(d.world.buildings).some(
      (b) => b.definition === "radio" && b.progress === 100 && b.powered,
    )
  ) {
    d.header.result = "已完成三十日生存与广播联络，可继续生存。";
    d.event("Milestone", d.header.result);
  }
  return d.finish();
}
