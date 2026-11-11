import { DatabaseSync } from "node:sqlite";
import {
  type World,
  type Commit,
} from "../../../../assets/simulation/model.ts";
import {
  type PersistencePort,
  verifyCommit,
} from "../../../../assets/application/persistence.ts";
import { applyPatch } from "../../../../assets/simulation/transaction.ts";
import { checksum } from "../../../../assets/simulation/determinism.ts";
/** Optional local/dedicated Node backend. It is NOT evidence that the platform persists room disks. */
export class SqliteStore implements PersistencePort {
  readonly durability = "disk-transaction" as const;
  private db: DatabaseSync;
  constructor(path: string) {
    this.db = new DatabaseSync(path);
    this.db
      .exec(`PRAGMA busy_timeout=5000; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;
   CREATE TABLE IF NOT EXISTS worlds(id TEXT PRIMARY KEY,epoch INTEGER NOT NULL,head INTEGER NOT NULL,snapshot TEXT NOT NULL,checksum TEXT NOT NULL);
   CREATE TABLE IF NOT EXISTS commits(world TEXT NOT NULL,seq INTEGER NOT NULL,batch TEXT NOT NULL,payload TEXT NOT NULL,checksum TEXT NOT NULL,PRIMARY KEY(world,seq),UNIQUE(world,batch));`);
  }
  private atomic<T>(operation: () => T): T {
    this.db.exec("BEGIN IMMEDIATE");
    try {
      const value = operation();
      this.db.exec("COMMIT");
      return value;
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
  }
  async load(id: string): Promise<World | null> {
    return this.atomic(() => {
      const row = this.db.prepare("SELECT * FROM worlds WHERE id=?").get(id);
      if (!row) return null;
      let w = JSON.parse(String(row.snapshot)) as World;
      if (checksum(w) !== row.checksum) throw new Error("CorruptCheckpoint");
      for (const row of this.db
        .prepare(
          "SELECT payload FROM commits WHERE world=? AND seq>? ORDER BY seq",
        )
        .all(id, w.header.seq)) {
        const batch = JSON.parse(String(row.payload)) as Commit;
        verifyCommit(batch);
        if (batch.prev !== w.header.seq) throw new Error("CommittedLogGap");
        w = applyPatch(w, batch.patch);
      }
      if (w.header.seq !== row.head) throw new Error("MissingCommittedTail");
      return w;
    });
  }
  async initialize(world: World) {
    this.atomic(() => {
      const portable = JSON.parse(JSON.stringify(world)) as World;
      this.db
        .prepare("INSERT INTO worlds VALUES(?,?,?,?,?)")
        .run(
          world.header.worldId,
          0,
          world.header.seq,
          JSON.stringify(portable),
          checksum(portable),
        );
    });
  }
  async acquire(id: string) {
    return this.atomic(() => {
      const row = this.db
        .prepare("UPDATE worlds SET epoch=epoch+1 WHERE id=? RETURNING epoch")
        .get(id);
      if (!row) throw new Error("WorldMissing");
      return Number(row.epoch);
    });
  }
  async commit(batch: Commit) {
    verifyCommit(batch);
    this.atomic(() => {
      const row = this.db
        .prepare("SELECT epoch,head FROM worlds WHERE id=?")
        .get(batch.worldId);
      if (!row || row.epoch !== batch.epoch) throw new Error("WriterFenced");
      const prior = this.db
        .prepare("SELECT checksum,batch FROM commits WHERE world=? AND seq=?")
        .get(batch.worldId, batch.next);
      if (prior) {
        if (prior.batch !== batch.batchId || prior.checksum !== batch.checksum)
          throw new Error("BatchConflict");
        return;
      }
      if (row.head !== batch.prev) throw new Error("CommitConflict");
      this.db
        .prepare("INSERT INTO commits VALUES(?,?,?,?,?)")
        .run(
          batch.worldId,
          batch.next,
          batch.batchId,
          JSON.stringify(batch),
          batch.checksum,
        );
      this.db
        .prepare("UPDATE worlds SET head=? WHERE id=? AND epoch=?")
        .run(batch.next, batch.worldId, batch.epoch);
    });
  }
  async committed(id: string, batchId: string) {
    return !!this.db
      .prepare("SELECT 1 FROM commits WHERE world=? AND batch=?")
      .get(id, batchId);
  }
  async checkpoint(world: World, epoch: number) {
    this.atomic(() => {
      const row = this.db
        .prepare("SELECT epoch,head FROM worlds WHERE id=?")
        .get(world.header.worldId);
      if (!row || row.epoch !== epoch || row.head !== world.header.seq)
        throw new Error("CheckpointConflict");
      const portable = JSON.parse(JSON.stringify(world));
      this.db
        .prepare("UPDATE worlds SET snapshot=?,checksum=? WHERE id=?")
        .run(
          JSON.stringify(portable),
          checksum(portable),
          world.header.worldId,
        );
      this.db
        .prepare("DELETE FROM commits WHERE world=? AND seq<=?")
        .run(world.header.worldId, world.header.seq);
    });
  }
  async release() {
    this.db.close();
  }
}
