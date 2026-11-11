import { describe, it, expect, beforeAll } from "vitest";
import {
  createWorld,
  beginDay,
  placePending,
  materialize,
  memberId,
  slotPosition,
} from "../simulation/population.ts";
import { Draft, applyPatch } from "../simulation/transaction.ts";
import { type World, type Command, TILE } from "../simulation/model.ts";
import { audit } from "../simulation/invariants.ts";
import {
  reduceCommand,
  die,
  hurt,
  advance,
  stepJobs,
  controlBudget,
} from "../simulation/rules.ts";
import {
  ITEMS,
  RESEARCH,
  SKILLS,
  validateContent,
} from "../content/catalog.ts";
import { countItem, newContainer, addItem } from "../simulation/inventory.ts";
import { receiverSet, soundField } from "../simulation/acoustics.ts";
import { choosePlan } from "../simulation/cognition.ts";
import { tileAt, passable, findPath } from "../simulation/terrain.ts";
import { stable } from "../simulation/determinism.ts";
import { Authority } from "../application/authority.ts";
import { MemoryStore } from "../application/persistence.ts";
import { project } from "../application/projection.ts";

let baseline: World;
beforeAll(() => {
  baseline = createWorld("acceptance-baseline", { size: 512, biome: "inland" });
});
const fixture = () => structuredClone(baseline);
const self = (w: World) => w.actors[w.bindings["seat-1"].actor];
function cmd(
  w: World,
  kind: string,
  data: Record<string, unknown>,
  id = "test-1",
): Command {
  const b = w.bindings["seat-1"];
  return {
    id,
    actor: b.actor,
    sequence: b.sequence + 1,
    epoch: b.epoch,
    kind,
    data,
  };
}
function supplies(w: World, items: Record<string, number>): World {
  const d = new Draft(w);
  for (const [id, n] of Object.entries(items))
    addItem(d, self(w).inventory, id, n, "fixture");
  return d.finish().world;
}

