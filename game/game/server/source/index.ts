import { createPlatformStateSyncRuntime } from "@vibegame/state-sync-runtime/server";
import { createRoomGame } from "./room.ts";
const platform = (globalThis as { PlatformServer?: unknown }).PlatformServer;
if (!platform)
  throw new Error("PlatformServer was not injected by the platform host");
createPlatformStateSyncRuntime({
  platform,
  roomPolicy: { maxPlayers: 4, minPlayersToStart: 2, tickIntervalMs: 50 },
  createGame: createRoomGame,
});
