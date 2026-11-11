import type { World } from "../simulation/model.ts";
import { checksum } from "../simulation/determinism.ts";
import { assertWorld } from "../simulation/invariants.ts";
import { CONTENT_HASH } from "../simulation/population.ts";
const tables = [
  "actors",
  "items",
  "containers",
  "cohorts",
  "terrain",
  "buildings",
  "jobs",
  "tasks",
  "reservations",
  "companions",
  "vehicles",
  "deaths",
  "bindings",
  "disasters",
  "resources",
] as const;
/** Checksum detects accidental damage; this is not a signature or anti-cheat boundary. */
export function exportSave(world: World): string {
  const portable = JSON.parse(JSON.stringify(world)) as World;
  return JSON.stringify({
    format: "ember-save-1",
    checksum: checksum(portable),
    world: portable,
  });
}
export function importSave(text: string): World {
  if (text.length > 128 * 1024 * 1024) throw new Error("SaveFileTooLarge");
  const v = JSON.parse(text, (key, value) => {
    if (["__proto__", "prototype", "constructor"].includes(key))
      throw new Error("UnsafeSaveKey");
    return value;
  });
  if (
    v?.format !== "ember-save-1" ||
    !v.world ||
    checksum(v.world) !== v.checksum
  )
    throw new Error("SaveChecksumMismatch");
  const w = v.world as World;
  if (
    w.header?.schema !== 1 ||
    w.header.contentHash !== CONTENT_HASH ||
    w.header.simVersion !== "ember-sim-1"
  )
    throw new Error("SaveVersionIncompatible");
  if (
    !tables.every(
      (t) => w[t] && typeof w[t] === "object" && !Array.isArray(w[t]),
    )
  )
    throw new Error("SaveSchemaInvalid");
  if (
    !Number.isSafeInteger(w.header.tick) ||
    w.header.tick < 0 ||
    !Number.isSafeInteger(w.header.seq) ||
    w.header.seq < 0 ||
    !Array.isArray(w.events)
  )
    throw new Error("SaveSchemaInvalid");
  if (
    Object.values(w.bindings).length !== 1 ||
    Object.values(w.bindings)[0].player !== "local"
  )
    throw new Error("OnlyLocalSaveImportAllowed");
  if (
    !Number.isSafeInteger(w.header.size) ||
    w.header.size < 128 ||
    w.header.size > 4096 ||
    typeof w.header.worldId !== "string" ||
    w.header.worldId.length > 160 ||
    typeof w.header.nextId !== "string" ||
    !/^\d{1,40}$/.test(w.header.nextId) ||
    !w.receipts ||
    typeof w.receipts !== "object"
  )
    throw new Error("SaveSchemaInvalid");
  for (const table of tables)
    for (const [id, record] of Object.entries(w[table]))
      if (
        !record ||
        typeof record !== "object" ||
        ("id" in record && record.id !== id)
      )
        throw new Error("SaveSchemaInvalid");
  assertWorld(w, true);
  return w;
}
