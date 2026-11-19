extends RefCounted
const SupplyObservation=preload("res://scripts/planning/zone_supply_observation.gd")
const Supply=preload("res://scripts/planning/zone_work_supply.gd")
const Data=preload("res://scripts/world/world_data.gd")
const G=preload("res://scripts/buildings/building_geometry.gd")
## Supply's original read-only host API, scoped to ONE synchronous candidate
## query. Residency cannot change inside this call (no await/commit). Never use
## this facade in admission, work execution, handoff or a subsequent query.
var context:Dictionary
var _host:RefCounted
var _detailed:Dictionary={}
var _production:RefCounted
var _supply:Dictionary={}
func _init(host:RefCounted,tx:RefCounted=null)->void:
	_host=host;context=host.context
	if tx!=null and host.domain("production")!=null:_production=SupplyObservation.new(host.domain("production"),tx)
func domain(name:String)->Variant:return _production if name=="production" and _production!=null else _host.domain(name)
func supply_candidates(tx:RefCounted,a:Dictionary,zone:Dictionary,job:Dictionary,requirements:Dictionary)->Array:
	if _production==null:return []
	# Job identity changes the offer IDs, not source availability. Share only
	# exactly equal prerequisite sets at this immutable observation. An actual
	# held/reserved exclusion keeps its own key; command admission is uncached.
	var basis:Array=[a.id,zone.id,zone.revision,zone.get("policy",{}),requirements.get("cost",{}),requirements.get("reusable",{}),requirements.get("tool_quality",{}),_production.exclusion_key(str(job.get("work_id","")))]
	if zone.has("region_ids"):basis.append(G.location(job.location).regionId)
	if not Data.json_value(basis):return Supply.compute_candidates(self,tx,a,zone,job,requirements)
	var key:String=JSON.stringify(basis,"",true,true)
	if not _supply.has(key):_supply[key]=Supply.compute_candidates(self,tx,a,zone,job,requirements)
	var rows:Array=_supply[key].duplicate(true)
	for row:Dictionary in rows:
		var offer_basis:Array=[str(a.id),str(zone.id),int(zone.revision),str(job.id),str(row.source_id)]
		row.id="zone-supply:"+JSON.stringify(offer_basis).sha256_text().substr(0,32)
		row.work_candidate_id="zonework:"+str(zone.id)+":"+str(job.id)
		row.job_id=str(job.id)
	return rows
func detailed(at:Dictionary)->bool:
	var region:String=str(at.get("regionId",""))
	if not _detailed.has(region):_detailed[region]=_host.detailed(at)
	return _detailed[region]
