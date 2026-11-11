import {
  type World,
  type Header,
  type Tables,
  type TablePatch,
  type Candidate,
  type Id,
  type Event,
  type Receipt,
} from "./model.ts";
import { forkItemIndex, dirtyItem } from "./inventory-index.ts";
import { hash } from "./determinism.ts";

/** Copy only touched records. A candidate never mutates the last committed state. */
export class Draft {
  readonly world: World;
  readonly tables: TablePatch = {};
  readonly events: Event[] = [];
  readonly receipts: Record<string, Receipt | null> = {};
  private copied = new Set<keyof Tables>();
  constructor(readonly base: World) {
    this.world = { ...base, header: structuredClone(base.header) };
  }
  get header(): Header {
    return this.world.header;
  }
  put<K extends keyof Tables>(table: K, id: Id, value: Tables[K]): Tables[K] {
    if (!this.copied.has(table)) {
      (this.world[table] as Record<Id, Tables[K]>) = {
        ...this.base[table],
      } as Record<Id, Tables[K]>;
      if (table === "items") forkItemIndex(this.base.items, this.world.items);
      this.copied.add(table);
    }
    const map = (this.tables[table] ??= {} as never) as Record<
      Id,
      Tables[K] | null
    >;
    (this.world[table] as Record<Id, Tables[K]>)[id] = value;
    if (table === "items") dirtyItem(this.world.items, id);
    map[id] = value;
    return value;
  }
  edit<K extends keyof Tables>(table: K, id: Id): Tables[K] {
    const existing = (
      this.tables[table] as Record<Id, Tables[K] | null> | undefined
    )?.[id];
    if (existing) {
      if (table === "items") dirtyItem(this.world.items, id);
      return existing;
    }
    const value = this.world[table][id];
    if (!value) throw new Error(`Missing ${table}/${id}`);
    const copy =
      table === "cohorts"
        ? {
            ...value,
            slots: (value as Tables["cohorts"]).slots,
            removed: [...(value as Tables["cohorts"]).removed],
            heard: structuredClone((value as Tables["cohorts"]).heard),
          }
        : structuredClone(value);
    return this.put(table, id, copy as Tables[K]);
  }
  remove<K extends keyof Tables>(table: K, id: Id): void {
    if (!this.world[table][id]) return;
    this.edit(table, id);
    delete this.world[table][id];
    (this.tables[table] as Record<Id, null>)[id] = null;
  }
  id(): Id {
    const id = this.header.nextId;
    this.header.nextId = (BigInt(id) + 1n).toString();
    return id;
  }
  ids(count: number): Id {
    const first = this.header.nextId;
    this.header.nextId = (BigInt(first) + BigInt(count)).toString();
    return first;
  }
  random(stream: string, max: number): number {
    const n = this.header.rng[stream] ?? 0;
    this.header.rng[stream] = n + 1;
    return hash(`${this.header.seed}/${stream}/${n}`) % max;
  }
  event(kind: string, text: string, actor?: Id): void {
    this.events.push({
      id: this.id(),
      tick: this.header.tick,
      kind,
      text,
      ...(actor ? { actor, position: this.world.actors[actor]?.position } : {}),
    });
  }
  /** Merge a successful nested operation. Failed operations never touch the parent. */
  absorb(child: Draft): void {
    Object.assign(this.header, child.header);
    for (const table of Object.keys(child.tables) as (keyof Tables)[])
      for (const [id, value] of Object.entries(child.tables[table]!)) {
        if (value === null) this.remove(table, id);
        else this.put(table, id, value as never);
      }
    this.events.push(...child.events);
  }
  finish(receipt?: Receipt, receiptKey = receipt?.commandId): Candidate {
    this.header.seq = this.base.header.seq + 1;
    if (receipt) {
      receipt.seq = this.header.seq;
      this.receipts[receiptKey!] = receipt;
    }
    this.world.events = [...this.base.events, ...this.events].slice(-128);
    this.world.receipts = { ...this.base.receipts };
    for (const [key, value] of Object.entries(this.receipts))
      if (value) this.world.receipts[key] = value;
    // Binding sequence high-water marks prevent replay after the receipt cache expires.
    for (const key of Object.keys(this.world.receipts).slice(0, -256)) {
      delete this.world.receipts[key];
      this.receipts[key] = null;
    }
    return {
      world: this.world,
      patch: {
        header: this.header,
        tables: this.tables,
        events: this.events,
        receipts: this.receipts,
      },
      receipt,
    };
  }
}
export function applyPatch(world: World, patch: Candidate["patch"]): World {
  const next = {
    ...world,
    header: patch.header,
    events: [...world.events, ...patch.events].slice(-128),
    receipts: { ...world.receipts },
  };
  for (const [key, value] of Object.entries(patch.receipts)) {
    if (value === null) delete next.receipts[key];
    else next.receipts[key] = value;
  }
  for (const table of Object.keys(patch.tables) as (keyof Tables)[]) {
    const map = { ...world[table] } as Record<Id, Tables[keyof Tables]>;
    for (const [id, value] of Object.entries(patch.tables[table]!))
      if (value === null) delete map[id];
      else map[id] = value;
    (next[table] as Record<Id, Tables[keyof Tables]>) = map;
  }
  return next;
}
