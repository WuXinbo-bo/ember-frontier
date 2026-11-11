import {
  type Actor,
  type Belief,
  type Plan,
  type Vec,
  type World,
  TILE,
  distance,
} from "./model.ts";
import { containerPosition, inventoryItems } from "./inventory.ts";
import { nearbyResources } from "./environment.ts";
import { nearbyMembers } from "./spatial.ts";
import { clearLine } from "./terrain.ts";

export interface SelfState {
  position: Vec;
  food: number;
  water: number;
  fatigue: number;
  hp: number;
  caution: number;
  sociability: number;
  ambition: number;
  canEat: boolean;
  canDrink: boolean;
  tick: number;
}
/** Intentionally receives beliefs and self only; cannot access hidden World facts. */
export function choosePlan(
  beliefs: ReadonlyArray<Belief>,
  self: Readonly<SelfState>,
): Plan {
  const fresh = beliefs.filter(
    (b) => self.tick - b.tick < 2400 && b.confidence > 20,
  );
  const danger = fresh
    .filter((b) => b.kind === "danger")
    .sort(
      (a, b) =>
        distance(a.position, self.position) -
        distance(b.position, self.position),
    )[0];
  const base = { cursor: 0, retryAt: self.tick, failures: 0 };
  if (
    danger &&
    distance(danger.position, self.position) < 3 + self.caution / 20
  ) {
    const dx = self.position.x - danger.position.x,
      dy = self.position.y - danger.position.y,
      n = Math.max(1, Math.hypot(dx, dy));
    return {
      ...base,
      goal: "retreat",
      reason: `危险记忆与谨慎 ${self.caution}：撤离`,
      steps: [
        {
          kind: "move",
          position: {
            x: Math.round(self.position.x + (dx / n) * 5 * TILE),
            y: Math.round(self.position.y + (dy / n) * 5 * TILE),
          },
        },
      ],
    };
  }
  if (self.water < 65 && self.canDrink)
    return {
      ...base,
      goal: "drink",
      reason: "饮水储备下降",
      steps: [{ kind: "consume-water" }],
    };
  if (self.food < 65 && self.canEat)
    return {
      ...base,
      goal: "eat",
      reason: "补充饱食",
      steps: [{ kind: "consume-food" }],
    };
  if (self.fatigue > 65)
    return {
      ...base,
      goal: "rest",
      reason: "疲劳妨碍工作与警戒",
      steps: [{ kind: "rest" }],
    };
  const resource = fresh
    .filter((b) => b.kind === "resource")
    .sort(
      (a, b) =>
        distance(a.position, self.position) -
        distance(b.position, self.position),
    )[0];
  if (resource)
    return {
      ...base,
      goal: "supply",
      reason: "寻找已观察到的实物补给",
      steps: [
        { kind: "move", position: resource.position },
        { kind: "loot", target: resource.id },
      ],
    };
  const ally = fresh.find((b) => b.kind === "ally");
  if (ally && self.sociability > 65)
    return {
      ...base,
      goal: "cooperate",
      reason: "偏好与可信同伴合作",
      steps: [{ kind: "move", position: ally.position }],
    };
  return {
    ...base,
    goal: "scout",
    reason: "没有足够情报，探索邻近区域",
    steps: [{ kind: "scout" }],
  };
}
/** Perception is the only boundary allowed to project local truth into beliefs. */
export function observe(world: World, actor: Actor): Belief[] {
  const beliefs: Belief[] = (actor.profile?.beliefs ?? []).filter(
    (b) => world.header.tick - b.tick < 2400,
  );
  const add = (b: Belief) => {
    const i = beliefs.findIndex((x) => x.id === b.id);
    if (i < 0) beliefs.push(b);
    else beliefs[i] = b;
  };
  for (const c of Object.values(world.containers))
    if (
      !c.actor &&
      !c.owner &&
      distance(actor.position, containerPosition(world, c.id)) < 9 &&
      clearLine(world, actor.position, c.position) &&
      inventoryItems(world, c.id).length
    )
      add({
        id: c.id,
        kind: "resource",
        position: c.position,
        tick: world.header.tick,
        source: actor.id,
        confidence: 100,
        contents: Object.fromEntries(
          inventoryItems(world, c.id).map((i) => [i.definition, i.quantity]),
        ),
      });
  for (const r of nearbyResources(world, actor.position, 9))
    if (clearLine(world, actor.position, r.position))
      add({
        id: r.id,
        kind: "resource",
        position: r.position,
        tick: world.header.tick,
        source: actor.id,
        confidence: 100,
        contents: { [r.definition]: r.remaining },
      });
  for (const b of Object.values(world.buildings))
    if (
      b.owner === actor.id &&
      b.progress === 100 &&
      distance(b.position, actor.position) < 10
    )
      add({
        id: b.id,
        kind: "shelter",
        definition: b.definition,
        position: b.position,
        tick: world.header.tick,
        source: actor.id,
        confidence: 100,
      });
  for (const z of nearbyMembers(world, actor.position, 8))
    if (clearLine(world, actor.position, z.position))
      add({
        id: z.id,
        kind: "danger",
        position: z.position,
        tick: world.header.tick,
        source: actor.id,
        confidence: 100,
      });
  for (const a of Object.values(world.actors))
    if (
      a.id !== actor.id &&
      a.life === "Alive" &&
      distance(actor.position, a.position) < 8 &&
      clearLine(world, actor.position, a.position)
    )
      add({
        id: a.id,
        kind: a.kind === "infected" ? "danger" : "ally",
        position: a.position,
        tick: world.header.tick,
        source: actor.id,
        confidence: 100,
      });
  return beliefs.slice(-48);
}
