#!/usr/bin/env python3
"""BBB headless domain checks only. Does not import/export or open a preview."""
import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
SUITES = (
    "support_dependency_suite",
    "support_baseline_suite", "support_baseline_transaction_suite",
    "snapshot_batch_suite",
    "navigation_template_transaction_suite",
    "navigation_template_safety_suite",
    "navigation_template_probe",
    "suffix_exit_probe",
    "support_endpoint_suite",
    "os_support_probe",
    "expansion_transaction_suite", "content_consumers_suite",
    "actor_release_suite", "door_transaction_suite", "door_commit_probe", "exit_transaction_equivalence_suite", "exit_proof_suite",
    "geometry_history_suite", "walk_cost_probe", "flat_clearance_suite",
    "continuous_npc_suite", "action_contract_suite", "dynamic_asset_suite", "delivery_capture_suite", "supplement_cold_equivalence_suite", "spatial_purposes_suite",
    "check_parse", "building_state_suite", "building_surface_dynamic_suite", "imported_surface_suite", "domain_suite", "legacy_suite", "door_cost_suite", "door_phase_suite", "door_projection_suite", "cold_equivalence_suite", "cold_fifth_equivalence_suite", "floor_cold_equivalence_suite", "floor_certificate_safety_suite", "validation_key_cost_suite", "validation_identity_suite", "support_crop_cost_suite", "support_witness_suite", "support_bins_suite", "navigation_validation_suite", "terrain_route_suite", "generated_camp_suite", "housing_courtyard_life_suite", "geometry_templates_suite", "tool_boundary_suite", "route_reuse_probe", "route_phase_probe", "movement_candidates_suite",
    "npc_work_suite", "camp_suite", "stair_suite", "npc_camp_suite", "generated_furniture_probe", "visual_surface_suite", "dressing_geometry_suite", "dressing_state_suite", "cabinet_state_suite", "interaction_area_suite", "fine_step_route_suite", "movement_contract_suite", "movement_standing_probe", "continuous_boundary_suite", "step_motion_suite",
    "cache_safety_suite", "metadata_reuse_suite", "metadata_invalidation_suite", "snapshot_suite", "presentation_suite", "roof_coherence_suite", "interior_adapter_suite", "furniture_stability_suite", "family_generation_suite", "family_matrix_suite", "housing_matrix_suite", "housing_life_suite", "housing_route_probe", "housing_motion_probe", "housing_compatibility_suite", "radio_boundary_suite", "terrain_reservation_suite", "profile_domain", "route_hotspots", "walking_surface_suite", "voxel_clearance_suite", "candidate_tokens_suite", "floor_clearance_suite", "rural_route_suite", "hostile_structure_suite", "support_projection_suite",
)


def quiet_window():
    # A owns the window. This is an additional guard, not permission to start
    # tests based on a stale report; re-read the board before invoking.
    board = ROOT / "outputs/R3.3-主引擎任务板.md"
    # A may prepend a task/status section above the active window heading.
    # Read the newest explicit heading, rather than assuming line one.
    heading = next((line for line in board.read_text().splitlines()
                    if line.startswith("#") and
                    any(term in line for term in ("安静窗", "冻结"))), "")
    # Newer explicit release wins over historical windows below it. Never
    # treat yesterday's undated hours as today's permission or prohibition.
    if "解除" in heading:
        return
    match = re.search(r"(\d{4}-\d\d-\d\d).*?(\d\d):(\d\d)[—–-](\d\d):(\d\d)", heading)
    now = dt.datetime.now()
    if match and now.date() == dt.date.fromisoformat(match.group(1)):
        sh, sm, eh, em = map(int, match.groups()[1:])
        minute = now.hour * 60 + now.minute
        start, end = sh * 60 + sm, eh * 60 + em
        if (start <= minute < end if end >= start else minute >= start or minute < end):
            raise SystemExit(f"A build/performance window active: {heading}")


