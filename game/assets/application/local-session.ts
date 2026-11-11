import { Authority } from "./authority.ts";
import { IndexedDbStore } from "../adapters/indexeddb.ts";
import { createWorld } from "../simulation/population.ts";
import { project } from "./projection.ts";
import { importSave } from "./save-file.ts";
import type { Command, Header } from "../simulation/model.ts";
/** Engine-owned local authority. Never imports a room API. */
export class LocalSession {
  authority?: Authority;
  private tail: Promise<unknown> = Promise.resolve();
  async open(seed: string, biome: Header["biome"], worldId?: string) {
    await this.close();
    const store = await new IndexedDbStore().open();
    try {
      this.authority = await Authority.open(
        (worldId ? await store.load(worldId) : null) ??
          createWorld(seed, { biome, owner: "local" }),
        store,
      );
    } catch (error) {
      await store.release();
      throw error;
    }
  }
  async import(text: string) {
    const w = importSave(text);
    w.header.worldId = `import-${crypto.randomUUID()}`;
    await this.close();
    const store = await new IndexedDbStore().open();
    try {
      this.authority = await Authority.open(w, store);
    } catch (e) {
      await store.release();
      throw e;
    }
  }
  view() {
    return this.authority
      ? project(this.authority.state, "local", this.authority.store.durability)
      : undefined;
  }
  action(
    kind: string,
    data: Record<string, unknown>,
    expected?: Command["expected"],
  ) {
    const operation = this.tail.then(async () => {
      const a = this.authority;
      if (!a) throw new Error("WorldNotOpen");
      const b = Object.values(a.state.bindings).find(
        (b) => b.player === "local",
      )!;
      return a.dispatch(
        {
          id: `local/${b.epoch}/${a.state.header.seq + 1}/${kind}`,
          actor: b.actor,
          sequence: b.sequence + 1,
          epoch: b.epoch,
          kind,
          data,
          expected,
        },
        "local",
      );
    });
    this.tail = operation.catch(() => {});
    return operation;
  }
  async close() {
    await this.tail;
    if (this.authority) {
      const a = this.authority;
      this.authority = undefined;
      await a.close();
    }
  }
}
