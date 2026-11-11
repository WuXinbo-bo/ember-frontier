/** The simulation contract contains only serializable data. Units: 1/256 tile, ticks, grams. */
export type Id = string;
export type Vec = { x: number; y: number };
export type Phase =
  | "Running"
  | "Paused"
  | "DayBoundary"
  | "CapacityBlocked"
  | "Ended";
export type ActorKind = "player" | "npc" | "infected" | "animal";
export interface Belief {
  id: Id;
  kind: "resource" | "danger" | "ally" | "shelter" | "disaster";
  position: Vec;
  tick: number;
  source: Id;
  confidence: number;
  definition?: string;
  contents?: Record<string, number>;
}
export interface Plan {
  goal: string;
  steps: { kind: string; target?: Id; position?: Vec; definition?: string }[];
  cursor: number;
  reason: string;
  retryAt: number;
  failures: number;
}
export interface Profile {
  personality: { caution: number; sociability: number; ambition: number };
  beliefs: Belief[];
  memories: { tick: number; kind: string; subject?: Id }[];
  plan: Plan;
  nextThink: number;
  personalGoal: string;
}
export interface Actor {
  id: Id;
  kind: ActorKind;
  name: string;
  sex: "female" | "male";
  position: Vec;
  hp: number;
  life: "Alive" | "Dead";
  inventory: Id;
  skills: Record<string, number>;
  knowledge: string[];
  food: number;
  water: number;
  fatigue: number;
  mood: number;
  temperature: number;
  lastNeeds: number;
  readyAt: number;
  intent: Vec;
  sneaking: boolean;
  faction?: Id;
  profile?: Profile;
  heard?: { position: Vec; tick: number; eventId: Id };
  traits: Record<string, number>;
  pressure: Record<string, number>;
  injuries: string[];
  mountedOn?: Id;
  invitedBy?: Id;
  revision: number;
}
export interface Item {
  id: Id;
  definition: string;
  quantity: number;
  container: Id;
  condition: number;
  revision: number;
  provenance: string;
}
export interface Container {
  id: Id;
  position: Vec;
  actor?: Id;
  capacity: number;
  state: "normal" | "submerged" | "buried" | "drifting";
  owner?: Id;
  revision: number;
}
export interface Cohort {
  id: Id;
  first: Id;
  slots: number[];
  removed: number[];
  heard: Record<string, { position: Vec; tick: number; eventId: Id }>;
  sourceDay: number;
  revision: number;
}
export interface TerrainDelta {
  elevation: number;
  water: number;
  blocked: boolean;
  damage: number;
  revision: number;
  permanent: boolean;
  source: Id;
  baseWater?: number;
  baseBlocked?: boolean;
  temporary?: Record<string, { water: number; blocked: boolean }>;
}
export interface Building {
  id: Id;
  definition: string;
  position: Vec;
  owner: Id;
  progress: number;
  hp: number;
  revision: number;
  powered: boolean;
  storedEnergy: number;
  inventory: Id;
  occupied: boolean;
  open?: boolean;
}
export interface Job {
  id: Id;
  kind: "craft" | "build" | "research" | "modify" | "train" | "read";
  definition: string;
  actor: Id;
  target?: Id;
  workstation?: Id;
  inputs: Id;
  done: number;
  required: number;
  state: "Working" | "Paused" | "Complete" | "Cancelled";
  reason?: string;
  consumed: boolean;
  revision: number;
}
export interface Task {
  id: Id;
  issuer: Id;
  assignee?: Id;
  kind: "collect" | "build" | "research" | "rescue";
  target: string;
  amount: number;
  delivered: number;
  destination: Id;
  reward: { definition: string; quantity: number };
  state:
    | "Published"
    | "Accepted"
    | "Executing"
    | "Settled"
    | "Cancelled"
    | "Blocked";
  reason?: string;
  revision: number;
}
export interface Reservation {
  id: Id;
  holder: Id;
  resource: Id;
  amount: number;
  job: Id;
  expires: number;
}
export interface Companion {
  id: Id;
  owner: Id;
  controller?: Id;
  type: "pet" | "controlled";
  grade: "small" | "medium" | "large" | "ordinary" | "elite" | "special";
  cost: number;
  training: number;
  loyalty: number;
  stability: number;
  state:
    | "captured"
    | "isolated"
    | "rest"
    | "follow"
    | "guard"
    | "retreat"
    | "emergency"
    | "free"
    | "dead";
  orderPosition?: Vec;
  saddle: boolean;
  retention: number;
  retainedTraits: Record<string, number>;
  maintenanceTick: number;
  transferOffer?: Id;
  revision: number;
}
export interface Vehicle {
  id: Id;
  definition: "buggy" | "boat";
  owner: Id;
  position: Vec;
  hp: number;
  capacity: number;
  fuel: number;
  readyAt?: number;
  inventory: Id;
  modules: string[];
  seats: Record<string, Id>;
  revision: number;
}
export interface Death {
  id: Id;
  tick: number;
  cause: string;
  loot: Id;
  originalItems: Id[];
  harvested?: boolean;
}
export interface Binding {
  id: Id;
  actor: Id;
  player: string;
  epoch: number;
  sequence: number;
  connected: boolean;
  dead: boolean;
  pauseVote: boolean;
}
export interface Disaster {
  id: Id;
  kind: "rain" | "earthquake" | "tornado" | "tsunami";
  position: Vec;
  radius: number;
  stage: "forecast" | "impact" | "recovery" | "closed";
  due: number;
  applied: string[];
  permanent: boolean;
}
export interface Population {
  initial: number;
  daily: number;
  deaths: number;
  alive: number;
  placed: number;
  pending: number;
}
export interface Header {
  worldId: string;
  seed: string;
  schema: 1;
  simVersion: string;
  contentHash: string;
  biome: "inland" | "coast" | "dunes";
  size: number;
  tick: number;
  completedDays: number;
  ticksPerDay: number;
  phase: Phase;
  seq: number;
  nextId: string;
  rng: Record<string, number>;
  placementCursor: number;
  npcCursor: number;
  terrainRevision: number;
  climate: "normal" | "hot" | "cold" | "rain";
  climateUntil: number;
  dailyKey: number;
  npc: Population;
  infected: Population;
  worldOwner: string;
  result?: string;
}
export interface Resource {
  id: Id;
  definition: string;
  position: Vec;
  remaining: number;
  revision: number;
  traits: Record<string, number>;
  pressure: number;
}
export interface Tables {
  resources: Resource;
  actors: Actor;
  items: Item;
  containers: Container;
  cohorts: Cohort;
  terrain: TerrainDelta;
  buildings: Building;
  jobs: Job;
  tasks: Task;
  reservations: Reservation;
  companions: Companion;
  vehicles: Vehicle;
  deaths: Death;
  bindings: Binding;
  disasters: Disaster;
}
export type TableState = { [K in keyof Tables]: Record<Id, Tables[K]> };
export interface Event {
  id: Id;
  tick: number;
  kind: string;
  actor?: Id;
  text: string;
  position?: Vec;
}
export type World = TableState & {
  header: Header;
  events: Event[];
  receipts: Record<string, Receipt>;
};
export interface Command {
  id: string;
  actor: Id;
  sequence: number;
  epoch: number;
  kind: string;
  data: Record<string, unknown>;
  expected?: Record<Id, number>;
}
export interface Receipt {
  ok: boolean;
  code: string;
  commandId: string;
  seq: number;
  fingerprint: string;
}
export type TablePatch = { [K in keyof Tables]?: Record<Id, Tables[K] | null> };
export interface Patch {
  header: Header;
  tables: TablePatch;
  events: Event[];
  receipts: Record<string, Receipt | null>;
}
export interface Commit {
  worldId: string;
  prev: number;
  next: number;
  batchId: string;
  epoch: number;
  patch: Patch;
  checksum: string;
}
export interface Candidate {
  world: World;
  patch: Patch;
  receipt?: Receipt;
}
export class RuleError extends Error {
  constructor(public readonly code: string) {
    super(code);
  }
}
export function requireRule(
  condition: unknown,
  code: string,
): asserts condition {
  if (!condition) throw new RuleError(code);
}
export const TILE = 256;
export const distance = (a: Vec, b: Vec) =>
  Math.hypot(a.x - b.x, a.y - b.y) / TILE;
export const tileKey = (p: Vec) =>
  `${Math.floor(p.x / TILE)},${Math.floor(p.y / TILE)}`;
