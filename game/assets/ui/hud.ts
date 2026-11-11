import type { GameHost } from "@forgeax/engine/app";
import { mountUi, type UiAsset } from "@forgeax/engine/ui";
import { game, lifecycle, rooms } from "zaohua-platform-sdk";
import type {
  OnlineRoomSession,
  RoomSnapshot,
} from "@vibegame/state-sync-runtime/client";
import { applyViewDelta, type ViewDelta } from "../application/replication.ts";
import type { View } from "../application/projection.ts";
import type { Command } from "../simulation/model.ts";
import { TILE, distance } from "../simulation/model.ts";
import {
  ITEMS,
  RECIPES,
  BUILDINGS,
  RESEARCH,
  SKILLS,
} from "../content/catalog.ts";
import { checksum } from "../simulation/determinism.ts";
const CHANNEL = "ember/game";
const reasons: Record<string, string> = {
  MissingMaterial: "材料不足",
  OutOfRange: "目标距离过远",
  Busy: "正在进行其他动作",
  KnowledgeMissing: "缺少前置知识",
  WorkstationMissing: "需要附近的自有工作台",
  Unsafe: "附近存在威胁，无法安全休息或暂停",
  Cooldown: "动作尚未完成",
  PlacementOccupied: "该地块有人或感染体",
  PlacementBlocked: "无法在这里放置建筑",
  NoPower: "工作台缺少电力",
  AlreadyRead: "已经掌握这本书的知识",
  ControlBudgetExceeded: "超过当前统一指挥预算",
  TrainingMissing: "需要先训练或研究控制技术",
  WorldOpenInAnotherTab: "此世界已在另一个标签页打开，请先关闭它",
  VersionsRequired: "库存版本缺失，请刷新操作",
  VersionConflict: "物资已发生变化，请重新选择",
  ActorDead: "角色已永久死亡",
  WorldNotRunning: "世界暂停或正在完成日结算",
  ItemMissing: "物品已不存在",
  TargetUnavailable: "目标已不可用",
  ConsentMissing: "对方尚未同意加入，先建立信任",
  OutputCapacity: "背包已满，工作等待腾出空间",
};
type Packet = {
  view?: View;
  delta?: ViewDelta;
  receipt?: { ok: boolean; code: string; commandId?: string };
};
export async function createHud(asset: UiAsset, host: GameHost) {
  if (!host.uiRoot) throw new Error("PresentationUiRootMissing");
  const result = mountUi(asset, {
    root: host.uiRoot,
    layer: 50,
    onAction: (a) => void action(a),
  });
  if (!result.ok) throw result.error;
  const mounted = result.value,
    root = mounted.host.shadowRoot!,
    doc = root.ownerDocument,
    win = doc.defaultView!,
    port = host.presentationPort ?? host.port;
  if (!port) throw new Error("PresentationMessagePortMissing");
  const $ = <T extends HTMLElement = HTMLElement>(s: string) => {
    const n = root.querySelector<T>(s);
    if (!n) throw new Error(`MissingHudElement:${s}`);
    return n;
  };
  const releases: (() => void)[] = [],
    keys = new Set<string>();
  let view: View | undefined,
    screen = "menu",
    tab = "",
    lastDetail = "",
    statusUntil = 0,
    paused = false,
    connected = true,
    sequence = 0,
    lastEpoch = 0,
    disposed = false,
    busy = false,
    mode = "local",
    lastReceipt = "",
    room: OnlineRoomSession<Command, Packet> | undefined,
    roomId = "",
    polling = false,
    roomRelease: (() => void) | undefined;
  const post = (kind: string, data: Record<string, unknown> = {}) =>
    port.postMessage({ channel: CHANNEL, kind, ...data });
  const toast = (message: string) => {
    $("#status").textContent = reasons[message] ?? message;
    $("#status").hidden = false;
    statusUntil = Date.now() + 4500;
  };
  const show = (next: string) => {
    screen = next;
    root
      .querySelectorAll<HTMLElement>("[data-screen]")
      .forEach((e) => (e.hidden = e.dataset.screen !== next));
  };
  const block = (title?: string, detail = "", retry = false) => {
    $("#blocking").hidden = !title;
    if (title) {
      $("#blocking-title").textContent = title;
      $("#blocking-detail").textContent = detail;
      $("#retry").hidden = !retry;
    }
  };
  const command = (
    kind: string,
    data: Record<string, unknown> = {},
    expected?: Command["expected"],
  ) => {
    if (!view || paused || !connected) return;
    if (mode === "local") post("action", { action: kind, data, expected });
    else if (room) {
      const c: Command = {
        id: `${room.getPlayerId()}/${view.binding.epoch}/${++sequence}`,
        actor: view.self.id,
        sequence,
        epoch: view.binding.epoch,
        kind,
        data,
        expected,
      };
      room.sendAction(c);
    }
  };
  const move = (x = 0, y = 0) =>
    command("Move", {
      x: Math.sign(x),
      y: Math.sign(y),
      sneaking: keys.has("ShiftLeft") || keys.has("ShiftRight"),
    });
  const stop = () => {
    keys.clear();
    move();
  };
  const amount = (id: string) =>
    view?.items
      .filter(
        (i) => i.container === view!.self.inventory && i.definition === id,
      )
      .reduce((n, i) => n + i.quantity, 0) ?? 0;
  const transfer = (itemId: string, destination: string, n: number) => {
    if (!view) return;
    const i = view.items.find((i) => i.id === itemId),
      dest = view.containers.find((c) => c.id === destination),
      source = view.containers.find((c) => c.id === i?.container);
    if (i && dest && source)
      command(
        "Transfer",
        { item: itemId, destination, amount: n },
        {
          [i.id]: i.revision,
          [dest.id]: dest.revision,
          [source.id]: source.revision,
        },
      );
  };
  const interact = () => {
    if (!view) return;
    const item = view.items.find(
      (i) =>
        i.quantity > 0 &&
        i.container !== view!.self.inventory &&
        view!.containers.some(
          (c) => c.id === i.container && !c.actor && c.state === "normal",
        ),
    );
    if (item)
      transfer(item.id, view!.self.inventory, Math.min(item.quantity, 5));
    else {
      const r = view.resources.find(
        (r) => distance(r.position, view!.self.position) <= 2.5,
      );
      if (r)
        command("Gather", {
          x: Math.floor(r.position.x / TILE),
          y: Math.floor(r.position.y / TILE),
        });
      else toast("走近物资箱或资源点，再按 E。");
    }
  };
  const attack = () => {
    if (!view) return;
    const weapon = view.items.find(
        (i) =>
          i.container === view!.self.inventory && ITEMS[i.definition].damage,
      ),
      range = weapon ? (ITEMS[weapon.definition].range ?? 1.5) : 1.5;
    const target = view.actors
      .filter(
        (a) =>
          a.kind === "infected" &&
          a.life === "Alive" &&
          !view!.companions.some((c) => c.id === a.id),
      )
      .sort(
        (a, b) =>
          distance(a.position, view!.self.position) -
          distance(b.position, view!.self.position),
      )[0];
    if (target && distance(target.position, view.self.position) <= range)
      command("Attack", { target: target.id, weapon: weapon?.id });
    else toast("攻击范围内没有感染体。");
  };
  function row(
    title: string,
    description: string,
    buttons: { label: string; click: () => void; disabled?: boolean }[] = [],
  ) {
    const e = doc.createElement("div");
    e.className = "row";
    const h = doc.createElement("strong");
    h.textContent = title;
    e.append(h);
    const p = doc.createElement("p");
    p.textContent = description;
    e.append(p);
    const a = doc.createElement("div");
    a.className = "actions";
    for (const b of buttons) {
      const button = doc.createElement("button");
      button.textContent = b.label;
      button.disabled = !!b.disabled;
      button.addEventListener("click", b.click);
      a.append(button);
    }
    e.append(a);
    return e;
  }
  const cost = (value: Record<string, number>) =>
    Object.entries(value)
      .map(([id, n]) => `${ITEMS[id].name} ${amount(id)}/${n}`)
      .join(" · ");
  function detail(force = false) {
    if (!tab || !view) return;
    const key = `${tab}/${Math.floor(view.tick / 20)}/${view.items.map((i) => `${i.id}:${i.quantity}:${i.container}`).join()}/${view.phase}`;
    if (!force && lastDetail === key) return;
    lastDetail = key;
    const content = $("#detail-content");
    content.replaceChildren();
    $("#detail").hidden = false;
    const titles: Record<string, string> = {
      inventory: "背包与附近物资",
      craft: "制作与工作",
      build: "从零建造",
      research: "三条研究路线",
      companions: "伙伴与指挥",
      skills: "人物与技能",
      tasks: "任务与协作",
      vehicles: "载具与模块",
    };
    $("#detail-title").textContent = titles[tab];
    const add = (...args: Parameters<typeof row>) =>
      content.append(row(...args));
    if (tab === "inventory") {
      for (const r of view.resources.filter(
        (r) => distance(r.position, view!.self.position) <= 2.5,
      ))
        add(`资源点：${ITEMS[r.definition].name}`, `剩余 ${r.remaining}`, [
          {
            label: "采集",
            click: () =>
              command("Gather", {
                x: Math.floor(r.position.x / TILE),
                y: Math.floor(r.position.y / TILE),
              }),
          },
        ]);
      for (const container of view.containers) {
        const items = view.items.filter(
          (i) => i.container === container.id && i.quantity > 0,
        );
        if (!items.length) continue;
        add(
          container.id === view!.self.inventory
            ? "随身背包"
            : `附近容器 #${container.id}`,
          container.state === "normal"
            ? `容量 ${(container.capacity / 1000).toFixed(1)} kg`
            : `状态：${container.state}`,
          container.state === "normal"
            ? []
            : [
                {
                  label: "整理遗物",
                  click: () =>
                    command("RecoverLoot", { container: container.id }),
                },
              ],
        );
        for (const i of items) {
          const def = ITEMS[i.definition],
            own = i.container === view!.self.inventory;
          const buttons: Parameters<typeof row>[2] = [];
          if (!own)
            buttons.push({
              label: "取用",
              click: () => transfer(i.id, view!.self.inventory, 1),
            });
          else {
            if (def.food || def.water || def.heal)
              buttons.push({
                label: "使用",
                click: () => command("Consume", { item: i.id }),
              });
            if (def.knowledge)
              buttons.push({
                label: "阅读",
                click: () => command("Read", { item: i.id }),
              });
            const dest = view.containers.find(
              (c) => !c.actor && c.owner === view!.self.id,
            );
            if (dest)
              buttons.push({
                label: "存入附近容器",
                click: () => transfer(i.id, dest.id, 1),
              });
          }
          add(
            `${def.name} × ${i.quantity}`,
            `${((def.mass * i.quantity) / 1000).toFixed(2)} kg`,
            buttons,
          );
        }
      }
    }
    if (tab === "craft" || tab === "build" || tab === "research") {
      for (const j of view.jobs.filter(
        (j) => j.state !== "Complete" && j.state !== "Cancelled",
      ))
        add(
          `进行中：${RECIPES[j.definition]?.name ?? BUILDINGS[j.definition]?.name ?? RESEARCH[j.definition]?.name ?? j.definition}`,
          `${Math.floor((j.done / j.required) * 100)}% · ${j.reason ? (reasons[j.reason] ?? j.reason) : j.state}`,
          [{ label: "取消", click: () => command("CancelJob", { job: j.id }) }],
        );
      const defs =
        tab === "craft" ? RECIPES : tab === "build" ? BUILDINGS : RESEARCH;
      for (const [id, d] of Object.entries(defs)) {
        const known = tab === "research" && view.self.knowledge.includes(id);
        add(
          d.name,
          `${cost(d.cost)} · ${d.ticks / 20} 秒${"workstation" in d ? ` · ${BUILDINGS[d.workstation!]?.name ?? "徒手"}` : ""}`,
          [
            {
              label: known
                ? "已完成"
                : tab === "build"
                  ? "建在东侧两格"
                  : tab === "research"
                    ? "研究"
                    : "制作",
              disabled: !!known,
              click: () => {
                if (tab === "build")
                  command("Build", {
                    definition: id,
                    x:
                      Math.floor(view!.self.position.x / TILE) * TILE +
                      2 * TILE +
                      128,
                    y: Math.floor(view!.self.position.y / TILE) * TILE + 128,
                  });
                else
                  command(tab === "craft" ? "Craft" : "Research", {
                    definition: id,
                  });
              },
            },
          ],
        );
      }
      if (tab === "build")
        for (const b of view.buildings.filter((b) => b.owner === view!.self.id))
          add(
            `${BUILDINGS[b.definition].name} #${b.id}`,
            `建造 ${b.progress}% · 生命 ${b.hp} · ${b.powered ? "通电" : "未通电"}${b.occupied ? " · 已形成占据区" : ""}`,
            [
              {
                label: "维修",
                click: () => command("RepairBuilding", { building: b.id }),
              },
              ...(b.definition === "generator"
                ? [
                    {
                      label: b.powered ? "关闭" : "启动",
                      click: () => command("Power", { building: b.id }),
                    },
                  ]
                : []),
              ...(b.definition === "door"
                ? [
                    {
                      label: b.open ? "关门" : "开门",
                      click: () => command("ToggleDoor", { building: b.id }),
                    },
                  ]
                : []),
            ],
          );
    }
    if (tab === "skills") {
      if (view.self.invitedBy)
        add(
          "收到组织邀请",
          `领袖 #${view.self.invitedBy}，接受后仍由你自己操作。`,
          [{ label: "同意加入", click: () => command("AcceptInvitation") }],
        );
      add(
        view.self.name,
        `生命 ${view.self.hp}/100 · ${view.self.life === "Dead" ? "永久死亡" : "存活"} · 知识 ${view.self.knowledge.length}`,
      );
      for (const [id, name] of Object.entries(SKILLS))
        add(name, `${view.self.skills[id]} 经验`);
      for (const knowledge of view.self.knowledge)
        add(RESEARCH[knowledge]?.name ?? knowledge, "已掌握");
    }
    if (tab === "companions") {
      for (const a of view.actors.filter(
        (a) =>
          a.life === "Dead" &&
          ["animal", "infected"].includes(a.kind) &&
          distance(a.position, view!.self.position) < 3,
      ))
        add(a.name, "提取遗体材料不会恢复生命。", [
          {
            label: "采集遗体材料",
            click: () => command("Butcher", { target: a.id }),
          },
        ]);
      add(
        "统一指挥预算",
        "驯兽与生物控制取较高等级，不叠加；同时随行最多 3 个。",
      );
      for (const c of view.companions)
        add(
          `${c.type === "pet" ? "宠物" : "受控感染体"} #${c.id}`,
          `${c.state} · 稳定 ${c.stability} · 训练 ${c.training} · 占用 ${c.cost}`,
          [
            { label: "训练", click: () => command("Train", { target: c.id }) },
            { label: "改造", click: () => command("Modify", { target: c.id }) },
            { label: "部署", click: () => command("Deploy", { target: c.id }) },
            ...["follow", "guard", "rest", "retreat"].map((order, i) => ({
              label: ["跟随", "驻守", "休整", "撤退"][i],
              click: () => command("CompanionOrder", { target: c.id, order }),
            })),
          ],
        );
      for (const a of view.actors.filter(
        (a) =>
          a.life === "Alive" &&
          ["animal", "infected"].includes(a.kind) &&
          distance(a.position, view!.self.position) < 3 &&
          !view!.companions.some((c) => c.id === a.id),
      ))
        add(a.name, `生命 ${a.hp}`, [
          {
            label: "约束捕获",
            click: () => command("Capture", { target: a.id }),
          },
          ...(a.kind === "animal"
            ? [
                {
                  label: "狩猎",
                  click: () => command("Hunt", { target: a.id }),
                },
              ]
            : []),
        ]);
    }
    if (tab === "vehicles") {
      add("从底盘开始", "需要先研究重装载具，制作真实底盘及模块。", [
        {
          label: "装配陆行车",
          click: () => command("AssembleVehicle", { definition: "buggy" }),
        },
        {
          label: "装配船艇",
          click: () => command("AssembleVehicle", { definition: "boat" }),
        },
      ]);
      for (const v of view.vehicles)
        add(
          `${v.definition === "boat" ? "船艇" : "陆行车"} #${v.id}`,
          `生命 ${v.hp} · 燃料 ${v.fuel} · 模块 ${v.modules.join(" / ") || "无"}`,
          [
            {
              label: "加入驾驶席",
              click: () => command("EnterVehicle", { vehicle: v.id }),
            },
            {
              label: "加入炮手席",
              click: () =>
                command("EnterVehicle", { vehicle: v.id, seat: "gunner" }),
            },
            {
              label: "车载射击",
              click: () => {
                const t = view!.actors
                  .filter((a) => a.kind === "infected" && a.life === "Alive")
                  .sort(
                    (a, b) =>
                      distance(a.position, v.position) -
                      distance(b.position, v.position),
                  )[0];
                if (t) command("VehicleFire", { target: t.id });
              },
            },
            {
              label: "下车",
              click: () => command("ExitVehicle", { vehicle: v.id }),
            },
            {
              label: "加油",
              click: () => command("Refuel", { vehicle: v.id }),
            },
            {
              label: "操纵练习",
              click: () => command("PracticeDriving", { vehicle: v.id }),
            },
            ...["engine_module", "gun_module", "armor_module"].map(
              (module) => ({
                label: `安装${ITEMS[module].name}`,
                click: () =>
                  command("InstallModule", { vehicle: v.id, module }),
              }),
            ),
          ],
        );
    }
    if (tab === "tasks") {
      add("实物委托", "奖励从发布者的真实库存预留；交付后验收一次。");
      for (const t of view.tasks)
        add(
          `收集 ${ITEMS[t.target]?.name ?? t.target} × ${t.amount}`,
          `${t.state} · 已交付 ${t.delivered} · 奖励 ${ITEMS[t.reward.definition].name} × ${t.reward.quantity}`,
          [
            {
              label: "接受",
              click: () => command("AcceptTask", { task: t.id }),
            },
            {
              label: "交付所需物品",
              click: () => command("DeliverTask", { task: t.id }),
            },
            {
              label: "结算",
              click: () => command("SettleTask", { task: t.id }),
            },
            {
              label: "取消",
              click: () => command("CancelTask", { task: t.id }),
            },
          ],
        );
      add("发布木材收集任务", "目标 3 木材，奖励 1 罐头；交付到当前背包。", [
        {
          label: "发布",
          click: () =>
            command("PublishTask", {
              definition: "wood",
              amount: 3,
              destination: view!.self.inventory,
              reward: "food",
              rewardQuantity: 1,
            }),
        },
      ]);
      for (const a of view.actors.filter(
        (a) =>
          a.kind === "npc" &&
          a.life === "Alive" &&
          distance(a.position, view!.self.position) < 3,
      ))
        add(a.name, "先提供食物建立信任，再邀请同行。", [
          { label: "赠送食物", click: () => command("Gift", { target: a.id }) },
          {
            label: "邀请加入",
            click: () => command("Recruit", { target: a.id }),
          },
        ]);
    }
  }
  function accept(packet: Packet) {
    if (
      packet.delta &&
      view &&
      packet.delta.worldId === view.worldId &&
      packet.delta.next <= view.seq
    ) {
      room?.sendAction({
        kind: "__view_ack",
        worldId: view.worldId,
        seq: view.seq,
      } as unknown as Command);
      return;
    }
    if (packet.delta) {
      try {
        if (!view) throw new Error("NoBaseline");
        packet = { ...packet, view: applyViewDelta(view, packet.delta) };
      } catch {
        room?.sendAction({ kind: "__resync_view" } as Command);
        return;
      }
    }
    if (!packet.view) return;
    view = packet.view;
    if (mode === "online")
      room?.sendAction({
        kind: "__view_ack",
        worldId: view.worldId,
        seq: view.seq,
      } as unknown as Command);
    if (mode === "local")
      win.localStorage.setItem("ember.lastWorld", view.worldId);
    if (lastEpoch !== view.binding.epoch) {
      lastEpoch = view.binding.epoch;
      sequence = view.binding.sequence;
    } else sequence = Math.max(sequence, view.binding.sequence);
    show("game");
    busy = false;
    block();
    if (mode === "online" && !paused) post("online-view", { view });
    render();
    if (
      packet.receipt &&
      !packet.receipt.ok &&
      packet.receipt.commandId !== lastReceipt
    ) {
      lastReceipt = packet.receipt.commandId ?? "";
      toast(packet.receipt.code);
    }
  }
  function render() {
    if (!view) return;
    $("#world-clock").textContent =
      `第 ${view.day} 日 · ${String(Math.floor((view.tick % 36000) / 1500)).padStart(2, "0")}:${String(Math.floor((view.tick % 1500) / 25)).padStart(2, "0")} · ${view.climate}`;
    $("#population").textContent =
      `幸存者 ${view.population.npc} · 感染体 ${view.population.infected} · 待安置 ${view.population.pending}`;
    $("#hp").textContent = `${view.self.hp} / 100`;
    $("#hp-meter").style.width = `${view.self.hp}%`;
    $("#needs").textContent = `${view.self.food} / ${view.self.water}`;
    $("#fatigue").textContent = String(view.self.fatigue);
    $("#save-state").textContent =
      `${mode === "local" ? "本地已提交" : "联机会话"} #${view.seq} · ${view.phase}`;
    const journal = $("#journal");
    journal.replaceChildren();
    for (const e of view.events.slice(-3)) {
      const p = doc.createElement("p");
      p.textContent = e.text;
      journal.append(p);
    }
    if (view.self.life === "Dead")
      block(
        "永久死亡",
        view.result ?? "角色已死亡，原物品留在世界中。本角色不能复活。",
      );
    else if (view.phase === "CapacityBlocked")
      block(
        "世界安置容量不足",
        "每日人口账本已记录。安全安置完成前，世界暂停。",
      );
    detail();
  }
  async function setupRoom() {
    if (room) return;
    const { OnlineRoomSession } = await import(
      "@vibegame/state-sync-runtime/client"
    );
    room = new OnlineRoomSession<Command, Packet>({
      minPlayersToStart: 2,
      roomClient: rooms,
    });
    roomRelease = room.subscribeEvents({
      onRoomUpdate: (r) => {
        if (screen === "game") return;
        show("waiting");
        roomId = r.id ?? room?.roomId ?? roomId;
        $("#room-id").textContent = `房间 ${roomId}`;
        $("#seats").replaceChildren(
          ...r.players.map((p) =>
            row(
              p.name || "幸存者",
              `${p.isHost ? "房主" : "成员"}${p.isMe ? " · 你" : ""}`,
            ),
          ),
        );
        $<HTMLButtonElement>('[data-ui-action="start-room"]').disabled =
          !r.isHost || r.players.length < 2;
        block();
        busy = false;
      },
      onGameInit: accept,
      onGameUpdate: accept,
      onGameLoading: () =>
        block("正在准备共同世界", "服务端正在生成地形、安置人口并绑定角色。"),
      onGameOver: (r) =>
        toast(String((r as { result?: string })?.result ?? "本局结束")),
      onDisconnected: (i) => {
        connected = false;
        stop();
        block(
          "连接已中断",
          i?.autoRecovering
            ? "正在重连原角色。"
            : "角色仍留在权威世界，重连不会复活。",
        );
      },
      onReconnected: () => {
        connected = true;
        block();
      },
      onError: (e) => {
        busy = false;
        block();
        toast(String(e));
      },
    });
  }
  async function refresh() {
    if (!room || polling || screen !== "lobby" || doc.hidden) return;
    polling = true;
    try {
      const found = await room.listRooms();
      $("#rooms").replaceChildren(
        ...found.map((raw) => {
          const r = raw as {
            id?: string;
            roomId?: string;
            name?: string;
            playerCount?: number;
          };
          const id = r.id ?? r.roomId ?? "";
          return row(r.name ?? id, `${r.playerCount ?? "?"} / 4 人`, [
            {
              label: "加入",
              click: () => void requestRoom(() => room!.joinRoom(id)),
            },
          ]);
        }),
      );
      if (!found.length)
        $("#rooms").textContent = "暂无房间，可以创建一个并邀请同伴。";
    } catch (e) {
      toast(String(e));
    } finally {
      polling = false;
    }
  }
  async function requestRoom(fn: () => Promise<unknown>) {
    if (busy) return;
    busy = true;
    block("正在连接房间", "正在向平台申请席位。");
    try {
      await fn();
    } catch (e) {
      toast(String(e));
      block();
      busy = false;
    }
  }
  async function action(a: string) {
    try {
      if (a === "single") {
        if (busy) return;
        busy = true;
        mode = "local";
        block("正在打开世界", "恢复已提交的存档，或生成一个新世界。");
        post("open-local", {
          seed: $<HTMLInputElement>("#seed").value,
          biome: $<HTMLSelectElement>("#biome").value,
          worldId: $<HTMLSelectElement>("#saved-world").value,
        });
      } else if (a === "import") {
        const input = doc.createElement("input");
        input.type = "file";
        input.accept = ".json";
        input.onchange = async () => {
          const f = input.files?.[0];
          if (f) {
            if (f.size > 128 * 1024 * 1024) {
              toast("存档文件过大");
              return;
            }
            block(
              "正在验证导入存档",
              "校验内容版本与身份。导入会创建副本，不覆盖原存档。",
            );
            post("import", { text: await f.text() });
          }
        };
        input.click();
      } else if (a === "online") {
        mode = "online";
        await setupRoom();
        show("lobby");
        const occupied = await room!.peekCurrentRoom();
        $("#occupied").hidden = !occupied;
        if (occupied) {
          roomId = occupied.roomId;
          $("#occupied-text").textContent =
            `检测到你仍在房间 ${roomId}，请选择重连或离开。`;
        } else await refresh();
      } else if (a === "create-room")
        await requestRoom(() =>
          room!.createRoom({ name: "余烬共同体", maxPlayers: 4 }),
        );
      else if (a === "refresh-rooms") await refresh();
      else if (a === "restore-room")
        await requestRoom(() => room!.restoreCurrentRoom());
      else if (a === "leave-occupied") {
        await rooms.leave(roomId);
        $("#occupied").hidden = true;
        await refresh();
      } else if (a === "start-room") {
        block("正在准备共同世界", "等待服务端完成生成。");
        room?.startGame();
      } else if (a === "leave-room" || a === "menu") {
        stop();
        if (room?.roomId) {
          room.disconnect();
          await rooms.leave(room.roomId);
        }
        post("close");
        view = undefined;
        tab = "";
        $("#detail").hidden = true;
        show(a === "leave-room" ? "lobby" : "menu");
        block();
      } else if (a.startsWith("tab-")) {
        stop();
        tab = a.slice(4);
        detail(true);
      } else if (a === "close-detail") {
        tab = "";
        $("#detail").hidden = true;
      } else if (a === "interact") interact();
      else if (a === "attack") attack();
      else if (a === "rest") command("Rest");
      else if (a === "pause")
        command("Pause", { paused: view?.phase !== "Paused" });
      else if (a === "retry") {
        post("retry");
        block();
      } else if (a === "export") {
        if (mode === "local") post("export");
        else toast("联机会话不能导出为本地权威存档。");
      }
    } catch (e) {
      busy = false;
      block();
      toast(String(e));
    }
  }
  const receive = (e: MessageEvent) => {
    const m = e.data;
    if (m?.channel !== CHANNEL || disposed) return;
    if (m.kind === "ready") {
      post("inspect-once");
      game.loaded();
    }
    if (m.kind === "view") accept({ view: m.view });
    if (m.kind === "receipt" && !m.receipt.ok) toast(m.receipt.code);
    if (m.kind === "error") {
      busy = false;
      block("操作暂时停止", reasons[m.error] ?? m.error, !!view);
      toast(m.error);
    }
    if (m.kind === "saves") {
      const select = $<HTMLSelectElement>("#saved-world");
      for (const s of m.saves) {
        const o = doc.createElement("option");
        o.value = s.id;
        o.textContent = `${s.seed} · ${s.biome} · #${s.seq}`;
        select.append(o);
      }
      const last = win.localStorage.getItem("ember.lastWorld");
      if (last && m.saves.some((s: { id: string }) => s.id === last))
        select.value = last;
    }
    if (m.kind === "save-export" && m.text) {
      const url = URL.createObjectURL(
        new Blob([m.text], { type: "application/json" }),
      );
      const a = doc.createElement("a");
      a.href = url;
      a.download = `ember-${m.worldId}.json`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      toast("已导出当前已提交的单人存档。");
    }
  };
  const listen = (
    target: EventTarget,
    type: string,
    fn: EventListener,
    options?: AddEventListenerOptions,
  ) => {
    target.addEventListener(type, fn, options);
    releases.push(() => target.removeEventListener(type, fn, options));
  };
  listen(port, "message", receive as EventListener);
  port.start();
  const keyDown = (e: KeyboardEvent) => {
    if (
      ["INPUT", "TEXTAREA", "SELECT"].includes(
        (e.composedPath()[0] as HTMLElement)?.tagName,
      )
    )
      return;
    if (screen === "menu" && e.code === "Enter") {
      e.preventDefault();
      void action("single");
      return;
    }
    if (screen !== "game" || e.repeat) return;
    if (
      [
        "KeyW",
        "KeyA",
        "KeyS",
        "KeyD",
        "ArrowUp",
        "ArrowDown",
        "ArrowLeft",
        "ArrowRight",
        "ShiftLeft",
        "ShiftRight",
      ].includes(e.code)
    ) {
      if (tab) return;
      e.preventDefault();
      keys.add(e.code);
      keyMove();
    } else if (e.code === "KeyE") {
      e.preventDefault();
      interact();
    } else if (e.code === "Space") {
      e.preventDefault();
      attack();
    } else if (e.code === "KeyB") void action("tab-inventory");
    else if (e.code === "Escape") void action("close-detail");
  };
  const keyMove = () =>
    move(
      Number(keys.has("KeyD") || keys.has("ArrowRight")) -
        Number(keys.has("KeyA") || keys.has("ArrowLeft")),
      Number(keys.has("KeyS") || keys.has("ArrowDown")) -
        Number(keys.has("KeyW") || keys.has("ArrowUp")),
    );
  listen(win, "keydown", keyDown as EventListener);
  listen(win, "keyup", ((e: KeyboardEvent) => {
    if (keys.delete(e.code)) keyMove();
  }) as EventListener);
  listen(win, "blur", () => stop());
  root.querySelectorAll<HTMLElement>("[data-move]").forEach((button) => {
    listen(button, "pointerdown", ((e: PointerEvent) => {
      e.preventDefault();
      button.setPointerCapture(e.pointerId);
      const [x, y] = button.dataset.move!.split(",").map(Number);
      move(x, y);
    }) as EventListener);
    listen(button, "pointerup", () => move());
    listen(button, "pointercancel", () => move());
    listen(button, "lostpointercapture", () => move());
  });
  const setPaused = (value: boolean) => {
    stop();
    paused = value;
    post("suspend", { paused });
    if (!value && mode === "online" && view) post("online-view", { view });
  };
  releases.push(
    lifecycle.register({
      pause: () => setPaused(true),
      resume: () => setPaused(false),
      getState: () => ({ paused }),
    }),
  );
  listen(doc, "visibilitychange", () => setPaused(doc.hidden));
  const timer = setInterval(() => {
    if (Date.now() > statusUntil) $("#status").hidden = true;
    if (screen === "lobby") void refresh();
  }, 2000);
  releases.push(() => clearInterval(timer));
  listen($("#seed"), "input", () => {
    $<HTMLSelectElement>("#saved-world").value = "";
  });
  game.loading({ phase: "presentation" });
  post("inspect");
  post("list-saves");
  show("menu");
  return {
    dispose() {
      disposed = true;
      stop();
      for (const release of releases.reverse()) release();
      roomRelease?.();
      room?.disconnect();
      mounted.dispose();
    },
  };
}
