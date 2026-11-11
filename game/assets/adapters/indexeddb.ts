import { type World, type Commit } from "../simulation/model.ts";
import { applyPatch } from "../simulation/transaction.ts";
import {
  type PersistencePort,
  verifyCommit,
} from "../application/persistence.ts";

interface Meta {
  id: string;
  epoch: number;
  head: number;
  snapshot: World;
}
const request = <T>(r: IDBRequest<T>) =>
  new Promise<T>((resolve, reject) => {
    r.onsuccess = () => resolve(r.result);
    r.onerror = () => reject(r.error);
  });
const done = (tx: IDBTransaction) =>
  new Promise<void>((resolve, reject) => {
    tx.oncomplete = () => resolve();
    tx.onabort = () => reject(tx.error ?? new Error("TransactionAborted"));
    tx.onerror = () => reject(tx.error);
  });
export class IndexedDbStore implements PersistencePort {
  readonly durability = "browser-transaction" as const;
  private db!: IDBDatabase;
  private unlock?: () => void;
  private lockTask?: Promise<void>;
  constructor(readonly database = "ember-frontier-worlds-v1") {}
  async open() {
    if (typeof indexedDB === "undefined")
      throw new Error("IndexedDBUnavailable");
    const r = indexedDB.open(this.database, 1);
    r.onupgradeneeded = () => {
      r.result.createObjectStore("worlds", { keyPath: "id" });
      const batches = r.result.createObjectStore("commits", {
        keyPath: ["worldId", "next"],
      });
      batches.createIndex("world", "worldId");
    };
    this.db = await request(r);
    return this;
  }
  async list() {
    const tx = this.db.transaction("worlds", "readonly");
    const values = (await request(tx.objectStore("worlds").getAll())) as Meta[];
    return values.map((m) => ({
      id: m.id,
      seed: m.snapshot.header.seed,
      biome: m.snapshot.header.biome,
      seq: m.head,
      phase: m.snapshot.header.phase,
    }));
  }
  async load(id: string): Promise<World | null> {
    const tx = this.db.transaction(["worlds", "commits"], "readonly");
    const complete = done(tx);
    const meta = (await request(tx.objectStore("worlds").get(id))) as
      | Meta
      | undefined;
    if (!meta) {
      await complete;
      return null;
    }
    const batches = (await request(
      tx.objectStore("commits").index("world").getAll(id),
    )) as Commit[];
    await complete;
    let w = meta.snapshot;
    for (const b of batches.sort((a, b) => a.next - b.next)) {
      if (b.next <= w.header.seq) continue;
      verifyCommit(b);
      if (b.prev !== w.header.seq) throw new Error("CommittedLogGap");
      w = applyPatch(w, b.patch);
    }
    if (w.header.seq !== meta.head) throw new Error("MissingCommittedTail");
    return w;
  }
  async initialize(world: World) {
    const tx = this.db.transaction("worlds", "readwrite");
    const complete = done(tx);
    tx.objectStore("worlds").add({
      id: world.header.worldId,
      epoch: 0,
      head: world.header.seq,
      snapshot: world,
    } satisfies Meta);
    await complete;
  }
  async acquire(id: string) {
    if (!navigator.locks) throw new Error("ExclusiveLocksUnavailable");
    let confirm!: (value: boolean) => void;
    const got = new Promise<boolean>((r) => (confirm = r));
    this.lockTask = navigator.locks.request(
      `ember/${id}`,
      { ifAvailable: true },
      async (lock) => {
        confirm(!!lock);
        if (lock)
          await new Promise<void>((resolve) => {
            this.unlock = resolve;
          });
      },
    );
    if (!(await got)) throw new Error("WorldOpenInAnotherTab");
    const tx = this.db.transaction("worlds", "readwrite");
    const complete = done(tx);
    const meta = (await request(tx.objectStore("worlds").get(id))) as Meta;
    meta.epoch++;
    tx.objectStore("worlds").put(meta);
    await complete;
    return meta.epoch;
  }
  async commit(batch: Commit) {
    verifyCommit(batch);
    const tx = this.db.transaction(["worlds", "commits"], "readwrite");
    const complete = done(tx);
    const meta = (await request(
      tx.objectStore("worlds").get(batch.worldId),
    )) as Meta;
    const old = (await request(
      tx.objectStore("commits").get([batch.worldId, batch.next]),
    )) as Commit | undefined;
    if (meta.epoch !== batch.epoch) {
      tx.abort();
      await complete.catch(() => {});
      throw new Error("WriterFenced");
    }
    if (old) {
      if (old.batchId !== batch.batchId || old.checksum !== batch.checksum) {
        tx.abort();
        await complete.catch(() => {});
        throw new Error("BatchConflict");
      }
      await complete;
      return;
    }
    if (meta.head !== batch.prev) {
      tx.abort();
      await complete.catch(() => {});
      throw new Error("CommitConflict");
    }
    tx.objectStore("commits").add(batch);
    meta.head = batch.next;
    tx.objectStore("worlds").put(meta);
    await complete;
  }
  async committed(id: string, batchId: string) {
    const tx = this.db.transaction("commits", "readonly");
    const all = (await request(
      tx.objectStore("commits").index("world").getAll(id),
    )) as Commit[];
    return all.some((b) => b.batchId === batchId);
  }
  async checkpoint(world: World, epoch: number) {
    const tx = this.db.transaction(["worlds", "commits"], "readwrite");
    const complete = done(tx);
    const store = tx.objectStore("worlds"),
      meta = (await request(store.get(world.header.worldId))) as Meta;
    if (meta.epoch !== epoch || meta.head !== world.header.seq) {
      tx.abort();
      await complete.catch(() => {});
      throw new Error("CheckpointConflict");
    }
    meta.snapshot = world;
    store.put(meta);
    const keys = await request(
      tx.objectStore("commits").index("world").getAllKeys(world.header.worldId),
    );
    for (const key of keys)
      if (Array.isArray(key) && Number(key[1]) <= world.header.seq)
        tx.objectStore("commits").delete(key);
    await complete;
  }
  async release() {
    this.unlock?.();
    await this.lockTask;
    this.db?.close();
  }
}
