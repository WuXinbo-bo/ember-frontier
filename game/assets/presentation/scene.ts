import type {} from "@forgeax/engine/app";
import type {} from "@forgeax/engine/assets-runtime";
import type { Plugin } from "@forgeax/engine/plugin";
import type { EntityHandle } from "@forgeax/engine/ecs";
import { Time, Update } from "@forgeax/engine/ecs";
import {
  Camera,
  orthographic,
  MeshFilter,
  MeshRenderer,
  DirectionalLight,
  Skylight,
  setActiveCamera,
} from "@forgeax/engine/render";
import { Transform, Name } from "@forgeax/engine/scene";
import { quat } from "@forgeax/engine/math";
import { IndexedDbStore } from "../adapters/indexeddb.ts";
import { exportSave } from "../application/save-file.ts";
import { LocalSession } from "../application/local-session.ts";
import type { View } from "../application/projection.ts";
import { TILE } from "../simulation/model.ts";
import { COLORS } from "./palette.ts";
import { ASSETS } from "./refs.ts";
export const CHANNEL = "ember/game";
export const sceneOwner: Plugin.Object = {
  name: "ember/world",
  inject: ["world", "assets", "gameHost"],
  async apply(ctx) {
    const world = ctx.world,
      assets = ctx.assets!,
      host = ctx.gameHost!,
      port = host.port;
    host.setPointerLockAllowed?.(false);
    const local = new LocalSession();
    let view: View | undefined,
      mode = "menu",
      suspended = false,
      busy = false,
      disposed = false,
      accumulator = 0,
      stamp = "",
      failure = "";
    const owned: EntityHandle[] = [],
      objects = new Map<string, EntityHandle>(),
      handles: number[] = [];
    const mesh = (await assets.load(ASSETS.box, "mesh")).unwrap();
    handles.push(mesh);
    const sample = (
      await assets.load(ASSETS.materials.grass, "material")
    ).unwrap();
    handles.push(sample);
    const materials = new Map<string, typeof sample>();
    for (const key of Object.keys(COLORS)) {
      const h = (await assets.load(ASSETS.materials[key], "material")).unwrap();
      materials.set(key, h);
      handles.push(h);
    }
    const rotation = Array.from(
      quat.fromLookAt(quat.create(), [0, 24, 18], [0, 0, 0], [0, 1, 0]),
    );
    const camera = world
      .spawn(
        { component: Name, data: { value: "Survival orthographic camera" } },
        { component: Transform, data: { pos: [0, 24, 18], quat: rotation } },
        {
          component: Camera,
          data: {
            ...orthographic({ left: -20, right: 20, top: 12, bottom: -12 }),
            near: 0.1,
            far: 1000,
          },
        },
      )
      .unwrap();
    owned.push(camera);
    setActiveCamera(world, camera);
    owned.push(
      world
        .spawn({
          component: DirectionalLight,
          data: {
            direction: [-0.5, -1, -0.4],
            intensity: 2.5,
            color: [1, 0.9, 0.72],
          },
        })
        .unwrap(),
    );
    owned.push(
      world
        .spawn({
          component: Skylight,
          data: { intensity: 0.8, color: [0.73, 0.8, 0.7] },
        })
        .unwrap(),
    );
    const box = (id: string, p: number[], scale: number[], color: string) => {
      let e = objects.get(id);
      if (e === undefined) {
        e = world
          .spawn(
            { component: Name, data: { value: id } },
            { component: Transform, data: { pos: p, scale } },
            { component: MeshFilter, data: { assetHandle: mesh } },
            {
              component: MeshRenderer,
              data: { materials: [materials.get(color)!] },
            },
          )
          .unwrap();
        objects.set(id, e);
      } else {
        world.set(e, Transform, { pos: p, scale }).unwrap();
        world
          .set(e, MeshRenderer, { materials: [materials.get(color)!] })
          .unwrap();
      }
      return e;
    };
    // Static native menu backdrop; no authority or room is opened before mode selection.
    for (let y = -19; y <= 19; y++)
      for (let x = -23; x <= 23; x++)
        box(
          `menu/${x}/${y}`,
          [x, -0.15, y],
          [1, 0.3, 1],
          y >= -2 && y <= 1
            ? "road"
            : (x * x + y * y) % 5 === 0
              ? "grass2"
              : "grass",
        );
    for (let i = 0; i < 14; i++)
      box(
        `menu/ruin/${i}`,
        [i * 3 - 19, 0.5, i % 2 ? 7 : -8],
        [1.6, 1 + (i % 3), 1.2],
        i % 2 ? "wood" : "stone",
      );
    const send = (kind: string, data: Record<string, unknown> = {}) =>
      port?.postMessage({ channel: CHANNEL, kind, ...data });
    const draw = (v: View) => {
      box(
        "background",
        [v.self.position.x / TILE, -0.4, v.self.position.y / TILE],
        [100, 0.2, 100],
        "dark",
      );
      const terrainStamp = `${Math.floor(v.self.position.x / TILE)}/${Math.floor(v.self.position.y / TILE)}/${v.terrainRevision}`,
        keep = new Set<string>(["background"]);
      for (const tile of v.tiles) {
        const id = `tile/${tile.x}/${tile.y}`;
        keep.add(id);
        if (terrainStamp !== stamp)
          box(
            id,
            [tile.x + 0.5, -0.12, tile.y + 0.5],
            [1, 0.24, 1],
            tile.material === "grass" && (tile.x * 7 + tile.y * 3) % 5 === 0
              ? "grass2"
              : tile.material,
          );
        if (tile.blocked) {
          const key = `${id}/rubble`;
          keep.add(key);
          box(key, [tile.x + 0.5, 0.4, tile.y + 0.5], [0.8, 0.8, 0.8], "stone");
        }
      }
      stamp = terrainStamp;
      for (const r of v.resources) {
        const id = `resource/${r.id}`;
        keep.add(id);
        const height = r.definition === "wood" ? 1.2 : 0.4;
        box(
          id,
          [r.position.x / TILE, height / 2, r.position.y / TILE],
          [0.7, height, 0.7],
          r.definition === "wood" || r.definition === "herb"
            ? "grass2"
            : r.definition === "stone"
              ? "stone"
              : "crate",
        );
        if (r.definition === "wood") {
          const crown = `${id}/crown`;
          keep.add(crown);
          box(
            crown,
            [r.position.x / TILE, 1.7, r.position.y / TILE],
            [1.2, 1, 1.2],
            "dark",
          );
        }
      }
      for (const a of v.actors) {
        const id = `actor/${a.id}`,
          x = a.position.x / TILE,
          z = a.position.y / TILE,
          dead = a.life === "Dead";
        keep.add(id);
        box(
          id,
          [x, dead ? 0.1 : 0.6, z],
          [dead ? 0.9 : 0.45, dead ? 0.2 : 0.9, 0.4],
          dead ? "dead" : a.kind,
        );
        if (!dead) {
          const head = `${id}/head`;
          keep.add(head);
          box(
            head,
            [x, 1.2, z],
            [0.35, 0.35, 0.35],
            a.kind === "infected" ? "grass2" : "cloth",
          );
        }
      }
      for (const c of v.containers)
        if (!c.actor && !v.buildings.some((b) => b.inventory === c.id)) {
          const id = `loot/${c.id}`;
          keep.add(id);
          box(
            id,
            [c.position.x / TILE, 0.25, c.position.y / TILE],
            [0.65, 0.5, 0.65],
            c.state === "normal" ? "crate" : "water",
          );
        }
      for (const v0 of v.vehicles) {
        const id = `vehicle/${v0.id}`;
        keep.add(id);
        box(
          id,
          [v0.position.x / TILE, 0.5, v0.position.y / TILE],
          [1.5, 0.6, 2.5],
          v0.hp > 0 ? "steel" : "dead",
        );
        const cab = `${id}/cab`;
        keep.add(cab);
        box(
          cab,
          [v0.position.x / TILE, 1.1, v0.position.y / TILE - 0.4],
          [1.1, 0.6, 1],
          "wood",
        );
      }
      for (const b of v.buildings) {
        const id = `building/${b.id}`,
          x = b.position.x / TILE,
          z = b.position.y / TILE;
        keep.add(id);
        box(
          id,
          [x, 0.35, z],
          [0.9, b.progress < 100 ? 0.2 : 0.7, 0.9],
          b.hp <= 0 ? "dead" : b.definition === "campfire" ? "fire" : "wood",
        );
        if (b.definition === "shelter" && b.progress === 100) {
          const roof = `${id}/roof`;
          keep.add(roof);
          box(roof, [x, 1.3, z], [1.4, 0.25, 1.4], "roof");
        }
      }
      for (const [id, e] of objects)
        if (!keep.has(id)) {
          world.despawn(e).unwrap();
          objects.delete(id);
        }
      world
        .set(camera, Transform, {
          pos: [v.self.position.x / TILE, 24, v.self.position.y / TILE + 18],
        })
        .unwrap();
    };
    const publish = () => {
      const next = local.view();
      if (next) {
        view = next;
        draw(view);
        send("view", { view, error: failure || local.authority?.fault || "" });
      }
    };
    const receive = async (event: MessageEvent) => {
      const m = event.data;
      if (disposed || m?.channel !== CHANNEL) return;
      try {
        if (m.kind === "inspect") {
          send("ready");
          if (view) send("view", { view });
        }
        if (m.kind === "list-saves") {
          const reader = await new IndexedDbStore().open();
          try {
            send("saves", { saves: await reader.list() });
          } finally {
            await reader.release();
          }
        }
        if (m.kind === "import" && mode === "menu" && !busy) {
          busy = true;
          await local.import(String(m.text));
          mode = "local";
          failure = "";
          suspended = false;
          publish();
          send("opened");
        }
        if (m.kind === "open-local" && !busy && mode === "menu") {
          busy = true;
          send("loading");
          await local.open(
            String(m.seed || "ember-first-light").slice(0, 80),
            ["coast", "dunes"].includes(m.biome) ? m.biome : "inland",
            m.worldId || undefined,
          );
          mode = "local";
          suspended = false;
          failure = "";
          publish();
          send("opened");
        }
        if (m.kind === "action" && mode === "local") {
          const receipt = await local.action(
            m.action,
            m.data || {},
            m.expected,
          );
          send("receipt", { receipt });
          publish();
        }
        if (m.kind === "online-view" && mode !== "local") {
          mode = "online";
          view = m.view;
          if (view) draw(view);
        }
        if (m.kind === "suspend") {
          suspended = !!m.paused;
          if (mode === "local" && local.authority)
            await local.action("Move", { x: 0, y: 0 });
        }
        if (m.kind === "retry") {
          await local.authority?.retry();
          failure = "";
          publish();
        }
        if (m.kind === "close") {
          await local.close();
          view = undefined;
          mode = "menu";
          send("closed");
        }
        if (m.kind === "export" && mode === "local")
          send("save-export", {
            text: exportSave(local.authority!.state),
            worldId: local.authority!.state.header.worldId,
          });
      } catch (e) {
        failure = e instanceof Error ? e.message : String(e);
        send("error", { error: failure });
      } finally {
        if (m.kind === "open-local" || m.kind === "import") busy = false;
      }
    };
    await ctx.effect(function* () {
      port?.addEventListener("message", receive);
      port?.start();
      yield () => port?.removeEventListener("message", receive);
      const read = host.gameProjection?.registerRead({
        id: "ember.game",
        title: "Committed game state",
        read: () =>
          JSON.parse(
            JSON.stringify({
              mode,
              busy,
              suspended,
              error: failure,
              ...(view
                ? {
                    worldId: view.worldId,
                    seq: view.seq,
                    tick: view.tick,
                    phase: view.phase,
                    self: view.self,
                    population: view.population,
                    buildings: view.buildings,
                    jobs: view.jobs,
                    containers: view.containers,
                    items: view.items,
                  }
                : {}),
            }),
          ),
      });
      if (read) yield read;
      world
        .addSystem(Update, {
          name: "ember/authority",
          queries: [],
          fn: (w) => {
            if (
              mode !== "local" ||
              suspended ||
              busy ||
              disposed ||
              local.authority?.fault
            )
              return;
            accumulator = Math.min(
              0.25,
              accumulator + w.getResource(Time).delta,
            );
            if (accumulator < 0.05) return;
            accumulator -= 0.05;
            busy = true;
            void local
              .authority!.step()
              .then(() => {
                if (!disposed) publish();
              })
              .catch((e) => {
                failure = String(e);
                send("error", { error: failure });
              })
              .finally(() => {
                busy = false;
              });
          },
        })
        .unwrap();
      yield () => world.removeSystem(Update, "ember/authority").unwrap();
      yield async () => {
        disposed = true;
        await local.close();
        for (const e of objects.values()) world.despawn(e).unwrap();
        for (const e of owned) world.despawn(e).unwrap();
        for (const h of handles) assets.release(h).unwrap();
      };
    });
    send("ready");
  },
};
