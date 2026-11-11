import { beforeAll, describe, expect, it } from "vitest";
import { createWorld, materialize } from "../simulation/population.ts";
import { Draft, applyPatch } from "../simulation/transaction.ts";
import { reduceCommand, stepJobs, die, advance } from "../simulation/rules.ts";
import { type World, type Command, TILE } from "../simulation/model.ts";
import {
  addItem,
  countItem,
  newContainer,
  weight,
} from "../simulation/inventory.ts";
import { resourceAt } from "../simulation/environment.ts";
import { passable } from "../simulation/terrain.ts";
import { soundField } from "../simulation/acoustics.ts";
import { exportSave, importSave } from "../application/save-file.ts";
import { project } from "../application/projection.ts";
import {
  diffView,
  applyViewDelta,
  ProjectionStream,
} from "../application/replication.ts";
import { Authority } from "../application/authority.ts";
import { MemoryStore } from "../application/persistence.ts";
import { createRoomGame } from "../../game/server/source/room.ts";
import { stable, checksum } from "../simulation/determinism.ts";
let base: World;
beforeAll(() => {
  base = createWorld("architecture-contracts", { size: 512, biome: "inland" });
});
const fixture = () => structuredClone(base);
const actor = (w: World) => w.actors[w.bindings["seat-1"].actor];
const c = (
  w: World,
  kind: string,
  data: Record<string, unknown> = {},
  id?: string,
): Command => ({
  id: id ?? `test/${w.header.seq}/${kind}`,
  actor: actor(w).id,
  sequence: w.bindings["seat-1"].sequence + 1,
  epoch: w.bindings["seat-1"].epoch,
  kind,
  data,
});
const run = (w: World, kind: string, data: Record<string, unknown> = {}) =>
  reduceCommand(w, c(w, kind, data), "local");
function supply(w: World, contents: Record<string, number>) {
  const d = new Draft(w);
  for (const [id, n] of Object.entries(contents))
    addItem(d, actor(w).inventory, id, n, "test");
  return d.finish().world;
}
function work(w: World, ticks: number) {
  for (let n = 0; n < ticks; n++) {
    const d = new Draft(w);
    d.header.tick++;
    stepJobs(d);
    w = d.finish().world;
  }
  return w;
}
function building(d: Draft, def: string, x = 2) {
  const a = actor(d.world),
    id = d.id(),
    p = { x: a.position.x + x * TILE, y: a.position.y };
  d.put("buildings", id, {
    id,
    definition: def,
    position: p,
    owner: a.id,
    progress: 100,
    hp: 200,
    powered: true,
    storedEnergy: 500,
    inventory: newContainer(d, p, { owner: a.id }),
    occupied: false,
    revision: 0,
  });
  return id;
}

