"""One no-grant fresh route against immutable candidate10 production PCK."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "godot/afterglow"
GODOT = ROOT / "work/tooling/godot/Godot.app/Contents/MacOS/Godot"
PCK = PROJECT / "builds/candidates/Afterglow-build10.app/Contents/Resources/末日余晖.pck"
FROZEN = ROOT / "work/r3-3/native-build-10-frozen-source.zip"
ENTRY = PROJECT / "tests/gameplay/fresh_natural_route.gd"
OUT = ROOT / "work/r3-3-eee" / datetime.datetime.now().strftime("fresh-pck-%Y%m%d-%H%M%S-%f")
OUT.mkdir()

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def dump(p, data):
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")

assert sha(PCK) == "9e0a97fc75ae5bde4aa83df8a5ab5498787f99ccf3670021f83c6e6f0bd55d7f"
assert sha(FROZEN) == "555057ffc769c70c1e793b8b5c923a59d66610fe252c2b9fd65248be691146fb"
harness = OUT / "external-test-harness"
harness.mkdir()
with zipfile.ZipFile(FROZEN) as archive:
    for name in archive.namelist():
        relative = Path(name)
        if not relative.parts or relative.parts[0] != "tests" or relative.is_absolute() or ".." in relative.parts:
            continue
        data = archive.read(name)
        target = harness / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.suffix == ".gd":
            data = data.decode().replace("res://tests/", str(harness / "tests") + "/").encode()
        target.write_bytes(data)
entry = harness / "tests/gameplay/fresh_natural_route.gd"
entry.write_text(ENTRY.read_text().replace("res://tests/", str(harness / "tests") + "/"))
assert not (harness / "scripts").exists() and not (harness / "data").exists()
inputs = [PCK, FROZEN, ENTRY, Path(__file__).resolve(), *sorted(harness.rglob("*.gd"))]
before = {str(p): sha(p) for p in inputs}
dump(OUT / "input-before.json", before)
result_dir = OUT / "fresh"
result_dir.mkdir()
command = [str(GODOT), "--headless", "--log-file", str(OUT / "engine.log"),
           "--path", str(harness), "--main-pack", str(PCK), "--script", str(entry), "--", str(result_dir)]
dump(OUT / "command.json", command)
exception = None
started = time.monotonic()
with (OUT / "run.log").open("w") as log:
    with subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT) as process:
        while True:
            try:
                code = process.wait(timeout=0.5)
                break
            except subprocess.TimeoutExpired:
                output = (OUT / "run.log").read_text()
                if "SCRIPT ERROR: Parse Error:" in output or "SCRIPT ERROR: Compile Error:" in output:
                    exception = "External test compilation failed"
                elif time.monotonic() - started > 300:
                    exception = "Fresh route exceeded 300 seconds; no simulation budget disabled"
                if exception:
                    process.terminate()
                    try:
                        code = process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        process.kill(); code = process.wait(timeout=3)
                    break
after = {str(p): sha(p) for p in inputs}
dump(OUT / "input-after.json", after)
text = (OUT / "run.log").read_text()
try:
    data = json.loads((result_dir / "results.json").read_text())
except (OSError, ValueError):
    data = {}
errors = bool(re.search(r"SCRIPT ERROR:|^ERROR:", text, re.M))
warnings = bool(re.search(r"^WARNING:", text, re.M))
manifest = {
    "scope": "actual candidate10 PCK fresh base opening, original finite resources; external test only; no UI/OS/VA/performance qualification",
    "pck": str(PCK), "pck_sha256": before[str(PCK)], "frozen_source": str(FROZEN), "frozen_sha256": before[str(FROZEN)],
    "production_only_from_PCK": True, "historical_capture_input": False, "playtest_profile_applied": False,
    "command": command, "exit": code, "exception": exception, "errors": errors, "warnings": warnings,
    "checks": len(data.get("checks", [])), "failed": data.get("failed"),
    "input_stable": before == after, "input_drift": [p for p in before if before[p] != after[p]],
    "elapsed_seconds": time.monotonic() - started,
    "functional_ok": code == 0 and not exception and data.get("failed") == 0 and not errors and not warnings,
}
manifest["ok"] = manifest["functional_ok"] and manifest["input_stable"]
dump(OUT / "manifest.json", manifest)
print(json.dumps({k: v for k, v in manifest.items() if k not in ("command",)}, ensure_ascii=False))
print(OUT / "manifest.json")
raise SystemExit(0 if manifest["ok"] else 1)
