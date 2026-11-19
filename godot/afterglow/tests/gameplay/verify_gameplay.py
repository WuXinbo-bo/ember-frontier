"""Bounded E domain checks, real services, unique artifacts and source provenance."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "godot/afterglow"
GODOT = ROOT / "work/tooling/godot/Godot.app/Contents/MacOS/Godot"
ENTRIES = {
    "residents": "tests/integration/run_resident_life.gd",
    "gameplay": "tests/integration/run_gameplay.gd",
    "regression": "tests/gameplay/resident_regression.gd",
    "encounters": "tests/gameplay/encounter_regression.gd",
    "route": "tests/gameplay/generated_cooperation.gd",
    "outdoors": "tests/gameplay/resident_outdoors.gd",
    "recovery": "tests/gameplay/cooperation_recovery.gd",
    "material": "tests/gameplay/material_loop.gd",
    "motion": "tests/gameplay/resident_movement.gd",
    "social": "tests/gameplay/social_boundary.gd",
    "spatial_probe": "tests/gameplay/spatial_commit_probe.gd",
    "spatial_route": "tests/gameplay/spatial_route_probe.gd",
    "cursor": "tests/gameplay/gameplay_cursor.gd",
    "cursor_timers": "tests/gameplay/gameplay_cursor_timers.gd",
    "lifecycle": "tests/gameplay/resident_lifecycle.gd",
    "radio_stability": "tests/gameplay/radio_stability.gd",
    "perception": "tests/gameplay/perception_boundary.gd",
    "contracts": "tests/gameplay/intent_contracts.gd",
    "beds": "tests/gameplay/bed_candidates.gd",
    "delivery_recovery": "tests/gameplay/delivery_recovery.gd",
    "rural_completion": "tests/gameplay/rural_completion.gd",
    "release": "tests/gameplay/resident_release.gd",
    "capabilities": "tests/gameplay/ordinary_capabilities.gd",
    "radio_capability": "tests/gameplay/radio_capability.gd",
    "extension": "tests/gameplay/ordinary_extension.gd",
    "extension_presentation": "tests/gameplay/extension_presentation.gd",
}


def relevant(path, visual=False):
    # These headless checks assemble one runtime but never invoke UI, input,
    # or presentation. Keep their closure hashes, without treating unrelated
    # colleague changes as a failure of E's actual domain dependency set.
    return not path.startswith(tuple("godot/afterglow/scripts/" + name + "/" for name in (("input", "ui") if visual else ("input", "ui", "presentation"))))


def sources(entry):
    pending, found = [PROJECT / entry], {}
    visual = entry == ENTRIES["extension_presentation"]
    if visual:
        # D resolves saved appearance/skin paths dynamically. Hash original
        # assets, import settings AND actual remapped resources consumed here.
        pending.extend(p for p in (PROJECT / "data/gameplay/actors").rglob("*") if p.is_file())
        pending.append(PROJECT / "data/gameplay/props/r1_dropped_bundle.glb")
        assets = json.loads((PROJECT / "data/buildings/asset_manifest.json").read_text())
        pending.extend(PROJECT / assets["textures"][key]["resource"][6:] for key in ("wood_floor", "zinc"))
    while pending:
        path = pending.pop().resolve()
        if path in found or not path.is_file():
            continue
        found[path] = hashlib.sha256(path.read_bytes()).hexdigest()
        if visual and path.suffix in (".glb", ".png"):
            pending.append(Path(str(path) + ".import"))
            pending.extend((PROJECT / ".godot/imported").glob(path.name + "-*"))
        if visual and path.suffix == ".import":
            pending.extend(PROJECT / resource[6:] for resource in re.findall(r'res://[^"\s]+', path.read_text()))
        if path.suffix in (".gd", ".gdshader", ".gdshaderinc"):
            for resource in re.findall(r'res://[^"\'\s)]+\.(?:gdshaderinc|gdshader|gd|json)', path.read_text()):
                pending.append(PROJECT / resource[6:])
    return {str(path.relative_to(ROOT)): digest for path, digest in sorted(found.items())}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("checks", nargs="*", choices=list(ENTRIES))
parser.add_argument("--capture", type=Path, help="Explicit recorded no-grant route checkpoint for recovery")
parser.add_argument("--timeout", type=float, default=55, help="Wall-clock bound per check; does not change logical route limits")
options = parser.parse_args()
if not 0 < options.timeout <= 300:
    parser.error("--timeout must be positive and at most 300 seconds")
selected = options.checks or ["residents", "gameplay", "regression", "encounters"]
CAPTURE_ENTRIES = {"recovery", "material", "cursor_timers", "radio_stability", "delivery_recovery", "rural_completion", "radio_capability", "extension", "extension_presentation"}
if CAPTURE_ENTRIES.intersection(selected) and (options.capture is None or not options.capture.is_file()):
    parser.error("recovery/material/cursor_timers requires --capture pointing to a recorded real route checkpoint")
out = ROOT / "work/r3-3-eee" / datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
out.mkdir(parents=True)
results = []
for name in selected:
    entry = ENTRIES[name]
    target = out / name
    target.mkdir()
    report = target / "results.json"
    # The pre-existing resident script accepts a filename; gameplay accepts a directory.
    arg = str(report if name == "residents" else target)
    before = sources(entry)
    inputs = [options.capture.resolve()] if name in CAPTURE_ENTRIES else []
    if name == "extension_presentation":
        inputs.extend(Path(phase["path"]) for phase in json.loads(options.capture.read_text())["phase_captures"])
    input_before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    exception, code = None, None
    started = time.monotonic()
    with (target / "run.log").open("w") as log:
        try:
            command = [str(GODOT), "--headless", "--path", str(PROJECT), "--script", entry, "--", arg]
            if name in CAPTURE_ENTRIES:
                command.append(str(options.capture.resolve()))
            with subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT) as run:
                while True:
                    try:
                        code = run.wait(timeout=min(0.5, max(0.01, options.timeout - (time.monotonic() - started))))
                        break
                    except subprocess.TimeoutExpired:
                        # A compile failure can leave a SceneTree with no run()
                        # alive forever. Stop only this test's own child, retain
                        # its exact diagnostics, and never wait out a route cap.
                        diagnostics = (target / "run.log").read_text()
                        if "SCRIPT ERROR: Parse Error:" in diagnostics or "SCRIPT ERROR: Compile Error:" in diagnostics:
                            exception = "Godot script compilation failed; isolated child terminated"
                        elif time.monotonic() - started >= options.timeout:
                            exception = "Isolated check exceeded wall-clock limit"
                        if exception:
                            run.terminate()
                            try:
                                code = run.wait(timeout=3)
                            except subprocess.TimeoutExpired:
                                run.kill()
                                code = run.wait(timeout=3)
                            break
        except (subprocess.TimeoutExpired, OSError) as error:
            exception = str(error)
    after = sources(entry)
    text = (target / "run.log").read_text()
    try:
        data = json.loads(report.read_text())
    except (ValueError, OSError) as error:
        data = {}; exception = exception or str(error)
    errors = bool(re.search(r"SCRIPT ERROR:|^ERROR:", text, re.M))
    warnings = bool(re.search(r"^WARNING:", text, re.M))
    result = {"entry": entry, "exit": code, "exception": exception, "failed": data.get("failed"), "checks": len(data.get("checks", [])), "errors": errors, "warnings": warnings, "source_stable": before == after, "before_sha256": before, "after_sha256": after, "report": str(report.relative_to(ROOT))}
    changed = sorted(path for path in before.keys() | after.keys() if before.get(path) != after.get(path))
    result["relevant_source_stable"] = not any(relevant(path, name == "extension_presentation") for path in changed)
    result["source_drift"] = changed
    result["unrelated_source_drift"] = [path for path in changed if not relevant(path, name == "extension_presentation")]
    result["input_before_sha256"] = input_before
    result["input_after_sha256"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    result["input_stable"] = result["input_before_sha256"] == result["input_after_sha256"]
    result["ok"] = code == 0 and exception is None and data.get("failed") == 0 and not errors and not warnings and result["relevant_source_stable"] and result["input_stable"]
    result["elapsed_seconds"] = time.monotonic() - started
    result["timeout_seconds"] = options.timeout
    if name in CAPTURE_ENTRIES:
        result["capture"] = str(options.capture.resolve())
        result["capture_sha256"] = hashlib.sha256(options.capture.read_bytes()).hexdigest()
    results.append(result)
    print(json.dumps({k: result[k] for k in ("entry", "ok", "checks", "failed", "exit", "exception", "source_stable", "relevant_source_stable", "source_drift", "report")}), flush=True)
(out / "manifest.json").write_text(json.dumps({"scope": "E isolated domain commands/explicit fixtures; no formal app/input/VA/performance acceptance", "results": results, "ok": all(r["ok"] for r in results)}, indent=2) + "\n")
print(str(out / "manifest.json"))
sys.exit(0 if all(r["ok"] for r in results) else 1)
