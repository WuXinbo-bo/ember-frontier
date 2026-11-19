extends SceneTree
## Actual catalog display coverage; no world mutations or substituted recipes.
const Identity = preload("res://scripts/ui/building_identity.gd")
const F = preload("res://scripts/ui/factory_projection.gd")
const Catalog = preload("res://scripts/ui/factory_catalog.gd")
const Book = preload("res://scripts/ui/factory_handbook.gd")
var checks: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"ok":ok,"detail":detail})
	if not ok: print("FAIL "+label+" "+str(detail))

func run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules/catalog_v1.json"))
	var mechanisms: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules/mechanisms_v2.json"))
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/modules/opening_v15.json"))
	var definitions: Array = source.definitions + mechanisms.definitions + opening.definitions
	var original: String = JSON.stringify(definitions)
	var missing: Array = []
	for definition: Dictionary in definitions:
		if Identity.family(definition).is_empty() or Identity.name(definition).is_empty() or Identity.purpose(definition).is_empty(): missing.append(definition.id)
	check("every real legacy architecture mechanism and opening definition has a simple identity",definitions.size()==86 and missing.is_empty(),missing)
	check("opening multi-purpose work shed stays a work shed",Identity.name(opening.definitions[0])=="工作棚" and Identity.family(opening.definitions[0])=="workshop")
	var expected := {"home":"住宅", "warehouse":"仓库", "sawmill":"锯木厂", "artisan":"工匠坊", "repair":"修理铺", "guard":"岗亭"}
	for key: String in expected:
		check("mechanism family has plain label "+key,Identity.name({"mechanism":{"family":key,"tier":2}})==expected[key])
	check("kitchen and canteen use the real tier",Identity.name({"mechanism":{"family":"canteen","tier":1.0}})=="厨房" and Identity.name({"mechanism":{"family":"canteen","tier":2.0}})=="食堂")
	check("water purification name requires published processing recipes",Identity.name({"mechanism":{"family":"water","recipes":["existing"]}})=="净水站" and Identity.name({"architecture":{"family":"water","tier":"low"}})=="取水站")
	check("generic machine does not claim sawmill capability",Identity.family({"generation_role":"machine"})=="machine" and Identity.name({"generation_role":"machine"})=="加工站")
	check("unknown definition keeps provided label without invented family",Identity.family({"id":"future"}).is_empty() and Identity.name({"id":"future"},"未来设施")=="未来设施")
	check("explicit custom building names survive display normalization",Identity.instance_name({"generation_role":"home"},{"custom_name":"我们的家"})=="我们的家" and Identity.instance_name({"generation_role":"home"},{"name":"山边小屋","name_is_custom":true})=="山边小屋")
	var home: Dictionary = definitions.filter(func(row:Dictionary)->bool:return row.id=="r35.module.village_home")[0]
	var data: Dictionary = {"modules":{"available":true,"definitions":[home],"instances":[{"id":"home-instance","definition_id":home.id,"name":home.name,"stock_refs":{"supplies":"supply-stock"},"stock_visibility":{"supplies":false}}],"build_definition_ids":[home.id]}}
	var before: String = JSON.stringify(data)
	var public_definition: Dictionary = F.definition(data,str(home.id))
	var public_instance: Dictionary = F.instance(data,"home-instance")
	check("selected definition and instance expose the same simple label",public_definition.name=="住宅" and public_instance.name=="住宅" and not public_instance.use_hint.is_empty())
	check("descriptive source labels remain available for aliases",public_definition.source_name==home.name and public_instance.source_name==home.name)
	check("module lists use the same display identity",F.rows(data,"modules","definitions")[0].name=="住宅" and F.rows(data,"modules","instances")[0].name=="住宅")
	check("source snapshots and catalog remain byte-equivalent after display reads",JSON.stringify(data)==before and JSON.stringify(definitions)==original)
	public_definition.mechanism.family="changed"
	public_instance.stock_refs.supplies="changed"
	check("display DTO writes cannot change definition or instance authority",home.mechanism.family=="home" and data.modules.instances[0].stock_refs.supplies=="supply-stock")
	check("renaming cannot reveal hidden stock",not F.stock_visible(data,{"stocks":[{"id":"supply-stock","searched":true,"items":{"food":99}}]},"supply-stock"))
	check("catalog search accepts both functional and original building names",Catalog.matches(home,"all","all","all","住宅",{}) and Catalog.matches(home,"all","all","all",str(home.name),{}))
	check("handbook building name matches object and catalogue",Book.entry_name({"kind":"module","name":home.name,"definition":home})=="住宅")
	check("handbook item and process names are unchanged",Book.entry_name({"kind":"item","name":"原水"})=="原水" and Book.entry_name({"kind":"process","name":"锯板","definition":{"mode":"manual"}})=="锯板 · 手工作业")
	data.modules.available=false
	check("unavailable module section still hides both lists and selected rows",F.rows(data,"modules","instances").is_empty() and F.instance(data,"home-instance").is_empty() and F.definition(data,str(home.id)).is_empty())
	var failed: int = checks.filter(func(row:Dictionary)->bool:return not row.ok).size()
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		DirAccess.make_dir_recursive_absolute(args[0])
		var file := FileAccess.open(args[0]+"/results.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failed":failed,"scope":"Real catalog display labels, detached projections and source/visibility preservation; no engine performance claim."},"\t"));file.close()
	print("building identity18 "+str(checks.size()-failed)+"/"+str(checks.size()))
	quit(0 if failed==0 else 1)
