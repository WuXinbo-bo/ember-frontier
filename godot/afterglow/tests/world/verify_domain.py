"""Bounded CCC tests with exact source provenance; Godot exit 0 alone is insufficient."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import subprocess
import sys

REPO = Path(__file__).resolve().parents[4]
PROJECT = REPO / "godot/afterglow"
GODOT = REPO / "work/tooling/godot/Godot.app/Contents/MacOS/Godot"
OUT = REPO / "outputs/r3.3-ccc-evidence"

def hashes(entry):
    pending, seen = [PROJECT / entry], set()
    while pending:
        path = pending.pop().resolve()
        if path in seen or not path.exists():
            continue
        seen.add(path)
        if path.suffix in (".gd", ".gdshader", ".gdshaderinc", ".json"):
            for resource in re.findall(r'res://[^"\'\s)]+\.(?:gdshaderinc|gdshader|gd|json|glb|png)', path.read_text()):
                pending.append(PROJECT / resource.removeprefix("res://"))
    return {str(p.relative_to(REPO)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(seen)}

entries = ["run_world_tests.gd", "run_domain_integration.gd"]
if "--storage" in sys.argv:
    entries.append("run_storage_integration.gd")
if "--only=storage" in sys.argv:
    entries = ["run_storage_integration.gd"]
if "--only=section8" in sys.argv:
    entries = ["section8_terrain_input.gd", "section8_environment.gd"]
if "--only=environment" in sys.argv:
    entries = ["section8_environment.gd"]
if "--only=environment-cost" in sys.argv:
    entries = ["profile_environment_followup.gd"]
if "--only=shoulder-cost" in sys.argv:
    entries = ["profile_environment_shoulder.gd"]
if "--only=profile" in sys.argv:
    entries = ["section8_profile.gd"]
if "--only=reservation" in sys.argv:
    entries = ["section8_reservations.gd"]
if "--only=integration" in sys.argv:
    entries = ["run_domain_integration.gd"]
if "--only=world" in sys.argv:
    entries = ["run_world_tests.gd"]
if "--only=settlement" in sys.argv:
    entries = ["settlement_generation.gd"]
if "--only=settlement-joint" in sys.argv:
    entries = ["settlement_joint.gd"]
if "--only=settlement-cost" in sys.argv:
    entries = ["settlement_sampling_cost.gd"]
if "--only=settlement-validation" in sys.argv:
    entries = ["settlement_validation_cost.gd"]
if "--only=terrain-streaming" in sys.argv:
    entries = ["terrain_streaming.gd"]
if "--only=ground-detail" in sys.argv:
    entries = ["ground_detail_sampling.gd"]
if "--only=landscape" in sys.argv:
    entries = ["landscape_generation.gd"]
if "--only=ecology-incremental" in sys.argv:
    entries = ["ecology_incremental.gd"]
if "--only=quality-binding" in sys.argv:
    entries = ["quality_binding.gd"]
if "--only=landscape-routes" in sys.argv:
    entries = ["landscape_routes.gd"]
if "--only=terrace" in sys.argv:
    entries = ["terrace_diagnostic.gd"]
if "--only=landscape-current" in sys.argv:
    entries = ["landscape_generation.gd", "ecology_incremental.gd", "quality_binding.gd", "landscape_routes.gd", "terrace_diagnostic.gd"]
if "--only=generation-contract" in sys.argv:
    entries = ["generation_contract_compat.gd"]
if "--only=housing-generation" in sys.argv:
    entries = ["generation_contract_compat.gd", "housing_generation.gd"]
if "--only=housing-content" in sys.argv:
    entries = ["housing_generation.gd"]
if "--only=local-apron" in sys.argv:
    entries = ["local_apron.gd"]
if "--only=local-apron-cost" in sys.argv:
    entries = ["local_apron_cost.gd"]
if "--only=continuous-outdoor" in sys.argv:
    entries = ["continuous_outdoor.gd"]
if "--only=terrain-input" in sys.argv:
    entries = ["section8_terrain_input.gd"]
if "--only=terrain-contact" in sys.argv:
    entries = ["terrain_surface_contact.gd"]
if "--only=seed-range" in sys.argv:
    entries = ["seed_range_assembly.gd"]
results = []
for name in entries:
    entry = "tests/world/" + name
    prefix = "native-verified-" + name.removesuffix(".gd")
    target, log = OUT / (prefix + ".json"), OUT / (prefix + ".log")
    before = hashes(entry)
    # A stale previous JSON file must never qualify a failed current script.
    suffix = ".previous-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S%f")
    for previous in [target, log, target.with_name(target.name + ".plans.json"), target.with_name(target.name + ".navigation.json")]:
        if previous.exists():
            previous.rename(previous.with_name(previous.name + suffix))
    exit_code, exception = None, None
    with log.open("w") as f:
        try:
            run = subprocess.run([str(GODOT), "--headless", "--path", str(PROJECT), "--script", entry, "--", str(target)], stdout=f, stderr=subprocess.STDOUT, timeout=55)
            exit_code = run.returncode
        except (subprocess.TimeoutExpired, OSError) as error:
            exception = str(error)
    after = hashes(entry)
    try:
        outcome = json.loads(target.read_text()) if target.exists() else {"failed": None}
    except (OSError, ValueError) as error:
        outcome, exception = {"failed":None}, str(error)
    text = log.read_text()
    stable = before == after
    ok = exception is None and exit_code == 0 and outcome.get("failed") == 0 and not re.search(r"SCRIPT ERROR:|^ERROR:", text, re.M) and stable
    results.append({"entry":entry,"ok":ok,"exit":exit_code,"exception":exception,"source_stable":stable,"before_sha256":before,"after_sha256":after,"report":str(target.relative_to(REPO)),"log":str(log.relative_to(REPO)),"checks":len(outcome.get("checks",[])),"failed":outcome.get("failed")})
manifest = {"created_at":datetime.datetime.now().astimezone().isoformat(),"scope":"CCC bounded headless native domain checks; no formal preview or app export","results":results,"ok":all(r["ok"] for r in results)}
manifest_path = OUT / ("settlement-cost-manifest.json" if "--only=settlement-cost" in sys.argv else "settlement-joint-manifest.json" if "--only=settlement-joint" in sys.argv else "settlement-generation-manifest.json" if "--only=settlement" in sys.argv else "shoulder-cost-manifest.json" if "--only=shoulder-cost" in sys.argv else "environment-cost-manifest.json" if "--only=environment-cost" in sys.argv else "environment-followup-manifest.json" if "--only=environment" in sys.argv else "world-regression-manifest.json" if "--only=world" in sys.argv else "section8-reservation-manifest.json" if "--only=reservation" in sys.argv else "domain-integration-manifest.json" if "--only=integration" in sys.argv else "section8-profile-manifest.json" if "--only=profile" in sys.argv else "section8-verified-manifest.json" if "--only=section8" in sys.argv else "native-verified-manifest.json")
if "--only=settlement-validation" in sys.argv:
    manifest_path = OUT / "settlement-validation-manifest.json"
if "--only=terrain-streaming" in sys.argv:
    manifest_path = OUT / "terrain-streaming-manifest.json"
if "--only=ground-detail" in sys.argv:
    manifest_path = OUT / "ground-detail-manifest.json"
if "--only=landscape" in sys.argv:
    manifest_path = OUT / "landscape-generation-manifest.json"
if "--only=ecology-incremental" in sys.argv:
    manifest_path = OUT / "ecology-incremental-manifest.json"
if "--only=quality-binding" in sys.argv:
    manifest_path = OUT / "quality-binding-manifest.json"
if "--only=landscape-routes" in sys.argv:
    manifest_path = OUT / "landscape-routes-manifest.json"
if "--only=terrace" in sys.argv:
    manifest_path = OUT / "terrace-capture-manifest.json"
if "--only=landscape-current" in sys.argv:
    manifest_path = OUT / "landscape-current-manifest.json"
if "--only=generation-contract" in sys.argv:
    manifest_path = OUT / "generation-contract-manifest.json"
if "--only=housing-generation" in sys.argv:
    manifest_path = OUT / "housing-generation-manifest.json"
if "--only=housing-content" in sys.argv:
    manifest_path = OUT / "housing-content-manifest.json"
if "--only=local-apron" in sys.argv:
    manifest_path = OUT / "local-apron-manifest.json"
if "--only=local-apron-cost" in sys.argv:
    manifest_path = OUT / "local-apron-cost-manifest.json"
if "--only=continuous-outdoor" in sys.argv:
    manifest_path = OUT / "continuous-outdoor-manifest.json"
if "--only=terrain-input" in sys.argv:
    manifest_path = OUT / "terrain-input-manifest.json"
if "--only=terrain-contact" in sys.argv:
    manifest_path = OUT / "terrain-contact-manifest.json"
if "--only=seed-range" in sys.argv:
    manifest_path = OUT / "seed-range-manifest.json"
if manifest_path.exists():
    manifest_path.rename(manifest_path.with_name(manifest_path.name + ".previous-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S%f")))
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"ok":manifest["ok"],"results":[{k:r[k] for k in ["entry","ok","source_stable","checks","failed"]} for r in results]},ensure_ascii=False))
sys.exit(0 if manifest["ok"] else 1)
