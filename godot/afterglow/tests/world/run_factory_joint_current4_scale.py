"""One C test on A's immutable build18 PCK; same test-only harness protocol.

Reuse the established A --main-pack/external-tests approach; never copy a
production resource or project.godot into the external harness.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil,subprocess,time,zipfile

ROOT=Path(__file__).resolve().parents[4]
PROJECT=ROOT/'godot/afterglow'
ENTRY=PROJECT/'tests/world/factory_joint_current4_scale.gd'
GODOT=ROOT/'work/tooling/godot/Godot.app/Contents/MacOS/Godot'
ADOPTION=ROOT/'work/r3-4/build18-adoption.json'
NORMAL=ROOT/'work/r3-4/build18-pck-core-normal-v1/factory-economy/actual-normal-economy.native.json'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def dump(p,value):p.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')
def production():
    return {str(p.relative_to(ROOT)):sha(p) for base in ('scripts','data') for p in sorted((PROJECT/base).rglob('*')) if p.is_file() and p.suffix in ('.gd','.json','.gdshader','.gdshaderinc')}
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('out',type=Path)
    parser.add_argument('--target',type=int,choices=[4,8,12,24],default=24)
    parser.add_argument('--timeout',type=float,default=150)
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    adoption=json.loads(ADOPTION.read_text())
    app=Path(adoption['verification']['candidate_app']);packs=list((app/'Contents/Resources').glob('*.pck'))
    if len(packs)!=1:raise ValueError('one exact candidate18 PCK required')
    pack=packs[0];frozen=ROOT/adoption['frozen_zip']
    if sha(pack)!=adoption['verification']['pck_sha256'] or sha(frozen)!=adoption['frozen_zip_sha256']:raise ValueError('adoption source identity mismatch')
    if sha(NORMAL)!='222ed3d81b6ae914c0fdf0ce266aabf07600f8f51c08b96ee5aa27f98c7effb0':raise ValueError('explicit build18 normal53 identity required')
    harness=out/'frozen-harness';external=harness/'tests/world/factory_joint_current4_scale.gd'
    external.parent.mkdir(parents=True);shutil.copyfile(ENTRY,external)
    shutil.copyfile(__file__,out/'runner-executed.py')
    if any((harness/p).exists() for p in ('scripts','data','scenes','themes','project.godot')):raise ValueError('external tests only')
    frozen_members={}
    with zipfile.ZipFile(frozen) as archive:
        for name in archive.namelist():
            if not name.endswith('/'):frozen_members[name]=hashlib.sha256(archive.read(name)).hexdigest()
    deps=[pack,frozen,ADOPTION,NORMAL,GODOT,Path(__file__).resolve(),external]
    before={str(p):sha(p) for p in deps};source_before=production()
    dump(out/'dependencies-before.json',before)
    dump(out/'source-before.json',source_before)
    dump(out/'frozen-archive-all-members.json',frozen_members)
    command=[str(GODOT),'--headless','--log-file',str(out/'engine.log'),'--path',str(harness),'--main-pack',str(pack),'--script',str(external),'--',str(out/'results.json'),str(NORMAL),str(args.target)]
    dump(out/'started.json',{'created_at':datetime.datetime.now().astimezone().isoformat(),'command':command,'target':args.target,'source_scope':'actual build18 immutable production; only new external test, no application export'})
    start=time.monotonic();error=None;exit_code=None
    with (out/'stdout.log').open('w') as log:
        try:exit_code=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=args.timeout).returncode
        except (OSError,subprocess.TimeoutExpired) as e:error=str(e)
    after={str(p):sha(p) for p in deps};source_after=production()
    dump(out/'dependencies-after.json',after);dump(out/'source-after.json',source_after)
    diagnostics=re.findall(r'^(?:SCRIPT ERROR|ERROR|WARNING):.*',(out/'stdout.log').read_text(),re.M)
    result=json.loads((out/'results.json').read_text()) if (out/'results.json').is_file() else {}
    dependency_stable=before==after
    functional=exit_code==0 and not error and not result.get('partial',True) and bool(result.get('checks')) and result.get('failed')==0 and result.get('actual_regions')==args.target
    manifest={'created_at':datetime.datetime.now().astimezone().isoformat(),'scope':'actual build18 PCK/headless Native joint data+modules+original residents+storage only; not OS/VA/RSS/fixed performance/30min/60min or full G4/G5','entry':'tests/world/factory_joint_current4_scale.gd','entry_sha256':sha(external),'runner_sha256':sha(__file__),'command':command,'exit_code':exit_code,'error':error,'elapsed_seconds':time.monotonic()-start,'target':args.target,'actual_regions':result.get('actual_regions'),'checks':len(result.get('checks',[])),'failed':result.get('failed'),'diagnostics':diagnostics,'functional_ok':functional,'dependency_stable':dependency_stable,'source_stable':source_before==source_after,'workspace_delta':[p for p in sorted(source_before.keys()|source_after.keys()) if source_before.get(p)!=source_after.get(p)],'pack_sha256':after[str(pack)],'frozen_zip_sha256':after[str(frozen)],'normal_input_sha256':after[str(NORMAL)],'frozen_member_count':len(frozen_members),'results_sha256':sha(out/'results.json') if (out/'results.json').is_file() else None}
    manifest['qualified']=functional and dependency_stable and not diagnostics
    dump(out/'manifest.json',manifest)
    print(json.dumps(manifest,ensure_ascii=False))
    return 0 if manifest['qualified'] else 1
if __name__=='__main__':raise SystemExit(main())
