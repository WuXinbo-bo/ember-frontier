import {
  type World,
  type Command,
  type Commit,
  type Candidate,
  type Binding,
  type Vec,
  TILE,
  requireRule,
} from "../simulation/model.ts";
import { Draft } from "../simulation/transaction.ts";
import { advance, reduceCommand } from "../simulation/rules.ts";
import { assertWorld } from "../simulation/invariants.ts";
import { checksum } from "../simulation/determinism.ts";
import { makeActor, CONTENT_HASH } from "../simulation/population.ts";
import { nearbyMembers } from "../simulation/spatial.ts";
import { passable } from "../simulation/terrain.ts";
import type { PersistencePort } from "./persistence.ts";

export class Authority {
  private tail: Promise<unknown> = Promise.resolve();
  private pending?: { candidate: Candidate; batch: Commit };
  private epoch = 0;
  fault: string | null = null;
  checkpointWarning: string | null = null;
  private constructor(
    public state: World,
    readonly store: PersistencePort,
  ) {}
  static async open(
    initial: World,
    store: PersistencePort,
  ): Promise<Authority> {
    let world = await store.load(initial.header.worldId);
    if (!world) {
      await store.initialize(initial);
      world = initial;
    }
    const epoch = await store.acquire(world.header.worldId);
    world = (await store.load(world.header.worldId))!;
    try {
      requireRule(
        world.header.schema === 1 && world.header.contentHash === CONTENT_HASH,
        "SaveVersionIncompatible",
      );
      assertWorld(world, true);
    } catch (e) {
      await store.release();
      throw e;
    }
    const a = new Authority(world, store);
    a.epoch = epoch;
    return a;
  }
  private serial<T>(fn: () => Promise<T>): Promise<T> {
    const result = this.tail.then(fn);
    this.tail = result.catch(() => {});
    return result;
  }
  private async commit(candidate: Candidate): Promise<void> {
    if (candidate.world === this.state) return;
    assertWorld(candidate.world);
    const batch: Commit = {
      worldId: this.state.header.worldId,
      prev: this.state.header.seq,
      next: candidate.world.header.seq,
      batchId: `${this.epoch}/${candidate.world.header.seq}`,
      epoch: this.epoch,
      patch: candidate.patch,
      checksum: checksum(candidate.patch),
    };
    this.pending = { candidate, batch };
    try {
      await this.store.commit(batch);
    } catch (e) {
      if (!(await this.store.committed(batch.worldId, batch.batchId))) {
        this.fault = e instanceof Error ? e.message : String(e);
        throw e;
      }
    }
    this.state = candidate.world;
    this.pending = undefined;
    this.fault = null;
    if (this.state.header.seq % 200 === 0) {
      try {
        await this.store.checkpoint(this.state, this.epoch);
        this.checkpointWarning = null;
      } catch (e) {
        this.checkpointWarning = e instanceof Error ? e.message : String(e);
      }
    }
  }
  dispatch(command: Command, principal: string) {
    return this.serial(async () => {
      if (this.fault) throw new Error(`PersistenceBlocked: ${this.fault}`);
      const c = reduceCommand(this.state, command, principal);
      await this.commit(c);
      return c.receipt!;
    });
  }
  step() {
    return this.serial(async () => {
      if (this.fault) return;
      const c = advance(this.state);
      if (c) await this.commit(c);
    });
  }
  retry() {
    return this.serial(async () => {
      if (!this.pending) return;
      const { candidate, batch } = this.pending;
      try {
        await this.store.commit(batch);
      } catch (e) {
        if (!(await this.store.committed(batch.worldId, batch.batchId)))
          throw e;
      }
      this.state = candidate.world;
      this.pending = undefined;
      this.fault = null;
    });
  }
  bind(player: string, name: string) {
    return this.serial(async () => {
      if (this.fault) throw new Error(`PersistenceBlocked: ${this.fault}`);
      const d = new Draft(this.state);
      let binding = Object.values(d.world.bindings).find(
        (b) => b.player === player,
      );
      if (binding) {
        const b = d.edit("bindings", binding.id);
        b.connected = true;
        b.epoch++;
        b.sequence = 0;
        binding = b;
      } else {
        requireRule(d.header.phase !== "Ended", "WorldEnded");
        requireRule(
          Object.keys(d.world.bindings).length < 4,
          "LifetimeSeatsFull",
        );
        const host = Object.values(d.world.actors).find(
          (a) => a.kind === "player",
        )!;
        let p: Vec = { x: host.position.x + 2 * TILE, y: host.position.y };
        let n = 0;
        while (
          (!passable(d.world, p) ||
            nearbyMembers(d.world, p, 1).length > 0 ||
            Object.values(d.world.actors).some(
              (a) =>
                a.life === "Alive" &&
                Math.abs(a.position.x - p.x) < TILE &&
                Math.abs(a.position.y - p.y) < TILE,
            )) &&
          n++ < 100
        )
          p = {
            x: host.position.x + (2 + (n % 10)) * TILE,
            y: host.position.y + Math.floor(n / 10) * TILE,
          };
        requireRule(n < 100, "NoJoinPosition");
        const a = makeActor(d, "player", p);
        a.name = name.slice(0, 40);
        const id = `seat-${Object.keys(d.world.bindings).length + 1}`;
        binding = {
          id,
          actor: a.id,
          player,
          epoch: 1,
          sequence: 0,
          connected: true,
          dead: false,
          pauseVote: false,
        };
        d.put("bindings", id, binding);
      }
      await this.commit(d.finish());
      return binding;
    });
  }
  disconnect(player: string) {
    return this.serial(async () => {
      const b = Object.values(this.state.bindings).find(
        (b) => b.player === player,
      );
      if (!b) return;
      const d = new Draft(this.state);
      d.edit("bindings", b.id).connected = false;
      d.edit("actors", b.actor).intent = { x: 0, y: 0 };
      d.edit("actors", b.actor).mountedOn = undefined;
      for (const vehicle of Object.values(d.world.vehicles))
        for (const [seat, id] of Object.entries(vehicle.seats))
          if (id === b.actor) delete d.edit("vehicles", vehicle.id).seats[seat];
      for (const c of Object.values(d.world.companions))
        if (c.controller === b.actor) {
          const edit = d.edit("companions", c.id);
          edit.state = "emergency";
          edit.controller = undefined;
        }
      await this.commit(d.finish());
    });
  }
  async close() {
    await this.tail;
    try {
      await this.store.checkpoint(this.state, this.epoch);
    } finally {
      await this.store.release();
    }
  }
}