describe("bounded idempotency and isolation", () => {
  it("authenticated rejection advances its high-water mark; replay has no second commit", () => {
    const w = fixture(),
      input = c(w, "Craft", { definition: "spear" }),
      r = reduceCommand(w, input, "local");
    expect(r.receipt?.code).toBe("MissingMaterial");
    expect(r.world.bindings["seat-1"].sequence).toBe(input.sequence);
    expect(reduceCommand(r.world, input, "local").world).toBe(r.world);
  });
  it("another principal cannot read or poison a valid command receipt", () => {
    const w = fixture(),
      input = c(w, "Move", { x: 1, y: 0 }),
      r = reduceCommand(w, input, "local");
    expect(reduceCommand(r.world, input, "other").receipt?.code).toBe(
      "Unauthorized",
    );
    expect(reduceCommand(w, input, "other").world).toBe(w);
  });
  it("bounds receipts while rejecting replay of evicted commands", () => {
    let w = fixture();
    const first = c(w, "Move", { x: 0, y: 0 }, "original");
    w = reduceCommand(w, first, "local").world;
    for (let n = 0; n < 300; n++) w = run(w, "Move", { x: 0, y: 0 }).world;
    expect(Object.keys(w.receipts).length).toBe(256);
    expect(reduceCommand(w, first, "local").receipt?.code).toBe(
      "StaleSequence",
    );
    const next = run(w, "Move", { x: 1, y: 0 });
    expect(stable(applyPatch(w, next.patch))).toBe(stable(next.world));
  });
  it("nested failed action leaves its parent unchanged", () => {
    const d = new Draft(fixture()),
      before = stable(d.world),
      child = new Draft(d.world);
    addItem(child, actor(child.world).inventory, "scrap", 1, "candidate");
    expect(stable(d.world)).toBe(before);
    d.absorb(child);
    expect(countItem(d.world, actor(d.world).inventory, "scrap")).toBe(1);
  });
});
describe("finite resources and work", () => {
  it("depleted deposits stay depleted through portable save reload", () => {
    let w = fixture();
    let found;
    for (let y = 230; y < 280 && !found; y++)
      for (let x = 230; x < 280 && !found; x++) found = resourceAt(w, x, y);
    expect(found).toBeTruthy();
    const d = new Draft(w);
    d.edit("actors", actor(w).id).position = { ...found!.position };
    d.put("resources", found!.id, { ...found!, remaining: 1 });
    w = d.finish().world;
    w = run(w, "Gather", {
      x: found!.position.x / TILE - 0.5,
      y: found!.position.y / TILE - 0.5,
    }).world;
    expect(w.resources[found!.id].remaining).toBe(0);
    const restored = importSave(exportSave(w));
    expect(
      resourceAt(
        restored,
        found!.position.x / TILE - 0.5,
        found!.position.y / TILE - 0.5,
      ),
    ).toBeUndefined();
  });
  it("reading pauses when the original book leaves inventory and awards once", () => {
    let w = supply(fixture(), { book_tech: 1 });
    const book = Object.values(w.items).find(
      (i) => i.definition === "book_tech" && i.container === actor(w).inventory,
    )!;
    w = run(w, "Read", { item: book.id }).world;
    w = work(w, 100);
    const d = new Draft(w),
      bin = newContainer(d, actor(w).position);
    d.edit("items", book.id).container = bin;
    w = work(d.finish().world, 200);
    expect(actor(w).knowledge).not.toContain("tech");
    expect(Object.values(w.jobs)[0].reason).toBe("BookMissing");
    const back = new Draft(w);
    back.edit("items", book.id).container = actor(w).inventory;
    w = work(back.finish().world, 100);
    expect(actor(w).knowledge).toContain("tech");
    expect(actor(w).skills.learning).toBe(50);
    expect(actor(work(w, 100)).skills.learning).toBe(50);
  });
  it("craft consumes inputs once; loss of acknowledgement does not create duplicate output", () => {
    let w = supply(fixture(), { wood: 2, stone: 1 });
    w = run(w, "Craft", { definition: "spear" }).world;
    const start = w;
    w = work(w, 120);
    expect(countItem(w, actor(w).inventory, "spear")).toBe(1);
    expect(countItem(w, actor(w).inventory, "wood")).toBe(0);
    expect(countItem(work(w, 120), actor(w).inventory, "spear")).toBe(1);
    expect(countItem(start, actor(start).inventory, "wood")).toBe(0);
  });
  it("cancellation keeps excess unconsumed material at the worksite", () => {
    let w = supply(fixture(), { wood: 2, stone: 1 });
    w = run(w, "Craft", { definition: "spear" }).world;
    const d = new Draft(w);
    d.edit("containers", actor(w).inventory).capacity = weight(
      w,
      actor(w).inventory,
    );
    w = d.finish().world;
    const job = Object.values(w.jobs)[0];
    w = run(w, "CancelJob", { job: job.id }).world;
    expect(weight(w, actor(w).inventory)).toBeLessThanOrEqual(
      w.containers[actor(w).inventory].capacity,
    );
    expect(countItem(w, job.inputs, "wood")).toBe(2);
  });
  it("work pauses on power loss and resumes without recharging materials", () => {
    let w = supply(fixture(), { herb: 2, reagent: 1 });
    const d = new Draft(w);
    const lab = building(d, "biolab");
    w = run(d.finish().world, "Craft", { definition: "medicine" }).world;
    w = work(w, 60);
    const off = new Draft(w);
    off.edit("buildings", lab).powered = false;
    w = work(off.finish().world, 100);
    expect(Object.values(w.jobs)[0].done).toBe(60);
    const on = new Draft(w);
    on.edit("buildings", lab).powered = true;
    w = work(on.finish().world, 90);
    expect(countItem(w, actor(w).inventory, "medicine")).toBe(1);
    expect(Object.values(w.jobs)[0].state).toBe("Complete");
  });
  it("death prevents unfinished production and preserves real reserved inputs", () => {
    let w = supply(fixture(), { wood: 2, stone: 1 });
    w = run(w, "Craft", { definition: "spear" }).world;
    const d = new Draft(w);
    die(d, actor(w).id, "test");
    w = work(d.finish().world, 200);
    expect(countItem(w, actor(w).inventory, "spear")).toBe(0);
    expect(Object.values(w.jobs)[0].reason).toBe("ActorDead");
  });
  it("door state changes collision and acoustic reach", () => {
    const d = new Draft(fixture()),
      door = building(d, "door", 1);
    let w = d.finish().world;
    expect(passable(w, w.buildings[door].position)).toBe(false);
    const closed = soundField(w, actor(w).position, 2);
    w = run(w, "ToggleDoor", { building: door }).world;
    expect(passable(w, w.buildings[door].position)).toBe(true);
    const open = soundField(w, actor(w).position, 2);
    expect(open.size).toBeGreaterThan(closed.size);
  });
});
describe("real delivery and vehicle resources", () => {
  it("only dedicated delivery credits one task and reward settles once", () => {
    let w = supply(fixture(), { wood: 3, food: 2 });
    const d = new Draft(w),
      npc = Object.values(w.actors).find((a) => a.kind === "npc")!;
    d.edit("actors", npc.id).position = { ...actor(w).position };
    const id = d.id(),
      destination = newContainer(d, actor(w).position, { owner: npc.id });
    d.put("tasks", id, {
      id,
      issuer: npc.id,
      assignee: actor(w).id,
      kind: "collect",
      target: "wood",
      amount: 3,
      delivered: 0,
      destination,
      reward: { definition: "food", quantity: 1 },
      state: "Accepted",
      revision: 0,
    });
    w = d.finish().world;
    const delivery = run(w, "DeliverTask", { task: id });
    expect(delivery.receipt?.ok).toBe(true);
    w = delivery.world;
    expect(w.tasks[id].delivered).toBe(3);
    const settled = run(w, "SettleTask", { task: id });
    expect(settled.receipt?.ok).toBe(true);
    expect(run(settled.world, "SettleTask", { task: id }).receipt?.ok).toBe(
      false,
    );
  });
  function prepared() {
    let w = supply(fixture(), { vehicle_chassis: 1 });
    const d = new Draft(w);
    d.edit("actors", actor(w).id).knowledge.push("tech.vehicles.1");
    w = run(d.finish().world, "AssembleVehicle", { definition: "buggy" }).world;
    const setup = new Draft(w),
      v = Object.values(w.vehicles)[0],
      a = setup.edit("actors", actor(w).id);
    a.skills.driving = 50;
    a.readyAt = 0;
    const edit = setup.edit("vehicles", v.id);
    edit.modules = ["engine_module", "gun_module"];
    edit.fuel = 100;
    w = run(setup.finish().world, "EnterVehicle", { vehicle: v.id }).world;
    return { w, id: v.id };
  }
  it("vehicle weapon requires actual cargo ammunition and keeps one weapon cooldown", () => {
    let { w, id } = prepared();
    const d = new Draft(w),
      cohort = Object.values(w.cohorts)[0],
      z = materialize(d, cohort.id, 0);
    z.position = { x: actor(w).position.x + TILE, y: actor(w).position.y };
    w = d.finish().world;
    expect(run(w, "VehicleFire", { target: z.id }).receipt?.code).toBe(
      "MissingMaterial",
    );
    const ammo = new Draft(w);
    addItem(ammo, w.vehicles[id].inventory, "ammo", 2, "test");
    w = run(ammo.finish().world, "VehicleFire", { target: z.id }).world;
    expect(w.actors[z.id].hp).toBe(15);
    expect(countItem(w, w.vehicles[id].inventory, "ammo")).toBe(1);
    expect(w.vehicles[id].fuel).toBe(98);
    expect(run(w, "VehicleFire", { target: z.id }).receipt?.code).toBe(
      "Cooldown",
    );
  });
  it("death releases a vehicle seat without creating a new actor", () => {
    const { w, id } = prepared(),
      d = new Draft(w);
    die(d, actor(w).id, "test");
    const next = d.finish().world;
    expect(next.vehicles[id].seats).toEqual({});
    expect(next.actors[actor(w).id].mountedOn).toBeUndefined();
  });
});
describe("projection baseline, privacy, portable saves", () => {
  it("reconstructs an acknowledged projection and materially reduces unchanged terrain traffic", () => {
    const w = fixture(),
      before = project(w, "local", "session-only"),
      after = project(
        run(w, "Move", { x: 1, y: 0 }).world,
        "local",
        "session-only",
      );
    const delta = diffView(before, after);
    expect(stable(applyViewDelta(before, delta))).toBe(stable(after));
    expect(JSON.stringify(delta).length).toBeLessThan(
      JSON.stringify(after).length / 5,
    );
    expect(() => applyViewDelta(after, delta)).toThrow(
      "ProjectionBaselineMismatch",
    );
  });
  it("uses a snapshot on a missing baseline and forgets it on reconnect", () => {
    const w = fixture(),
      view = project(w, "local", "session-only"),
      stream = new ProjectionStream();
    expect(stream.packet(view).view).toBeTruthy();
    stream.acknowledge(view.worldId, view.seq);
    expect(stream.packet(view).delta).toBeTruthy();
    stream.reset();
    expect(stream.packet(view).view).toBeTruthy();
  });
  it("deletes entities leaving a viewer projection", () => {
    const before = project(fixture(), "local", "session-only"),
      after = {
        ...before,
        seq: before.seq + 1,
        actors: before.actors.slice(1),
      },
      delta = diffView(before, after);
    expect(applyViewDelta(before, delta).actors).toEqual(after.actors);
  });
  it("export roundtrips without rerolling IDs, knowledge or inventories", () => {
    const w = fixture();
    expect(stable(importSave(exportSave(w)))).toBe(
      stable(JSON.parse(JSON.stringify(w))),
    );
  });
  it("rejects corrupted, incompatible and online save payloads", () => {
    const w = fixture(),
      save = JSON.parse(exportSave(w));
    save.world.header.tick++;
    expect(() => importSave(JSON.stringify(save))).toThrow(
      "SaveChecksumMismatch",
    );
    w.header.contentHash = "unknown";
    expect(() => importSave(exportSave(w))).toThrow("SaveVersionIncompatible");
    const online = fixture();
    online.bindings["seat-1"].player = "remote";
    expect(() => importSave(exportSave(online))).toThrow(
      "OnlyLocalSaveImportAllowed",
    );
  });
  it("rejects prototype keys before processing untrusted imports", () => {
    expect(() => importSave('{"__proto__":{}}')).toThrow("UnsafeSaveKey");
  });
  it("checkpoint failure does not turn a durably committed command into an apparent failure", async () => {
    class Store extends MemoryStore {
      override async checkpoint() {
        throw new Error("disk-full-checkpoint");
      }
    }
    const s = new Store(),
      w = fixture();
    w.header.seq = 199;
    const a = await Authority.open(w, s);
    expect((await a.dispatch(c(w, "Move", { x: 1, y: 0 }), "local")).ok).toBe(
      true,
    );
    expect(a.state.header.seq).toBe(200);
    expect(a.checkpointWarning).toBe("disk-full-checkpoint");
    expect((await s.load(w.header.worldId))!.header.seq).toBe(200);
  });
  it("a lost acknowledgement during retry resolves the already committed batch", async () => {
    const s = new MemoryStore(),
      w = fixture(),
      a = await Authority.open(w, s);
    s.failNext = true;
    await expect(
      a.dispatch(c(w, "Move", { x: 1, y: 0 }), "local"),
    ).rejects.toThrow();
    s.loseNextAck = true;
    await a.retry();
    expect(a.fault).toBeNull();
    expect(a.state.header.seq).toBe(1);
  });
});
describe("four lifetime seats use the same Node authority", () => {
  it("rejects a fifth identity; disconnected slots remain bound and death cannot revive", async () => {
    const a = await Authority.open(fixture(), new MemoryStore());
    for (let i = 2; i <= 4; i++) await a.bind(`p${i}`, `Player ${i}`);
    await a.disconnect("p2");
    await expect(a.bind("p5", "Fifth")).rejects.toThrow("LifetimeSeatsFull");
    const original = Object.values(a.state.bindings).find(
      (b) => b.player === "p2",
    )!;
    const d = new Draft(a.state);
    die(d, original.actor, "test");
    const recovered = await Authority.open(d.finish().world, new MemoryStore());
    const back = await recovered.bind("p2", "Player 2");
    expect(back.actor).toBe(original.actor);
    expect(back.dead).toBe(true);
    expect(recovered.state.actors[back.actor].life).toBe("Dead");
  });
  it("official room adapter produces filtered snapshots and deltas for four clients", async () => {
    const players = Array.from({ length: 4 }, (_, n) => ({
      id: `p${n}`,
      name: `Player ${n}`,
      isHost: n === 0,
    }));
    const room = createRoomGame(players);
    await room.start();
    const initial = room.getState("p0") as { view: ReturnType<typeof project> };
    expect(initial.view.population.infected).toBe(10000);
    await room.applyAction("p0", {
      kind: "__view_ack",
      worldId: initial.view.worldId,
      seq: initial.view.seq,
    });
    await room.tick();
    expect((room.getDelta("p0", 0) as { delta: unknown }).delta).toBeTruthy();
    expect(room.getState("stranger")).toBeNull();
    await room.removePlayer?.("p1");
    await room.addPlayer?.(players[1]);
    expect(room.getPlayerCount()).toBe(4);
    await expect(
      room.addPlayer?.({ id: "p5", name: "Fifth", isHost: false }),
    ).rejects.toThrow("LifetimeSeatsFull");
    await room.stop();
  });
});

