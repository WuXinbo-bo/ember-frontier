# CCC world / terrain / environment regression

Production modules live in the same `godot/afterglow` project as A/B/UI. These
headless checks support integration; they do not launch a second formal preview
or qualify an exported macOS application, Metal rendering, FPS, or a stage gate.

Before running, read the current window at the top of
`outputs/R3.3-主引擎任务板.md`. Do not run these CPU/file checks during A's exclusive
build/performance window. The official preview/export and complete player route
belong to A. Keep A/B/UI source and actual user saves untouched.

From the repository root, in an allowed code/function window:

```sh
python3 godot/afterglow/tests/world/verify_domain.py --storage
```

The verifier uses A's already verified Godot binary at
`work/tooling/godot/Godot.app/Contents/MacOS/Godot`; it does not install an engine.
It records recursively referenced source SHA256 values before and after each
entry, archives older reports/logs, and fails on missing output, timeout, changed
source, failed checks, or engine/script errors. Exit code zero alone is not a pass.
Output: `outputs/r3.3-ccc-evidence/native-verified-manifest.json` and the referenced
per-entry JSON/logs. Repeated suites supersede rather than add to old check counts.

- `run_world_tests.gd`: real ordinary713 source checksum/1536 chunk LE hashes,
  every-cell native roundtrip, legacy UTF16, negative/boundary cells, capability
  isolation/CAS/tombstones, mesh winding/native physics, orthographic picking,
  residency, complete-footprint ground decoration invalidation.
- `run_domain_integration.gd`: real A runtime command/tick, B final-draft safety,
  C labor/pause/resume/atomic materials and terrain; complete B rural proposal.
  It does not substitute a test call for A's terrain advance or private commit.
- `run_storage_integration.gd`: real A Thread/FileAccess double slots + C codec,
  fresh C evidence directories, damaged SHA fallback, real ordinary import and
  exact old terrain-tool identity/qualities in one live production table.
  It never writes `user://saves`. Old negative malformed-JSON logs are retained;
  the current checksum-damage vector uses valid JSON to avoid an expected parser
  error being confused with an unhandled engine failure.

For a storage-only follow-up after an A storage change:

```sh
python3 godot/afterglow/tests/world/verify_domain.py --only=storage
```

Cost fixture, only in an explicitly available window:

```sh
work/tooling/godot/Godot.app/Contents/MacOS/Godot --headless --path godot/afterglow --script tests/world/profile_world_domain.gd -- outputs/r3.3-ccc-evidence/native-cost-new-run.json
```

Use a fresh output filename. It profiles the original preserved ordinary source;
record device/build/window and source fingerprints alongside it. Do not compare
headless CPU numbers to Metal FPS or browser budgets. The old baseline is
`native-cost-baseline.json`; keep it and failed logs. Codec/load work belongs in a
loading phase or A's save worker. Initial mesh queue's 4 ms is a soft per-frame
budget; one chunk cannot be interrupted, and synchronous edit-neighbor rebuilds
must be measured in the real app. PackedInt32 cells have twice the old Uint16
cell-buffer bytes; snapshots, shapes and textures are additional costs.

Maintenance triggers: Godot/template upgrade, source schema/generator/material
change, persisted-ID change, new terrain operation, capability or shared-fact
boundary, region/residency rules, or new environment footprint. Re-run these
checks, then A's actual old-city/double-region/IO/save-exit-restart/visual/long-run
routes. C owns data/codec and derived invalidation; B owns final safety/tool
reservations; A owns native storage/runtime/export and formal qualification.
Never regenerate an explored legacy town from seed, accept a plugin as a second
save authority, erase source originals, or infer stage approval from these tests.
# 调度第8节新增定向验证

仅在A代码/功能窗或允许的短领域窗口运行：

```
python3 godot/afterglow/tests/world/verify_domain.py --only=section8
python3 godot/afterglow/tests/world/verify_domain.py --only=profile
python3 godot/afterglow/tests/world/verify_domain.py --only=reservation
```

前者走A实际terrain_payload/router/runtime与B/C领域，覆盖新刷子、面邻格、半米高度、预留/暂停/取消和重访；环境检查覆盖原图SHA、米制、过渡连续性、挖填/冷热派生。真实物理瞄准和VA仍由A同.app验收；结构化`shared_input_gaps`必须单列，不被其它绿测掩盖。

后者使用保全的`outputs/r3.3-ccc-evidence/section8-before`源码；`section8_baseline_state.gd`只改旧state对旧view的资源路径，原字节及SHA另存，不用改写后的源码冒充原始基线。用同普通713全事实做prepare/查询，用同农村块交替测派生重建，排除预热并保留12个原始样本。隔离draft深拷贝、capability和完整结构验均保留；不能用头部CPU结果声称Metal/FPS通过。未来新增操作不能默认加入热事务短路清单；新实体/区域/块分配与实体删除必须保留完整图验证。任一导入仍先完整validate。

