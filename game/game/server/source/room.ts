import type {
  StateSyncGame,
  RuntimePlayer,
  MatchPreparationReporter,
} from "@vibegame/state-sync-runtime/server";
import { Authority } from "../../../assets/application/authority.ts";
import type { PersistencePort } from "../../../assets/application/persistence.ts";
import { MemoryStore } from "../../../assets/application/persistence.ts";
import { ProjectionStream } from "../../../assets/application/replication.ts";
import { project } from "../../../assets/application/projection.ts";
import { createWorld } from "../../../assets/simulation/population.ts";
import type { Command } from "../../../assets/simulation/model.ts";
import { randomUUID } from "node:crypto";

/** This adapter runs only in the platform's injected Node room host. */
export function createRoomGame(
  players: RuntimePlayer[],
  match?: MatchPreparationReporter,
  persistence?: PersistencePort,
): StateSyncGame {
  let authority: Authority | undefined;
  const connected = new Set(players.map((p) => p.id));
  const requests = new Map<string, { window: number; count: number }>();
  const receipts = new Map<string, unknown>();
  const store = persistence ?? new MemoryStore();
  const streams = new Map<string, ProjectionStream>();
  const stream = (id: string) => {
    let s = streams.get(id);
    if (!s) {
      s = new ProjectionStream();
      streams.set(id, s);
    }
    return s;
  };
  return {
    async start() {
      if (!players.length || players.length > 4)
        throw new Error("InvalidRoomPopulation");
      match?.reportLoading({
        phase: "world",
        text: "生成共同世界并绑定永久角色席位",
      });
      const seed = randomUUID();
      authority = await Authority.open(
        createWorld(seed, { owner: players[0].id }),
        store,
      );
      for (const p of players.slice(1)) await authority.bind(p.id, p.name);
    },
    async stop() {
      await authority?.close();
    },
    async tick() {
      if (authority && connected.size) await authority.step();
      return authority?.state.header.phase === "Ended";
    },
    async applyAction(playerId, input) {
      if (!authority || !connected.has(playerId)) return;
      if (input && typeof input === "object") {
        const wire = input as { kind?: string; worldId?: string; seq?: number };
        if (wire.kind === "__view_ack") {
          if (
            typeof wire.worldId === "string" &&
            Number.isSafeInteger(wire.seq)
          )
            stream(playerId).acknowledge(wire.worldId, wire.seq!);
          return;
        }
        if (wire.kind === "__resync_view") {
          stream(playerId).reset();
          return;
        }
      }
      const now = Date.now(),
        old = requests.get(playerId),
        rate = old && now - old.window < 1000 ? old : { window: now, count: 0 };
      requests.set(playerId, rate);
      if (++rate.count > 30) {
        receipts.set(playerId, { ok: false, code: "RateLimited" });
        return;
      }
      if (
        !input ||
        typeof input !== "object" ||
        JSON.stringify(input).length > 12288
      )
        return;
      try {
        receipts.set(
          playerId,
          await authority.dispatch(input as Command, playerId),
        );
      } catch (e) {
        receipts.set(playerId, {
          ok: false,
          code: e instanceof Error ? e.message : "ActionRejected",
        });
      }
    },
    async removePlayer(id) {
      connected.delete(id);
      streams.delete(id);
      await authority?.disconnect(id);
    },
    async addPlayer(player) {
      if (!authority) throw new Error("WorldNotReady");
      await authority.bind(player.id, player.name);
      connected.add(player.id);
    },
    getPlayerCount() {
      return connected.size;
    },
    getState(id) {
      if (!id || !authority || !connected.has(id)) return null;
      return {
        ...stream(id).packet(
          project(authority.state, id, store.durability),
          true,
        ),
        receipt: receipts.get(id),
      };
    },
    getDelta(id) {
      if (!authority || !connected.has(id)) return null;
      return {
        ...stream(id).packet(project(authority.state, id, store.durability)),
        receipt: receipts.get(id),
      };
    },
    getResult() {
      return {
        result: authority?.state.header.result,
        durability: store.durability,
      };
    },
  };
}
