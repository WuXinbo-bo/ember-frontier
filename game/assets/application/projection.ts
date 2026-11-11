import {
  type World,
  type Actor,
  type Building,
  type Container,
  type Item,
  type Job,
  type Task,
  type Companion,
  type Event,
  type Header,
  type Vehicle,
  TILE,
  distance,
} from "../simulation/model.ts";
import { type Tile, tileAt, clearLine } from "../simulation/terrain.ts";
import { containerPosition } from "../simulation/inventory.ts";
import { nearbyResources } from "../simulation/environment.ts";
import { nearbyMembers } from "../simulation/spatial.ts";
export type VisibleActor = Pick<
  Actor,
  "id" | "kind" | "name" | "position" | "hp" | "life" | "sex"
>;
export interface View {
  worldId: string;
  seq: number;
  tick: number;
  day: number;
  phase: Header["phase"];
  climate: string;
  population: { npc: number; infected: number; pending: number };
  self: Actor;
  binding: { epoch: number; sequence: number; dead: boolean };
  vehicles: Vehicle[];
  resources: ReturnType<typeof nearbyResources>;
  actors: VisibleActor[];
  tiles: Tile[];
  buildings: Building[];
  containers: Container[];
  items: Item[];
  jobs: Job[];
  tasks: Task[];
  companions: Companion[];
  events: Event[];
  terrainRevision: number;
  result?: string;
  durability: string;
  error?: string;
}
export function project(w: World, player: string, durability: string): View {
  const binding = Object.values(w.bindings).find((b) => b.player === player);
  if (!binding) throw new Error("NoCharacterBinding");
  const self = w.actors[binding.actor],
    radius = 22;
  const visible = (p: { x: number; y: number }) =>
    distance(p, self.position) <= radius;
  const actor = (a: VisibleActor): VisibleActor => ({
    id: a.id,
    kind: a.kind,
    name: a.name,
    position: { ...a.position },
    hp: a.hp,
    life: a.life,
    sex: a.sex,
  });
  const actors = Object.values(w.actors)
    .filter(
      (a) => visible(a.position) && clearLine(w, self.position, a.position),
    )
    .map(actor);
  for (const m of nearbyMembers(w, self.position, radius))
    if (clearLine(w, self.position, m.position))
      actors.push({
        id: m.id,
        kind: "infected",
        name: `感染体 ${m.id}`,
        position: m.position,
        hp: 60,
        life: "Alive",
        sex: "male",
      });
  const containers = Object.values(w.containers).filter(
    (c) =>
      c.id === self.inventory ||
      (!c.actor &&
        distance(containerPosition(w, c.id), self.position) <= 3 &&
        !c.owner) ||
      (c.owner === self.id && visible(c.position)),
  );
  const allowed = new Set(containers.map((c) => c.id));
  const tiles: Tile[] = [];
  const cx = Math.floor(self.position.x / TILE),
    cy = Math.floor(self.position.y / TILE);
  for (let y = cy - 18; y <= cy + 18; y++)
    for (let x = cx - 18; x <= cx + 18; x++) tiles.push(tileAt(w, x, y));
  return structuredClone({
    worldId: w.header.worldId,
    seq: w.header.seq,
    tick: w.header.tick,
    day: w.header.completedDays + 1,
    phase: w.header.phase,
    climate: w.header.climate,
    population: {
      npc: w.header.npc.alive,
      infected: w.header.infected.alive,
      pending: w.header.npc.pending + w.header.infected.pending,
    },
    self: structuredClone(self),
    vehicles: Object.values(w.vehicles).filter((v) => visible(v.position)),
    resources: nearbyResources(w, self.position, 18).filter((r) =>
      clearLine(w, self.position, r.position),
    ),
    binding: {
      epoch: binding.epoch,
      sequence: binding.sequence,
      dead: binding.dead,
    },
    actors,
    tiles,
    buildings: Object.values(w.buildings).filter((b) => visible(b.position)),
    containers,
    items: Object.values(w.items).filter(
      (i) => i.quantity > 0 && allowed.has(i.container),
    ),
    jobs: Object.values(w.jobs).filter((j) => j.actor === self.id),
    tasks: Object.values(w.tasks).filter(
      (t) =>
        t.issuer === self.id ||
        t.assignee === self.id ||
        visible(w.actors[t.issuer].position),
    ),
    companions: Object.values(w.companions).filter((c) => c.owner === self.id),
    events: w.events
      .filter((e) => !e.position || visible(e.position))
      .slice(-8),
    terrainRevision: w.header.terrainRevision,
    result: w.header.result,
    durability,
  });
}
