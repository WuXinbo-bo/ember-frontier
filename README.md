# 余烬边界 · 基础开发版本

## Godot 测试版（develop / wxb）

用 Godot 4.7 打开 `godot/afterglow/project.godot`，按 F5 进入游戏。Windows 导出使用 `Windows Desktop` 预设。

Godot 工程包含源代码、场景、工程配置、美术资产和回归测试。协作和发布流程见[分支与版本发布](docs/branch-workflow.md)。下方是原有的 ForgeAX 工程说明。

天工 ForgeAX 0.4.19 / TypeScript。目标为电脑、手机双端的 **2.5D 像素生存游戏**，视觉参考为用户确认的 **《隔离区》**。

当前交付重点是可运行、可验证、可继续开发的底层架构。画面、角色和场景均为调试占位资产，不是正式美术；正式素材将在下一阶段重新配置与导入。

## 从哪里开始

- [游戏工程与运行说明](game/README.md)
- [底层架构落地说明](docs/implementation/基础架构交付说明.md)
- [验证结果与限制](docs/implementation/验证报告.md)
- [后续逐项开发清单](docs/implementation/后续落实清单.md)
- [A01–A92 当前证据矩阵](docs/implementation/验收覆盖矩阵.md)
- [原始策划](apocalypse-survival-gdd-v0.4.md) · [原架构方案](docs/architecture/游戏底层架构方案-v1.0.md)

## 本地开发

工具版本：Node 24.22.1、pnpm 12.15.0、Engine/SDK 0.4.19。先使用造化插件安装/检查官方天工 SDK，再进入 `game/`：

```sh
pnpm install --frozen-lockfile
pnpm run check
pnpm dev
pnpm run test:play
```

使用造化插件的“启动当前项目预览”运行带平台 SDK 和联机宿主的预览；源码变化后使用同一会话的重新加载。当前机器预览服务使用端口 **55950**；端口是本机会话信息，不是固定部署地址。

## 状态边界

基础规则与接口已有实现及自动测试，不能将它们等同于完整策划验收。官方多人房间当前仍使用会话内存；另有经过实际磁盘重开测试的 SQLite 适配器，平台是否提供可持久化磁盘尚未证明。13 个研究分支已有配置，但分支内容与高阶玩法未全部展开。100 日人口账本成立，100 日规模实时性能未达目标。详情见验证报告。

未发布到造化。仓库为用户授权创建的私有开发仓库，不包含 GitHub 凭据、工具链缓存或生成构建产物。
