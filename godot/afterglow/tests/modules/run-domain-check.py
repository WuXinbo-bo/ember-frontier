"""Bounded BBB headless evidence; never imports/exports or changes save slots."""
from pathlib import Path
import datetime, hashlib, json, os, re, subprocess, sys, time, zipfile

ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "godot/afterglow"
ENTRY, NAME = sys.argv[1:3]
OUT = ROOT / "work/r3-4-bbb" / NAME
OUT.mkdir(parents=True, exist_ok=False)

def sources():
    pending, seen = [PROJECT / ENTRY], set()
    while pending:
        path = pending.pop().resolve()
        if path in seen or not path.is_file():
            continue
        seen.add(path)
        if path.suffix in (".gd", ".gdshader", ".json"):
            for ref in re.findall(r'res://[^"\'\s)]+\.(?:gdshader|gd|json|png)', path.read_text()):
                pending.append(PROJECT / ref.removeprefix("res://"))
    # Module catalog and content paths can be constructed by native helpers.
    seen.update(PROJECT.glob("data/modules/*.json"))
    seen.add(Path(__file__).resolve())
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)}

before = sources()
with zipfile.ZipFile(OUT / "source-before.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    for path in before:
        archive.write(ROOT / path, path)
command = [str(ROOT / "work/tooling/godot/Godot.app/Contents/MacOS/Godot"),
           "--headless", "--path", str(PROJECT), "--script", "res://" + ENTRY]
if len(sys.argv) > 3:
    command += ["--", *sys.argv[3:]]
started = time.monotonic()
timeout_seconds = min(300, max(15, float(os.environ.get("BBB_DOMAIN_TIMEOUT_SECONDS", "115"))))
error, code = None, None
with (OUT / "engine.log").open("w") as output:
    try:
        code = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=timeout_seconds).returncode
    except (subprocess.TimeoutExpired, OSError) as exc:
        error = str(exc)
raw = (OUT / "engine.log").read_text()
report = {}
for line in raw.splitlines():
    if line.startswith('{"checks"') or line.startswith('{"ok"'):
        try:
            candidate = json.loads(line)
            if "checks" in candidate:
                report = candidate
        except json.JSONDecodeError:
            pass
after = sources()
issues = re.findall(r"^(?:ERROR|SCRIPT ERROR|WARNING):.*", raw, re.M)
failed = sum(not row["ok"] for row in report.get("checks", []))
result = {"created_at": datetime.datetime.now().astimezone().isoformat(), "command": command, "timeout_seconds": timeout_seconds,
          "exit_code": code, "error": error, "elapsed_seconds": time.monotonic() - started,
          "checks": len(report.get("checks", [])), "failed": failed, "diagnostics": issues,
          "before": before, "after": after, "source_stable": before == after,
          "scope": "BBB bounded real source regression; no package, OS, VA or performance qualification"}
result["ok"] = code == 0 and error is None and bool(report) and failed == 0 and not issues and before == after
(OUT / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
(OUT / "manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({k: result[k] for k in ("ok", "exit_code", "checks", "failed", "diagnostics", "source_stable", "elapsed_seconds")}))
if not result["ok"]:
    print(json.dumps([row for row in report.get("checks", []) if not row["ok"]], ensure_ascii=False))
sys.exit(0 if result["ok"] else 1)
