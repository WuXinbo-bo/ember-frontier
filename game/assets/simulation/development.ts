import type { Belief, Plan, Vec } from "./model.ts";
import { TILE, distance } from "./model.ts";
import { BUILDINGS, RESEARCH, ITEMS, RECIPES } from "../content/catalog.ts";
export interface DevelopmentSelf {
  position: Vec;
  tick: number;
  inventory: Record<string, number>;
  knowledge: string[];
  buildings: string[];
  working: boolean;
  route: "tech" | "bio" | "augmentation";
  food: number;
  water: number;
}
/** HTN expansion uses the NPC's own state and remembered observations only. */
export function developmentPlan(
  beliefs: readonly Belief[],
  self: DevelopmentSelf,
): Plan | undefined {
  const base = { cursor: 0, retryAt: self.tick, failures: 0 };
  if (self.working)
    return {
      ...base,
      goal: "work",
      reason: "继续已投入材料的工作",
      steps: [{ kind: "wait" }],
    };
  const plan = (goal: string, reason: string, steps: Plan["steps"]): Plan => ({
    ...base,
    goal,
    reason,
    steps,
  });
  const need = (definition: string, seen: string[] = []): Plan | undefined => {
    if (seen.includes(definition)) return;
    const candidates = beliefs
      .filter(
        (b) =>
          b.kind === "resource" &&
          (b.contents?.[definition] ?? 0) > 0 &&
          self.tick - b.tick < 2400,
      )
      .sort(
        (a, b) =>
          distance(a.position, self.position) -
          distance(b.position, self.position),
      );
    const b = candidates[0];
    if (!b) {
      const recipe = Object.entries(RECIPES).find(
        ([, r]) =>
          r.output[definition] &&
          (!r.knowledge || self.knowledge.includes(r.knowledge)) &&
          (!r.workstation || self.buildings.includes(r.workstation)),
      );
      if (!recipe) return;
      const [id, r] = recipe;
      for (const [item, n] of Object.entries(r.cost))
        if ((self.inventory[item] ?? 0) < n)
          return need(item, [...seen, definition]);
      const station = r.workstation
        ? beliefs.find((b) => b.definition === r.workstation)
        : undefined;
      return plan("craft", `制作所需的 ${ITEMS[definition].name}`, [
        ...(station ? [{ kind: "move", position: station.position }] : []),
        { kind: "craft", definition: id },
      ]);
    }
    return plan("supply", `为当前目标寻找 ${ITEMS[definition].name}`, [
      { kind: "move", position: b.position },
      {
        kind: b.id.startsWith("deposit/") ? "gather" : "loot",
        target: b.id,
        definition,
        position: b.position,
      },
    ]);
  };
  for (const def of ["food", "water"])
    if ((self.inventory[def] ?? 0) < 2) {
      const supply = need(def);
      if (supply) return supply;
    }
  const book = Object.keys(self.inventory).find(
    (id) =>
      ITEMS[id]?.knowledge &&
      !self.knowledge.includes(ITEMS[id].knowledge!) &&
      self.inventory[id] > 0,
  );
  if (book)
    return plan("learn", "阅读自己实际持有的知识", [
      { kind: "read", definition: book },
    ]);
  let building = !self.buildings.includes("shelter")
    ? "shelter"
    : !self.buildings.includes("campfire")
      ? "campfire"
      : !self.buildings.includes("workbench")
        ? "workbench"
        : undefined;
  if (
    !building &&
    self.route !== "tech" &&
    !self.buildings.includes("generator")
  )
    building = "generator";
  const station =
    self.route === "tech"
      ? "workbench"
      : self.route === "bio"
        ? "biolab"
        : "clinic";
  if (!building && !self.buildings.includes(station)) building = station;
  if (building) {
    const def = BUILDINGS[building];
    for (const [id, n] of Object.entries(def.cost))
      if ((self.inventory[id] ?? 0) < n) return need(id);
    const turn = Math.floor(self.tick / 100) % 4;
    return plan("build", `以现有物资建设 ${def.name}`, [
      {
        kind: "build",
        definition: building,
        position: {
          x: self.position.x + [2, -2, 0, 0][turn] * TILE,
          y: self.position.y + [0, 0, 2, -2][turn] * TILE,
        },
      },
    ]);
  }
  if (!self.knowledge.includes(self.route))
    return need(
      self.route === "tech"
        ? "book_tech"
        : self.route === "bio"
          ? "book_bio"
          : "book_aug",
    );
  const research = Object.entries(RESEARCH).find(
    ([id, d]) =>
      d.route === self.route &&
      !self.knowledge.includes(id) &&
      d.prerequisites.every((p) => self.knowledge.includes(p)),
  );
  if (research) {
    const [id, def] = research;
    for (const [item, n] of Object.entries(def.cost))
      if ((self.inventory[item] ?? 0) < n) return need(item);
    const known = beliefs.find(
      (b) => b.kind === "shelter" && b.definition === station,
    );
    if (known)
      return plan("research", `按自身路线研究 ${def.name}`, [
        { kind: "move", position: known.position },
        { kind: "research", definition: id },
      ]);
  }
}
