# 余烬边界 · 天工基础工程

版本 0.1.0。原生 Cordis Plugin + ForgeAX 正交场景 + 原生 HUD。当前画面只验证逻辑，最终采用 **2.5D 像素风格，参考《隔离区》**；美术和资产将在后续整体替换。

## 工具与命令

|工具|锁定版本|
|---|---|
|Node|24.22.1|
|pnpm|12.15.0|
|ForgeAX Engine / SDK|0.4.19|
|造化平台 SDK|0.2.0|

```sh
pnpm install --frozen-lockfile
pnpm run check          # 类型、规则/故障测试、官方工程检查、Node 服务端构建
pnpm dev                # 天工开发服务
pnpm run test:play      # 官方 owner 浏览器的实际输入与读档回归
pnpm run test:benchmark # 30/100 日人口安置 + 有限样本性能测量
pnpm build              # 天工构建
pnpm build:server       # 官方联机入口构建
```

带平台能力的预览从造化插件 `game_builder_preview_start` / `game_builder_preview_reload` 启动。使用同一项目根与会话，不另起替代 Canvas 或绕过官方 SDK。平台验证服务支持单人模式和多人大厅；单人模式不会调用 rooms API。

## 已接通的基础流程

选择种子/地貌或已有世界 → 本地事务恢复 → 移动/搜索/采集 → 背包与消费 → 制作/建造/研究长工作 → 生存与战斗 → 永久死亡与原物资遗留。支持本地导出与导入副本。联机入口具备房间列表、创建、加入、等待、启动、断线提示和永久席位绑定。

键盘：Enter 进入单人、WASD/方向键移动、Shift 潜行、E 搜索/采集、空格攻击、B 背包、Esc 关闭面板。小视口有方向、搜索、攻击与休息控件；正式手机手感仍待真机验收。

## 模块地图

|目录|职责|
|---|---|
|`assets/simulation/`|纯数据、确定性规则、命令、事务候选、人口、声学、地形、NPC、库存、载具|
|`assets/content/catalog.ts`|33 技能、有限物资、配方、建筑、三路线 13 分支研究定义|
|`assets/application/authority.ts`|串行命令和 K=0 提交屏障；提交确认后才推进对外状态|
|`assets/application/projection.ts`|按玩家过滤可见对象、背包与任务|
|`assets/application/replication.ts`|确认基线、增删改差量、缺基线回退全快照|
|`assets/adapters/indexeddb.ts`|浏览器原子事务、日志回放、checkpoint、单写者锁|
|`assets/application/save-file.ts`|版本/校验和/不变量验证；导入生成副本|
|`game/server/source/`|官方 PlatformServer 入口、房间生命周期、连接鉴权与节流|
|`game/server/source/persistence/sqlite.ts`|可选 Node SQLite WAL / FULL / fencing 持久化适配器|
|`assets/presentation/`|天工表现与可替换像素资产合同；不决定游戏规则|
|`assets/ui/`|菜单、基础操作 HUD 与桌面/触屏输入；只发意图|
|`assets/__tests__/`|核心规则、架构边界、故障恢复、Node 磁盘与房间合同测试|

`forge.json#roots` 是唯一插件装配入口。表现层读取提交后的投影；SimCore 不导入 DOM、引擎、数据库或平台 SDK。不要将 GUID、动画帧或图片路径写进权威角色状态。

## 存档与联机的明确限制

- 浏览器存档只在当前浏览器及源地址中有效；浏览器清理站点数据可能删除存档。可从菜单导出副本。
- 当前不提供旧内容版本自动迁移：内容 hash 不兼容时明确拒绝加载，不静默删物品或技能。
- 造化官方房间默认 `MemoryStore`，UI 明示“会话世界”。SQLite 适配器可供有明确持久磁盘的 Node 部署接入，不自动将平台房间改成永久世界。
- 第五名身份不能替换已占用的四个永久席位；死亡重连不会获得新角色。
- A01–A92 全产品验收、四浏览器同局、Android/iOS 真机、完整高阶分支与最终美术尚未完成。

## 测试与证据

测试报告和后续工作在上层 `docs/implementation/`。原生浏览器报告写入 `artifacts/play/scripts/playthrough/`；性能报告写入 `artifacts/architecture/`，这些生成目录不入库。提交的精简证据在 `../docs/implementation/evidence/`。

正式资产必须经官方 importer/Pack 建立稳定 GUID，遵守 `AGENTS.md`。当前 `visual-contract.ts` 的生产资产校验刻意不通过空资产集；不得把调试方块当作完成的像素资产。移动端 Landing 与发布封面也留到美术阶段。
