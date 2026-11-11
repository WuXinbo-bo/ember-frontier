import { type World, type Commit } from "../simulation/model.ts";
import { applyPatch } from "../simulation/transaction.ts";
import { checksum } from "../simulation/determinism.ts";

export interface PersistencePort {
  readonly durability:
    | "browser-transaction"
    | "session-only"
    | "disk-transaction";
  load(worldId: string): Promise<World | null>;
  initialize(world: World): Promise<void>;
  acquire(worldId: string): Promise<number>;
  commit(batch: Commit): Promise<void>;
  committed(worldId: string, batchId: string): Promise<boolean>;
  checkpoint(world: World, epoch: number): Promise<void>;
  release(): Promise<void>;
}
export function verifyCommit(batch: Commit): void {
  if (
    checksum(batch.patch) !== batch.checksum ||
    batch.patch.header.seq !== batch.next ||
    batch.next !== batch.prev + 1
  )
    throw new Error("CorruptCommittedBatch");
}
/** Session adapter is deliberately labelled non-durable. Used for official rooms until the platform persistence gate passes. */
export class MemoryStore implements PersistencePort {
  readonly durability = "session-only" as const;
  worlds = new Map<string, World>();
  epochs = new Map<string, number>();
  batches = new Map<string, Commit>();
  failNext = false;
  loseNextAck = false;
  async load(id: string) {
    return this.worlds.get(id) ?? null;
  }
  async initialize(world: World) {
    if (this.worlds.has(world.header.worldId))
      throw new Error("WorldAlreadyExists");
    this.worlds.set(world.header.worldId, world);
  }
  async acquire(id: string) {
    const epoch = (this.epochs.get(id) ?? 0) + 1;
    this.epochs.set(id, epoch);
    return epoch;
  }
  async commit(batch: Commit) {
    verifyCommit(batch);
    if (this.epochs.get(batch.worldId) !== batch.epoch)
      throw new Error("WriterFenced");
    const key = `${batch.worldId}/${batch.batchId}`;
    const prev = this.batches.get(key);
    if (prev) {
      if (prev.checksum !== batch.checksum) throw new Error("BatchConflict");
      return;
    }
    if (this.failNext) {
      this.failNext = false;
      throw new Error("InjectedStorageFailure");
    }
    const world = this.worlds.get(batch.worldId);
    if (!world || world.header.seq !== batch.prev)
      throw new Error("CommitConflict");
    this.worlds.set(batch.worldId, applyPatch(world, batch.patch));
    this.batches.set(key, batch);
    if (this.loseNextAck) {
      this.loseNextAck = false;
      throw new Error("LostAcknowledgment");
    }
  }
  async committed(id: string, batchId: string) {
    return this.batches.has(`${id}/${batchId}`);
  }
  async checkpoint(world: World, epoch: number) {
    if (this.epochs.get(world.header.worldId) !== epoch)
      throw new Error("WriterFenced");
    for (const [key, b] of this.batches)
      if (b.worldId === world.header.worldId && b.next < world.header.seq - 100)
        this.batches.delete(key);
  }
  async release() {}
}