describe("cache rollback and snapshot safety", () => {
  it("does not leak a transferred item across a discarded candidate", () => {
    const w = fixture(),
      a = actor(w);
    expect(countItem(w, a.inventory, "cloth")).toBe(2);
    const child = new Draft(w),
      bin = newContainer(child, a.position),
      item = Object.values(w.items).find(
        (i) => i.container === a.inventory && i.definition === "cloth",
      )!;
    child.edit("items", item.id).container = bin;
    expect(countItem(child.world, bin, "cloth")).toBe(2);
    expect(countItem(w, a.inventory, "cloth")).toBe(2);
    expect(countItem(w, bin, "cloth")).toBe(0);
  });
  it("updates an already queried draft index when a record changes again", () => {
    const w = fixture(),
      d = new Draft(w),
      a = actor(w),
      bin = newContainer(d, a.position),
      item = Object.values(w.items).find(
        (i) => i.container === a.inventory && i.definition === "cloth",
      )!;
    expect(countItem(d.world, a.inventory, "cloth")).toBe(2);
    d.edit("items", item.id).container = bin;
    expect(countItem(d.world, bin, "cloth")).toBe(2);
    d.edit("items", item.id).container = a.inventory;
    expect(countItem(d.world, bin, "cloth")).toBe(0);
    expect(countItem(d.world, a.inventory, "cloth")).toBe(2);
  });
});
