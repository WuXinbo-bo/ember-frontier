import { type World, type Vec, TILE, tileKey, distance } from "./model.ts";
import { hash } from "./determinism.ts";
import { BUILDINGS } from "../content/catalog.ts";

export interface Tile {
  x: number;
  y: number;
  elevation: number;
  water: number;
  material: "grass" | "sand" | "stone" | "road" | "water";
  blocked: boolean;
  revision: number;
}
function interpolated(seed: string, x: number, y: number): number {
  const cx = x >> 6,
    cy = y >> 6,
    fx = x & 63,
    fy = y & 63;
  const n = (a: number, b: number) => hash(`${seed}/land/${a}/${b}`) % 180;
  return Math.floor(
    (n(cx, cy) * (64 - fx) * (64 - fy) +
      n(cx + 1, cy) * fx * (64 - fy) +
      n(cx, cy + 1) * (64 - fx) * fy +
      n(cx + 1, cy + 1) * fx * fy) /
      4096,
  );
}
export function tileAt(world: World, x: number, y: number): Tile {
  const h = world.header;
  let elevation = 35 + interpolated(h.seed, x, y);
  if (h.biome === "coast")
    elevation += Math.min(0, (x - Math.floor(h.size * 0.28)) * 2);
  if (
    h.biome === "inland" &&
    Math.abs(
      y -
        Math.floor(h.size * 0.36) -
        Math.floor(interpolated(h.seed + "river", x, 0) / 3),
    ) < 3
  )
    elevation = -45;
  const edit = world.terrain[`${x},${y}`];
  elevation += edit?.elevation ?? 0;
  const water = Math.max(0, -elevation, edit?.water ?? 0);
  const road = y % 64 === 32 || x % 64 === 32;
  return {
    x,
    y,
    elevation,
    water,
    material:
      water > 0
        ? "water"
        : road
          ? "road"
          : h.biome === "dunes" || elevation < 40
            ? "sand"
            : elevation > 170
              ? "stone"
              : "grass",
    blocked: !!edit?.blocked || x < 0 || y < 0 || x >= h.size || y >= h.size,
    revision: edit?.revision ?? 0,
  };
}
export function buildingAt(world: World, p: Vec) {
  const key = tileKey(p);
  return Object.values(world.buildings).find(
    (b) => b.hp > 0 && tileKey(b.position) === key,
  );
}
export function passable(
  world: World,
  p: Vec,
  mode: "walk" | "raft" = "walk",
): boolean {
  const t = tileAt(world, Math.floor(p.x / TILE), Math.floor(p.y / TILE));
  const b = buildingAt(world, p);
  if (b && b.progress >= 100 && b.definition === "bridge" && b.hp > 0)
    return true;
  return (
    !t.blocked &&
    (mode === "raft" ? t.water < 250 : t.water <= 40) &&
    !(b && b.progress >= 100 && BUILDINGS[b.definition].solid && !b.open)
  );
}
export const withinOccupation = (world: World, p: Vec) =>
  Object.values(world.buildings).some(
    (b) =>
      b.occupied &&
      b.hp > 0 &&
      distance(b.position, p) <= (BUILDINGS[b.definition].occupation ?? 0),
  );
export function findPath(
  world: World,
  from: Vec,
  to: Vec,
  mode: "walk" | "raft" = "walk",
  limit = 2048,
): Vec[] | null {
  const sx = Math.floor(from.x / TILE),
    sy = Math.floor(from.y / TILE),
    tx = Math.floor(to.x / TILE),
    ty = Math.floor(to.y / TILE);
  const key = (x: number, y: number) => `${x},${y}`;
  const start = key(sx, sy),
    goal = key(tx, ty);
  if (start === goal) return [];
  const open = [
    { x: sx, y: sy, g: 0, f: Math.abs(tx - sx) + Math.abs(ty - sy) },
  ];
  const scores = new Map([[start, 0]]),
    prev = new Map<string, string>();
  let count = 0;
  while (open.length && count++ < limit) {
    let best = 0;
    for (let i = 1; i < open.length; i++)
      if (open[i].f < open[best].f) best = i;
    const n = open.splice(best, 1)[0],
      nk = key(n.x, n.y);
    if (nk === goal) {
      const path: Vec[] = [];
      let k = goal;
      while (k !== start) {
        const [x, y] = k.split(",").map(Number);
        path.push({ x: x * TILE + 128, y: y * TILE + 128 });
        k = prev.get(k)!;
      }
      return path.reverse();
    }
    for (const [dx, dy] of [
      [1, 0],
      [0, 1],
      [-1, 0],
      [0, -1],
    ]) {
      const x = n.x + dx,
        y = n.y + dy,
        k = key(x, y),
        g = n.g + 1;
      if (
        g >= (scores.get(k) ?? Infinity) ||
        !passable(world, { x: x * TILE + 128, y: y * TILE + 128 }, mode)
      )
        continue;
      scores.set(k, g);
      prev.set(k, nk);
      open.push({ x, y, g, f: g + Math.abs(tx - x) + Math.abs(ty - y) });
    }
  }
  return null;
}
export function clearLine(world: World, a: Vec, b: Vec): boolean {
  const steps = Math.ceil(distance(a, b) * 2);
  for (let i = 1; i < steps; i++) {
    const p = {
      x: Math.round(a.x + ((b.x - a.x) * i) / steps),
      y: Math.round(a.y + ((b.y - a.y) * i) / steps),
    };
    if (
      tileAt(world, Math.floor(p.x / TILE), Math.floor(p.y / TILE)).blocked ||
      (() => {
        const b = buildingAt(world, p);
        return (
          b &&
          b.progress === 100 &&
          ["wall", "door"].includes(b.definition) &&
          !b.open
        );
      })()
    )
      return false;
  }
  return true;
}
