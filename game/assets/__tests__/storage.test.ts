import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { afterEach, describe, expect, it } from "vitest";
import { createWorld } from "../simulation/population.ts";
import { Authority } from "../application/authority.ts";
import { SqliteStore } from "../../game/server/source/persistence/sqlite.ts";
import { exportSave } from "../application/save-file.ts";
const folders: string[] = [];
afterEach(async () => {
  for (const p of folders.splice(0))
    await rm(p, { recursive: true, force: true });
});
async function database() {
  const dir = await mkdtemp(join(tmpdir(), "ember-store-test-"));
  folders.push(dir);
  return join(dir, "world.sqlite");
}
describe("real Node disk transactions", () => {
  it("reopens the committed world after an abrupt process exit without close/checkpoint", async () => {
    const file = await database();
    const script = `import {createWorld} from './assets/simulation/population.ts';import {Authority} from './assets/application/authority.ts';import {SqliteStore} from './game/server/source/persistence/sqlite.ts';const a=await Authority.open(createWorld('disk-crash',{size:512,worldId:'disk-crash'}),new SqliteStore(process.argv[1]));const b=a.state.bindings['seat-1'];await a.dispatch({id:'move-before-exit',actor:b.actor,sequence:1,epoch:b.epoch,kind:'Move',data:{x:1,y:0}},'local');process.exit(0);`;
    const child = spawnSync(
      process.execPath,
      ["--import", "tsx", "--input-type=module", "-e", script, file],
      { cwd: process.cwd(), encoding: "utf8" },
    );
    expect(child.status, child.stderr).toBe(0);
    const store = new SqliteStore(file),
      saved = await store.load("disk-crash");
    expect(saved?.header.seq).toBe(1);
    expect(saved!.actors[saved!.bindings["seat-1"].actor].intent.x).toBe(1);
    await store.release();
  });
  it("fences a previous connection and atomically compacts checkpoints", async () => {
    const file = await database(),
      w = createWorld("sqlite-fencing", { size: 512 }),
      store = new SqliteStore(file),
      a = await Authority.open(w, store),
      other = new SqliteStore(file);
    await other.acquire(w.header.worldId);
    const b = w.bindings["seat-1"];
    await expect(
      a.dispatch(
        {
          id: "old-writer",
          actor: b.actor,
          epoch: 1,
          sequence: 1,
          kind: "Move",
          data: { x: 1, y: 0 },
        },
        "local",
      ),
    ).rejects.toThrow("WriterFenced");
    expect((await other.load(w.header.worldId))?.header.seq).toBe(0);
    await store.release();
    const fresh = await Authority.open(w, other);
    await fresh.step();
    const before = exportSave(fresh.state);
    await fresh.close();
    const reopened = new SqliteStore(file);
    expect(exportSave((await reopened.load(w.header.worldId))!)).toBe(before);
    await reopened.release();
  });
});
