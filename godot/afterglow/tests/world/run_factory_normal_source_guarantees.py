"""Run only CCC's source guarantees against immutable actual18 production."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil,subprocess,time,zipfile

ROOT=Path(__file__).resolve().parents[4]
PROJECT=ROOT/'godot/afterglow'
ENTRY=PROJECT/'tests/world/factory_normal_source_guarantees.gd'
ADOPTION=ROOT/'work/r3-4/build18-adoption.json'
GODOT=ROOT/'work/tooling/godot/Godot.app/Contents/MacOS/Godot'
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def dump(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def production():
    return {str(p.relative_to(ROOT)):sha(p) for base in ('scripts','data') for p in sorted((PROJECT/base).rglob('*')) if p.is_file() and p.suffix in ('.gd','.json','.gdshader','.gdshaderinc')}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out',type=Path)
    parser.add_argument('--only-seed',type=int,choices=[713,2026,17,999])
    parser.add_argument('--timeout',type=float,default=260)
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    adoption=json.loads(ADOPTION.read_text());pack_dir=Path(adoption['verification']['candidate_app'])/'Contents/Resources';packs=list(pack_dir.glob('*.pck'))
    assert len(packs)==1
    pack=packs[0];frozen=ROOT/adoption['frozen_zip']
    assert sha(pack)==adoption['verification']['pck_sha256'] and sha(frozen)==adoption['frozen_zip_sha256']
    seeds=[args.only_seed] if args.only_seed is not None else [713,2026,17,999]
    input_path=out/'source-guarantees-input.json'
    dump(input_path,{'schema':'ccc-normal-source-guarantees-v1','profile':'normal','content_version':4,'story_clue_version':1,'seeds':seeds,'max_ticks_per_seed':12000,'max_wall_msec':240000,'safety':'only normal Assembly.generate/prepare + Native; actual commands/fixed clock; never edit captures, grant or move an actor directly'})
    harness=out/'frozen-harness';external=harness/'tests/world'/ENTRY.name
    external.parent.mkdir(parents=True);shutil.copyfile(ENTRY,external);shutil.copyfile(__file__,out/'runner-executed.py')
    assert not any((harness/p).exists() for p in ['project.godot','scripts','data','scenes'])
    all_members={};content={}
    with zipfile.ZipFile(frozen) as z:
        for name in z.namelist():
            if name.endswith('/'):continue
            raw=z.read(name);all_members[name]=hashlib.sha256(raw).hexdigest()
            if name.endswith(('.gd','.json','.tscn','.tres','.gdshader','.gdshaderinc')):content[name]=raw.decode('utf-8')
    # Complete frozen archive table covers dynamic paths/imported resources;
    # this extra graph records recursive static res:// dependencies explicitly.
    closure={};missing=[];queue=re.findall(r'res://[^\"\s\)\]]+',external.read_text())
    while queue:
        resource=queue.pop().rstrip("',}");name=resource.removeprefix('res://')
        if name in closure:continue
        if name not in all_members:missing.append(resource);continue
        closure[name]=all_members[name]
        if name in content:queue.extend(re.findall(r'res://[^\"\s\)\]]+',content[name]))
    dump(out/'frozen-archive-all-members.json',all_members)
    dump(out/'recursive-static-resources.json',{'resources':closure,'unresolved_or_dynamic_hints':sorted(set(missing)),'complete_fallback':'frozen-archive-all-members.json plus immutable PCK SHA; source graph alone is not runtime proof'})
    # Shipping exports exclude tests. Reuse their exact archived bytes as
    # test-only overlay; production/data still come solely from actual PCK.
    old_test_inputs=[]
    with zipfile.ZipFile(frozen) as archive:
        for name in sorted(closure):
            if name.startswith('tests/') and name.endswith('.gd'):
                path=harness/name;path.parent.mkdir(parents=True,exist_ok=True)
                path.write_bytes(archive.read(name));assert sha(path)==all_members[name]
                old_test_inputs.append(path)
    dump(out/'test-overlay-members.json',{str(p.relative_to(harness)):sha(p) for p in [external]+old_test_inputs})
    deps=[pack,frozen,ADOPTION,GODOT,Path(__file__).resolve(),external,input_path]+old_test_inputs
    before={str(p):sha(p) for p in deps};source_before=production()
    dump(out/'dependencies-before.json',before);dump(out/'source-before.json',source_before)
    command=[str(GODOT),'--headless','--log-file',str(out/'engine.log'),'--path',str(harness),'--main-pack',str(pack),'--script',str(external),'--',str(out/'results.json'),str(input_path)]
    dump(out/'started.json',{'created_at':datetime.datetime.now().astimezone().isoformat(),'command':command,'seeds':seeds,'scope':'new source test only; A1800 runner/normal53/direct input not touched'})
    began=time.monotonic();error=None;exit_code=None
    with (out/'stdout.log').open('w') as log:
        try:exit_code=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout).returncode
        except (OSError,subprocess.TimeoutExpired) as exc:error=str(exc)
    after={str(p):sha(p) for p in deps};source_after=production()
    dump(out/'dependencies-after.json',after);dump(out/'source-after.json',source_after)
    result=json.loads((out/'results.json').read_text()) if (out/'results.json').is_file() else {}
    diagnostics=re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING):.*',(out/'stdout.log').read_text(),re.M)
    functional=exit_code==0 and error is None and not result.get('partial',True) and result.get('failed')==0 and len(result.get('seed_rows',[]))==len(seeds) and all(row.get('finished',False) for row in result.get('seed_rows',[]))
    manifest={'created_at':datetime.datetime.now().astimezone().isoformat(),'scope':'actual18 normal C4/story1 multi-seed source commands/B routes/actual body carry/data restoration; not OS/VA/RSS/performance/long-time/full economy or infinite supply','entry':str(ENTRY.relative_to(PROJECT)),'entry_sha256':sha(external),'runner_sha256':sha(__file__),'command':command,'seeds':seeds,'exit_code':exit_code,'error':error,'elapsed_seconds':time.monotonic()-began,'checks':len(result.get('checks',[])),'failed':result.get('failed'),'diagnostics':diagnostics,'functional_ok':functional,'dependency_stable':before==after,'source_stable':source_before==source_after,'workspace_delta':[p for p in sorted(source_before.keys()|source_after.keys()) if source_before.get(p)!=source_after.get(p)],'pack_sha256':sha(pack),'frozen_zip_sha256':sha(frozen),'frozen_members':len(all_members),'recursive_static_resources':len(closure),'input_sha256':sha(input_path),'results_sha256':sha(out/'results.json') if (out/'results.json').is_file() else None}
    manifest['qualified']=functional and before==after and not diagnostics
    dump(out/'manifest.json',manifest);print(json.dumps(manifest,ensure_ascii=False));return 0 if manifest['qualified'] else 1

if __name__=='__main__':raise SystemExit(main())
