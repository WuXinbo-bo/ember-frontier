import { type Actor, type Vec, TILE, distance, requireRule } from "./model.ts";
import { Draft } from "./transaction.ts";
import { pay, newContainer, weight, countItem, take } from "./inventory.ts";
import { passable } from "./terrain.ts";
import { emitSound } from "./acoustics.ts";
export const MODULES: Record<
  string,
  { mass: number; power: number; slot: string }
> = {
  engine_module: { mass: 18000, power: 0, slot: "drive" },
  gun_module: { mass: 22000, power: 2, slot: "weapon" },
  armor_module: { mass: 30000, power: 0, slot: "armor" },
};
export function vehicleAction(
  d: Draft,
  a: Actor,
  kind: string,
  data: Record<string, unknown>,
): boolean {
  const id = String(data.vehicle ?? a.mountedOn ?? ""),
    vehicle = d.world.vehicles[id];
  if (kind === "AssembleVehicle") {
    const definition = data.definition === "boat" ? "boat" : "buggy";
    requireRule(a.knowledge.includes("tech.vehicles.1"), "KnowledgeMissing");
    requireRule(a.readyAt <= d.header.tick, "Cooldown");
    const position = { x: a.position.x + TILE, y: a.position.y };
    requireRule(
      passable(d.world, position, definition === "boat" ? "raft" : "walk"),
      "PlacementBlocked",
    );
    pay(d, a.inventory, {
      [definition === "boat" ? "boat_chassis" : "vehicle_chassis"]: 1,
    });
    const id = d.id(),
      inventory = newContainer(d, position, { owner: a.id, capacity: 100000 });
    d.put("vehicles", id, {
      id,
      definition,
      owner: a.id,
      position,
      hp: 300,
      capacity: 100000,
      fuel: 0,
      inventory,
      modules: [],
      seats: {},
      revision: 0,
    });
    a.readyAt = d.header.tick + 100;
    d.event("VehicleCreated", "已从实际底盘装配载具，尚需发动机和燃料。", a.id);
    return true;
  }
  if (
    ![
      "InstallModule",
      "EnterVehicle",
      "ExitVehicle",
      "Refuel",
      "RecoverVehicle",
      "PracticeDriving",
    ].includes(kind)
  )
    return false;
  requireRule(vehicle && vehicle.hp > 0, "VehicleUnavailable");
  requireRule(distance(a.position, vehicle.position) <= 3, "OutOfRange");
  const v = d.edit("vehicles", id);
  if (kind === "PracticeDriving") {
    requireRule(v.owner === a.id && a.readyAt <= d.header.tick, "Cooldown");
    requireRule(v.fuel >= 1, "FuelEmpty");
    v.fuel--;
    a.skills.driving = Math.min(10000, a.skills.driving + 10);
    a.readyAt = d.header.tick + 200;
    d.event(
      "DrivingPractice",
      "完成耗油操纵练习，动作恢复期间不能移动。",
      a.id,
    );
  }
  if (kind === "InstallModule") {
    requireRule(v.owner === a.id, "PermissionDenied");
    requireRule(Object.keys(v.seats).length === 0, "VehicleOccupied");
    const module = String(data.module),
      def = MODULES[module];
    requireRule(def, "DefinitionMissing");
    requireRule(
      !v.modules.some((m) => MODULES[m].slot === def.slot),
      "ModuleSlotOccupied",
    );
    const mass =
      v.modules.reduce((s, m) => s + MODULES[m].mass, 0) +
      def.mass +
      weight(d.world, v.inventory);
    requireRule(mass <= v.capacity, "VehicleOverweight");
    pay(d, a.inventory, { [module]: 1 });
    v.modules.push(module);
  }
  if (kind === "EnterVehicle") {
    requireRule(!a.mountedOn, "AlreadyMounted");
    const seat = data.seat === "gunner" ? "gunner" : "driver";
    requireRule(!v.seats[seat], "SeatOccupied");
    requireRule(
      v.owner === a.id ||
        (d.world.actors[v.owner]?.faction === a.faction && !!a.faction),
      "PermissionDenied",
    );
    requireRule(a.skills.driving >= 50, "DrivingQualification");
    v.seats[seat] = a.id;
    a.mountedOn = id;
    a.position = { ...v.position };
  }
  if (kind === "ExitVehicle") {
    const seat = Object.keys(v.seats).find((k) => v.seats[k] === a.id);
    requireRule(seat, "NotInVehicle");
    const choices: [
      [number, number],
      [number, number],
      [number, number],
      [number, number],
    ] = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];
    const position = choices
      .map(([x, y]) => ({
        x: v.position.x + x * TILE,
        y: v.position.y + y * TILE,
      }))
      .find((p) => passable(d.world, p));
    requireRule(position, "NoSafeExit");
    delete v.seats[seat];
    a.position = position;
    a.mountedOn = undefined;
    a.intent = { x: 0, y: 0 };
  }
  if (kind === "Refuel") {
    requireRule(
      v.owner === a.id || Object.values(v.seats).includes(a.id),
      "PermissionDenied",
    );
    requireRule(v.fuel <= 5400, "FuelTankFull");
    pay(d, a.inventory, { fuel: 1 });
    v.fuel += 600;
  }
  if (kind === "RecoverVehicle") {
    requireRule(
      v.owner === a.id && a.knowledge.includes("tech.vehicles.1"),
      "PermissionDenied",
    );
    pay(d, a.inventory, { scrap: 2, gear: 1 });
    v.hp = Math.min(300, v.hp + 60);
    a.readyAt = d.header.tick + 100;
  }
  v.revision++;
  return true;
}
export function stepVehicles(d: Draft) {
  for (const prior of Object.values(d.world.vehicles)) {
    if (prior.hp <= 0) continue;
    const driver = d.world.actors[prior.seats.driver];
    if (
      !driver ||
      driver.life !== "Alive" ||
      (!driver.intent.x && !driver.intent.y)
    )
      continue;
    if (
      driver.readyAt > d.header.tick ||
      !prior.modules.includes("engine_module") ||
      prior.fuel <= 0
    )
      continue;
    const v = d.edit("vehicles", prior.id),
      mass =
        v.modules.reduce((s, m) => s + MODULES[m].mass, 0) +
        weight(d.world, v.inventory);
    if (mass > v.capacity) continue;
    const speed = 48 / (1 + mass / v.capacity),
      length = Math.max(1, Math.hypot(driver.intent.x, driver.intent.y));
    const p: Vec = {
      x: Math.round(v.position.x + (driver.intent.x / length) * speed),
      y: Math.round(v.position.y + (driver.intent.y / length) * speed),
    };
    if (passable(d.world, p, v.definition === "boat" ? "raft" : "walk")) {
      v.position = p;
      d.edit("containers", v.inventory).position = { ...p };
      for (const occupant of Object.values(v.seats)) {
        const a = d.world.actors[occupant];
        if (a?.life === "Alive") d.edit("actors", occupant).position = { ...p };
        else
          for (const seat of Object.keys(v.seats))
            if (v.seats[seat] === occupant) delete v.seats[seat];
      }
      v.revision++;
    }
    if (d.header.tick % 20 === 0) {
      v.fuel--;
      emitSound(d, v.position, 24, driver.id);
    }
  }
}