describe("content and baseline invariants", () => {
  it("defines 33 skills and 13 independent branches with validated costs", () => {
    expect(Object.keys(SKILLS)).toHaveLength(33);
    expect(Object.keys(RESEARCH)).toHaveLength(39);
    expect(validateContent()).toEqual([]);
  });
  it("A19/A20/A23: has 99 complete blank NPCs, 10000 infected and no camps", () => {
    expect(baseline.header.npc.alive).toBe(99);
    expect(baseline.header.infected.alive).toBe(10000);
    expect(Object.keys(baseline.buildings)).toHaveLength(0);
    for (const a of Object.values(baseline.actors).filter(
      (a) => a.kind === "player" || a.kind === "npc",
    )) {
      expect(a.hp).toBe(100);
      expect(Object.values(a.skills).every((v) => v === 0)).toBe(true);
      expect(a.knowledge).toEqual([]);
    }
    expect(audit(baseline, true)).toEqual([]);
  });
  it("same seed reproduces the complete initial world", () => {
    expect(
      stable(
        createWorld("acceptance-baseline", { size: 512, biome: "inland" }),
      ),
    ).toBe(stable(baseline));
  });
  it("materialization preserves membership, identity and exact location", () => {
    const w = fixture(),
      d = new Draft(w),
      c = Object.values(w.cohorts)[0],
      p = slotPosition(w, c.slots[0]);
    const a = materialize(d, c.id, 0);
    expect(a.id).toBe(memberId(c.first, 0));
    expect(a.position).toEqual(p);
    expect(d.header.infected.alive).toBe(10000);
    expect(() => materialize(d, c.id, 0)).toThrow("MemberUnavailable");
    expect(audit(d.finish().world, true)).toEqual([]);
  });
  it("does not mutate the committed input when a draft edits records", () => {
    const w = fixture(),
      before = stable(w),
      d = new Draft(w);
    hurt(d, self(w).id, 8, "fixture");
    expect(stable(w)).toBe(before);
    expect(self(d.world).hp).toBe(92);
  });
});
describe("commands and material conservation", () => {
  it("binds commands to authenticated player rather than payload identity", () => {
    const w = fixture();
    expect(
      reduceCommand(w, cmd(w, "Move", { x: 1, y: 0 }), "intruder").receipt
        ?.code,
    ).toBe("Unauthorized");
  });
  it.each([NaN, Infinity, 1.2, 2, -2, "1"])(
    "rejects malformed movement value %s",
    (x) => {
      const w = fixture();
      expect(
        reduceCommand(w, cmd(w, "Move", { x, y: 0 }), "local").receipt?.ok,
      ).toBe(false);
    },
  );
  it("does not accept authority-only commands from the client", () => {
    const w = fixture();
    expect(
      reduceCommand(w, cmd(w, "CommitModification", {}), "local").receipt?.code,
    ).toBe("UnknownCommand");
  });
  it("replays the original receipt for an identical command", () => {
    const w = fixture(),
      c = cmd(w, "Move", { x: 1, y: 0 }),
      r = reduceCommand(w, c, "local"),
      again = reduceCommand(r.world, c, "local");
    expect(again.world).toBe(r.world);
    expect(again.receipt).toEqual(r.receipt);
  });
  it("rejects command-id reuse with another payload", () => {
    const w = fixture(),
      c = cmd(w, "Move", { x: 1, y: 0 }),
      r = reduceCommand(w, c, "local");
    expect(() =>
      reduceCommand(r.world, { ...c, data: { x: 0, y: 1 } }, "local"),
    ).toThrow("CommandIdReused");
  });
  it("rejects stale session epochs", () => {
    const w = fixture(),
      c = cmd(w, "Move", { x: 1, y: 0 });
    c.epoch = 2;
    expect(reduceCommand(w, c, "local").receipt?.code).toBe("StaleSession");
  });
  it("requires explicit versions for item movement", () => {
    const w = fixture(),
      item = Object.values(w.items)[0];
    expect(
      reduceCommand(
        w,
        cmd(w, "Transfer", {
          item: item.id,
          destination: self(w).inventory,
          amount: 1,
        }),
        "local",
      ).receipt?.code,
    ).toBe("VersionsRequired");
  });
  it("atomically transfers one real stack and detects a stale competing read", () => {
    const w = fixture(),
      d = new Draft(w),
      a = self(w),
      dest = newContainer(d, a.position);
    const prepared = d.finish().world;
    const item = Object.values(prepared.items).find(
      (i) => i.container === a.inventory && i.definition === "cloth",
    )!;
    const c = cmd(prepared, "Transfer", {
      item: item.id,
      destination: dest,
      amount: 1,
    });
    c.expected = {
      [item.id]: item.revision,
      [item.container]: prepared.containers[item.container].revision,
      [dest]: 0,
    };
    const result = reduceCommand(prepared, c, "local");
    expect(result.receipt?.ok).toBe(true);
    expect(countItem(result.world, dest, "cloth")).toBe(1);
    expect(countItem(result.world, a.inventory, "cloth")).toBe(1);
    const stale = { ...c, id: "competing", sequence: c.sequence + 1 };
    expect(reduceCommand(result.world, stale, "local").receipt?.code).toBe(
      "VersionConflict",
    );
  });
  it("missing crafting materials roll back the entire attempted input reservation", () => {
    const w = fixture(),
      before = stable(w.items),
      r = reduceCommand(w, cmd(w, "Craft", { definition: "spear" }), "local");
    expect(r.receipt?.code).toBe("MissingMaterial");
    expect(stable(r.world.items)).toBe(before);
    expect(r.world.jobs).toEqual({});
  });
  it("reading the same knowledge cannot grant repeated skill experience", () => {
    let w = supplies(fixture(), { book_tech: 1 });
    const book = Object.values(w.items).find(
      (i) => i.container === self(w).inventory && i.definition === "book_tech",
    )!;
    w = reduceCommand(w, cmd(w, "Read", { item: book.id }), "local").world;
    for (let n = 0; n < 200; n++) {
      const work = new Draft(w);
      work.header.tick++;
      stepJobs(work);
      w = work.finish().world;
    }
    const xp = self(w).skills.learning;
    const r = reduceCommand(
      w,
      cmd(w, "Read", { item: book.id }, "read-again"),
      "local",
    );
    expect(r.receipt?.code).toBe("AlreadyRead");
    expect(self(r.world).skills.learning).toBe(xp);
  });
  it("A33: a gun cannot produce a hit without actual ammunition", () => {
    let w = supplies(fixture(), { pistol: 1 });
    const d = new Draft(w),
      c = Object.values(w.cohorts)[0],
      z = materialize(d, c.id, 0);
    z.position = { x: self(w).position.x + TILE, y: self(w).position.y };
    w = d.finish().world;
    const weapon = Object.values(w.items).find(
      (i) => i.container === self(w).inventory && i.definition === "pistol",
    )!;
    const r = reduceCommand(
      w,
      cmd(w, "Attack", { target: z.id, weapon: weapon.id }),
      "local",
    );
    expect(r.receipt?.code).toBe("MissingMaterial");
    expect(r.world.actors[z.id].hp).toBe(60);
  });
});
describe("permanent death and recovery truth", () => {
  it("A11/A12: transfers all original items to one persistent loot container", () => {
    const w = fixture(),
      a = self(w),
      ids = Object.values(w.items)
        .filter((i) => i.container === a.inventory)
        .map((i) => i.id)
        .sort(),
      d = new Draft(w);
    die(d, a.id, "test");
    const r = d.finish();
    expect(r.world.deaths[a.id].originalItems.sort()).toEqual(ids);
    for (const id of ids)
      expect(r.world.items[id].container).toBe(r.world.deaths[a.id].loot);
    expect(r.world.bindings["seat-1"].dead).toBe(true);
    expect(
      reduceCommand(r.world, cmd(r.world, "Move", { x: 1, y: 0 }), "local")
        .receipt?.code,
    ).toBe("ActorDead");
    expect(audit(r.world, true)).toEqual([]);
  });
  it("death is idempotent and decrements only the correct population", () => {
    const w = fixture(),
      npc = Object.values(w.actors).find((a) => a.kind === "npc")!,
      d = new Draft(w);
    die(d, npc.id, "test");
    die(d, npc.id, "repeat");
    expect(d.header.npc.deaths).toBe(1);
    expect(d.header.npc.alive).toBe(98);
    expect(d.header.infected.alive).toBe(10000);
  });
  it("redo patches reproduce tick, position and outcomes without replaying events", () => {
    const w = fixture(),
      d = new Draft(w);
    d.header.tick = 100;
    d.edit("actors", self(w).id).position.x += TILE;
    die(d, self(w).id, "test");
    const c = d.finish();
    expect(stable(applyPatch(w, c.patch))).toBe(stable(c.world));
  });
  it("failed persistence holds the last committed state and retries the same batch", async () => {
    const w = fixture(),
      store = new MemoryStore(),
      authority = await Authority.open(w, store);
    store.failNext = true;
    await expect(
      authority.dispatch(cmd(w, "Move", { x: 1, y: 0 }), "local"),
    ).rejects.toThrow("InjectedStorageFailure");
    expect(authority.state).toBe(w);
    await authority.step();
    expect(authority.state.header.tick).toBe(0);
    await authority.retry();
    expect(authority.state.header.seq).toBe(1);
    expect(self(authority.state).intent.x).toBe(1);
  });
  it("a lost acknowledgement does not apply a committed consumption twice", async () => {
    const w = fixture(),
      store = new MemoryStore(),
      authority = await Authority.open(w, store);
    const food = Object.values(w.items).find(
      (i) => i.container === self(w).inventory && i.definition === "food",
    )!;
    store.loseNextAck = true;
    const c = cmd(w, "Consume", { item: food.id });
    await authority.dispatch(c, "local");
    await authority.dispatch(c, "local");
    expect(countItem(authority.state, self(w).inventory, "food")).toBe(0);
    expect(authority.state.header.seq).toBe(1);
  });
  it("storage rejects an older writer epoch", async () => {
    const w = fixture(),
      store = new MemoryStore(),
      a = await Authority.open(w, store);
    await store.acquire(w.header.worldId);
    await expect(
      a.dispatch(cmd(w, "Move", { x: 1, y: 0 }), "local"),
    ).rejects.toThrow("WriterFenced");
    expect(a.state.header.seq).toBe(0);
  });
  it("serializes simultaneous requests across an async commit barrier", async () => {
    const w = fixture(),
      s = new MemoryStore(),
      a = await Authority.open(w, s);
    await Promise.all([
      a.dispatch(cmd(w, "Move", { x: 1, y: 0 }), "local"),
      a.dispatch(
        { ...cmd(w, "Move", { x: 0, y: 1 }, "second"), sequence: 2 },
        "local",
      ),
    ]);
    expect(a.state.header.seq).toBe(2);
    expect(self(a.state).intent).toEqual({ x: 0, y: 1 });
  });
});
describe("population, terrain and acoustics", () => {
  it("A21/A22: day accounting is unique and placement blocks normal time", () => {
    const w = fixture(),
      d = new Draft(w);
    d.header.tick = d.header.ticksPerDay;
    beginDay(d);
    expect(() => beginDay(d)).toThrow();
    expect(d.header.npc.pending).toBe(100);
    expect(d.header.infected.pending).toBe(10000);
    expect(d.header.phase).toBe("DayBoundary");
    const mid = d.finish().world,
      step = advance(mid)!;
    expect(step.world.header.tick).toBe(mid.header.tick);
    expect(step.world.header.npc.alive).toBe(199);
    let out = step.world;
    while (out.header.phase === "DayBoundary") out = advance(out)!.world;
    expect(out.header.infected.placed).toBe(20000);
    expect(audit(out, true)).toEqual([]);
  });
  it("partial sound coverage equals fully expanded membership", () => {
    const w = fixture(),
      source = self(w).position,
      budget = 9,
      field = soundField(w, source, budget),
      expected = new Set<string>();
    for (const a of Object.values(w.actors))
      if (
        field.has(
          `${Math.floor(a.position.x / TILE)},${Math.floor(a.position.y / TILE)}`,
        )
      )
        expected.add(a.id);
    for (const c of Object.values(w.cohorts))
      c.slots.forEach((slot, i) => {
        const p = slotPosition(w, slot);
        if (field.has(`${Math.floor(p.x / TILE)},${Math.floor(p.y / TILE)}`))
          expected.add(memberId(c.first, i));
      });
    expect(receiverSet(w, source, budget)).toEqual(expected);
  });
  it("A05: even the minimum nonzero sound is deterministic", () => {
    const w = fixture();
    expect(receiverSet(w, self(w).position, 1)).toEqual(
      receiverSet(w, self(w).position, 1),
    );
    expect(receiverSet(w, self(w).position, 1).has(self(w).id)).toBe(true);
  });
  it("A48/A50/A51: permanent subsidence remains after temporary water recedes", () => {
    const w = fixture(),
      d = new Draft(w),
      p = self(w).position,
      x = Math.floor(p.x / TILE),
      y = Math.floor(p.y / TILE),
      key = `${x},${y}`;
    d.put("terrain", key, {
      elevation: -400,
      water: 100,
      blocked: false,
      damage: 0,
      revision: 1,
      permanent: true,
      source: "quake",
    });
    const submerged = d.finish().world;
    const clear = new Draft(submerged);
    clear.edit("terrain", key).water = 0;
    const after = clear.finish().world;
    expect(tileAt(after, x, y).water).toBeGreaterThan(40);
    expect(passable(after, p)).toBe(false);
    expect(findPath(after, { x: p.x - TILE, y: p.y }, p)).toBeNull();
  });
  it("A69/A71: animal and bio budgets use max, never add", () => {
    const a = structuredClone(self(fixture()));
    a.skills.taming = 200;
    a.knowledge = ["bio.control.3"];
    expect(controlBudget(a)).toBe(6);
    a.skills.taming = 0;
    expect(controlBudget(a)).toBe(6);
    a.knowledge = [];
    expect(controlBudget(a)).toBe(0);
  });
});
describe("belief isolation and network projections", () => {
  it("planner chooses a real known supply target with an explanation", () => {
    const p = choosePlan(
      [
        {
          id: "box",
          kind: "resource",
          position: { x: 256, y: 256 },
          tick: 1,
          source: "self",
          confidence: 100,
        },
      ],
      {
        position: { x: 0, y: 0 },
        food: 10,
        water: 10,
        hp: 100,
        fatigue: 0,
        caution: 10,
        sociability: 20,
        ambition: 30,
        canEat: false,
        canDrink: false,
        tick: 2,
      },
    );
    expect(p.goal).toBe("supply");
    expect(p.steps[1].target).toBe("box");
  });
  it("cautious and bold NPCs choose different responses to the same known danger", () => {
    const belief = [
        {
          id: "z",
          kind: "danger" as const,
          position: { x: 5 * TILE, y: 0 },
          tick: 1,
          source: "self",
          confidence: 100,
        },
      ],
      state = {
        position: { x: 0, y: 0 },
        food: 100,
        water: 100,
        hp: 100,
        fatigue: 0,
        sociability: 20,
        ambition: 30,
        canEat: false,
        canDrink: false,
        tick: 2,
      };
    expect(choosePlan(belief, { ...state, caution: 100 }).goal).toBe("retreat");
    expect(choosePlan(belief, { ...state, caution: 0 }).goal).toBe("scout");
  });
  it("does not reveal remote actors or another human inventory", () => {
    const w = fixture(),
      v = project(w, "local", "session-only");
    expect(v.actors.length).toBeLessThan(10000);
    expect(
      v.items.every((i) => v.containers.some((c) => c.id === i.container)),
    ).toBe(true);
    expect(
      v.containers.filter((c) => c.actor && c.actor !== self(w).id),
    ).toHaveLength(0);
    expect("seed" in v).toBe(false);
  });
  it("retains lifetime identity after disconnect and reconnect", async () => {
    const store = new MemoryStore(),
      a = await Authority.open(fixture(), store),
      id = self(a.state).id;
    await a.disconnect("local");
    const binding = await a.bind("local", "旅人");
    expect(binding.actor).toBe(id);
    expect(binding.epoch).toBe(2);
    expect(Object.keys(a.state.bindings)).toHaveLength(1);
  });
});