def source_snapshot():
    """Record relevant native text sources, excluding import cache and logs."""
    project = ROOT / "godot/afterglow"
    paths = [project / "project.godot"]
    # Other domains may author unrelated test files in parallel. They are not
    # loaded by these B scripts; production sources remain fully recorded.
    for folder in ("scripts", "data", "tests/buildings", "scenes", "themes"):
        paths.extend(p for p in (project / folder).rglob("*")
                     if p.is_file() and p.suffix in (".gd", ".gdshader", ".json", ".tscn", ".tres"))
    return {str(p.relative_to(project)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(paths) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("suites", nargs="*", choices=SUITES)
    parser.add_argument("--label", default=dt.datetime.now().strftime("%H%M%S"))
    parser.add_argument("--timeout", type=int, default=50)
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.label):
        raise SystemExit("label must be a filename-safe unique token")
    out = ROOT / "work/r3-3-bbb"
    out.mkdir(parents=True, exist_ok=True)
    results = []
    for suite in args.suites or SUITES:
        quiet_window()
        log = out / f"{suite}-{args.label}.log"
        if log.exists():
            raise SystemExit(f"Evidence already exists, choose another label: {log}")
        command = [str(ROOT / "work/tooling/godot/Godot.app/Contents/MacOS/Godot"),
                   "--headless", "--path", str(ROOT / "godot/afterglow"),
                   "--script", f"res://tests/buildings/{suite}.gd"]
        if suite in ("support_dependency_suite", "support_baseline_transaction_suite", "snapshot_batch_suite", "navigation_template_transaction_suite", "navigation_template_safety_suite", "navigation_template_probe", "suffix_exit_probe", "exit_proof_suite", "exit_transaction_equivalence_suite", "door_commit_probe", "door_transaction_suite", "flat_clearance_suite", "walk_cost_probe", "geometry_history_suite", "supplement_cold_equivalence_suite", "legacy_suite", "door_cost_suite", "door_phase_suite", "door_projection_suite", "cold_equivalence_suite", "cold_fifth_equivalence_suite", "floor_cold_equivalence_suite", "floor_certificate_safety_suite", "validation_key_cost_suite", "support_crop_cost_suite", "support_bins_suite", "geometry_templates_suite", "stair_suite", "profile_domain", "route_hotspots", "route_reuse_probe", "route_phase_probe", "movement_candidates_suite", "walking_surface_suite", "voxel_clearance_suite", "candidate_tokens_suite", "floor_clearance_suite", "support_projection_suite"):
            command += ["--", str(ROOT / "work/r3-2/ordinary-source-713/checkpoint.v5.json")]
        if suite == "generated_furniture_probe":
            command += ["--", str(ROOT / "work/r3-3-bbb/sixth-active-readonly-capture-visual.json")]
        if suite == "support_endpoint_suite":
            command += ["--", str(ROOT / "work/r3-3/build10-support-scene-20261115-123152/saves/77c9bd2b11934109262bca3b7da15b9c/a.json")]
        timed_out = False
        before = source_snapshot()
        with log.open("w") as stream:
            try:
                run = subprocess.run(command, cwd=ROOT, stdout=stream,
                                     stderr=subprocess.STDOUT, timeout=args.timeout)
                code = run.returncode
            except subprocess.TimeoutExpired:
                code, timed_out = -1, True
        after = source_snapshot()
        drift = [key for key in sorted(before.keys() | after.keys())
                 if before.get(key) != after.get(key)]
        log.with_suffix(".manifest.json").write_text(json.dumps({
            "scope": "native text-source identity during this B domain check; not official PCK identity",
            "before": before, "after": after, "source_stable": not drift,
            "changed_added_or_removed": drift,
        }, ensure_ascii=False, indent=2))
        body = log.read_text()
        parsed = None
        for line in reversed(body.splitlines()):
            try:
                candidate = json.loads(line)
                if isinstance(candidate, dict) and "ok" in candidate:
                    parsed = candidate
                    break
            except ValueError:
                pass
        if parsed is not None:
            log.with_suffix(".json").write_text(json.dumps(parsed, ensure_ascii=False, indent=2))
        diagnostics = [line for line in body.splitlines()
                       if re.match(r"^(?:SCRIPT ERROR|ERROR|WARNING):", line)]
        row = {"suite": suite, "exit": code, "timeout": timed_out,
               "ok": code == 0 and bool(parsed and parsed.get("ok")) and not diagnostics and not drift,
               "checks": len(parsed.get("checks", [])) if parsed else 0,
               "source_stable": not drift, "source_drift": drift,
               "diagnostics": diagnostics,
               "log": str(log.relative_to(ROOT))}
        results.append(row)
        print(json.dumps(row, ensure_ascii=False), flush=True)
        if not row["ok"]:
            print("\n".join(line for line in body.splitlines()
                            if line.startswith("FAIL") or "ERROR" in line)[:3500], flush=True)
    result = {"scope": "BBB headless domain checks, not official application/FPS/visual acceptance",
              "ok": all(row["ok"] for row in results), "results": results}
    (out / f"summary-{args.label}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