profile还核对1024列逐项结果、12种slab/洞/空腔/台阶/冷热邻块的greedy与非greedy逐面几何，以及最大安全revision的无变化事务/溢出拒绝。公共`world_data.gd`由两侧复用同一当前版本，故表中比较隔离State/View/Mesher/Environment改动，不声称是旧工程完整发布包对新包。最大安全整数使用整数常量，避免本机引擎浮点字面量舍入；`revision_limit_probe.gd`保留该诊断的可复现入口。

reservation使用实际C fill intent、A clock/codec和B transfer。C的id/source_id/净cost、暂停/保存/取消/最终扣料必须保持；B必须在reserved中纳入terrain（含tx.staged、暂停、excluding自身）。共享边界未接时此检查明确失败且保存精确载荷，不能因其它C检查通过就声称材料预留完整。修复后只需定向复验该边界，不反复重跑无关绿测。

历史23:44为14个注册源；最新为16（12原有+g01/g02/g03/a06），注册不等于正常机位可见。新增草土/碎石按1.6m顶面源对使用；挖填竖面保留各自原图的竖向米制。shader通过`use_variant=false`退回单源三相位，`break_repetition=false`退回原图单采样，UV米制不回退；两项均只改派生表现，绝不重建世界/旧档。头部检查不能替代Metal编译、实际纹理带宽或VA。


## 2026-11-14 image/contact follow-up

Only affected domain checks, in A's available code/function window:

```sh
python3 godot/afterglow/tests/world/verify_domain.py --only=environment
python3 godot/afterglow/tests/world/verify_domain.py --only=environment-cost
```

The first originally checked 33 vectors; the current affected suite checks 37
(see the fourth-package section below). These supersede the older 16, not add to it.
It installs the complete real B rural seed on one C world and checks delivered
G03/A06 bytes, actual native mip chains, all four alpha slots/baseline, two cutout
planes in the existing low-cover node, full footprint invalidation, contact bands
from actual live foundations, removal/tombstones, native-codec cold reload and
warm revisit. Reload must clear obsolete overlays immediately. Contact segments
cache only layout geometry, never old terrain/residency; every ground rebuild
queries the whole footprint. Entity changes rebuild layout; extension-only
notifications skip environmental scans. A remains responsible for real app/Metal.

The cost test compares the byte-identical pre-follow-up Environment with the new
one against the same complete B seed and warmed *current shared* Material loader.
Eight alternating samples per side follow two warmups. Report startup, forced
sync, actual terrain/extension notifications, and four chunk environment rebuilds
separately. Geometry/CPU counts are not FPS, GPU cost, whole TerrainView cost, or
formal draw calls. This change adds 26 contact meshes/415 quads, keeps 9 supported
trees and the original low-patch count. Startup costs increase; do not hide them.
Original PNGs/first 14 rows remain unchanged; physical filtering/mips are explicit
quality changes. Full native Metal/frame/VA evidence must use A's next unified app.

`environment-followup-before/` retains original source bytes. The copied baseline
script is verified byte for byte. `environment-followup-cost-summary.json` keeps
raw report identity, hardware, estimates and scope; `environment-material-adoption.json`
records image/mirror/import hashes. Older failing and superseded reports are
archived, not overwritten as success. No actual save directory is used.

## Fourth-package road-shoulder correction (2026-11-14)

The fourth package contains all 49 sources from the prior C handoff. Its actual
north-side screenshot still shows a dotted brown road outline. The old 09 decal
retains only 7.066% of its pixels at alpha-scissor 0.4, confined to 0.1574 m of the
0.65 m strip. The correction keeps the original PNG and geometry, uses that alpha
as a small boundary variation, and blends the actual grass/soil/road/gravel
sources in world metres. Terrain and shoulder share `ground_sampling.gdshaderinc`;
UV2 retains the original 1.6 x 0.65 m decal coordinates. Thin shoulders do not cast
shadows or write depth. They use alpha blending; its local overdraw, corner
appearance, Metal compilation and cost require A's next unified application.
The headless checks do not establish any of those visual/GPU outcomes.

```sh
python3 godot/afterglow/tests/world/verify_domain.py --only=environment
python3 godot/afterglow/tests/world/verify_domain.py --only=shoulder-cost
```

The affected environment suite now has 37 vectors, including the previously
retained 33, world/strip UV separation and real material endpoints, plus a grass
chunk bordering a cold gravel chunk and exact warm restoration. The cost entry
compares byte-identical `fourth_baseline_environment.gd` against current production
on the same complete B seed, alternating eight samples after two warmups. It
includes the screenshot's apron chunks and mixed road/gravel chunk `3,-1,5`;
surfaces, nodes and triangles are reported separately. The verifier follows and
fingerprints shader includes as dependencies. Older 16/33/4 and 2.723 ms results
retain their original source/workload identities. Do not sum them into a new pass.
