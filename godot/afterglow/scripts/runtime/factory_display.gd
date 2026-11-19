extends RefCounted
## Read-state and explored-map memory only. No inventory, jobs, perception,
## simulation clock, repairs, movement or authority beyond the shared commit.
const Data=preload("res://scripts/world/world_data.gd")
const KEY:="r34:display"
const POLL_SECONDS:=0.5
const STABLE_SECONDS:=1.0
const TILE_METRES:=4.0
const HISTORY_LIMIT:=128
const Handbook=preload("res://scripts/runtime/factory_handbook.gd")
const FAVORITES_LIMIT:=256
const SEVERITY:={"info":0,"warning":1,"danger":2,"critical":3}
var _world:RefCounted
var _runtime:WeakRef
var _last_poll:float=-1.0

static func initial()->Dictionary:
	return {"version":1,"next_episode":1,"active":[],"history":[],"explored_tiles":[]}

func configure(context:Dictionary)->void:
	_world=context.world;_runtime=weakref(context.runtime);_last_poll=-1.0

func state(overrides:Dictionary={})->Dictionary:
	# WorldView.extension already returns a detached deep copy. Overrides are
	# caller-owned and still require isolation; never return their live object.
	if overrides.has(KEY):return overrides[KEY].duplicate(true) if overrides[KEY] is Dictionary else initial()
	var value:Variant=_world.extension(KEY)
	return value if value is Dictionary else initial()

func hold_descriptors(_facts:Dictionary,_overrides:Dictionary={})->Array:return []

static func _text(value:Variant,limit:int=4096)->bool:
	return value is String and value.length()<=limit

static func _number(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0

static func valid_source(value:Variant)->bool:
	return value is Dictionary and _text(value.get("key"),1024) and not value.key.is_empty() and Data.valid_id(value.get("object_id")) and Data.valid_id(value.get("reason_code")) and SEVERITY.has(value.get("severity")) and Data.vec(value.get("location")) and Data.valid_id(value.location.get("regionId")) and _text(value.get("title")) and _text(value.get("detail","")) and _text(value.get("episode_id",""),1024)

static func validate(value:Variant)->Dictionary:
	var bad:Dictionary={"ok":false,"code":"INVALID_DISPLAY_STATE","reason":"告警阅读状态或已探索地图损坏；原存档保留"}
	if not value is Dictionary or value.get("version")!=1 or not Data.integer(value.get("next_episode")) or int(value.next_episode)<1:return bad
	if not value.get("active") is Array or not value.get("history") is Array or not value.get("explored_tiles") is Array or value.history.size()>HISTORY_LIMIT:return bad
	var ids:Dictionary={};var keys:Dictionary={}
	for resolved:bool in [false,true]:
		for row:Variant in value.history if resolved else value.active:
			if not valid_source(row) or not Data.valid_id(row.get("id")) or ids.has(row.id) or not Data.integer(row.get("episode")) or int(row.episode)<1 or int(row.episode)>=int(value.next_episode):return bad
			ids[row.id]=true
			if row.id!="alert:%d"%int(row.episode) or row.get("resolved")!=resolved:return bad
			for key:String in ["first_seen","ignored_until","resolved_at"]:
				if not _number(row.get(key)):return bad
			for key:String in ["acknowledged","pending"]:
				if not row.get(key) is bool:return bad
			if not Data.integer(row.get("notification")) or int(row.notification)<1:return bad
			if not resolved:
				if keys.has(row.key):return bad
				keys[row.key]=true
	var tiles:Dictionary={}
	for tile:Variant in value.explored_tiles:
		if not tile is Dictionary or not Data.valid_id(tile.get("region_id")) or not Data.integer(tile.get("x")) or not Data.integer(tile.get("z")):return bad
		var key:String=tile_key(tile)
		if tiles.has(key):return bad
		tiles[key]=true
	if value.has("handbook"):
		var book:Variant=value.handbook
		if not book is Dictionary or not book.get("favorites") is Array or book.favorites.size()>FAVORITES_LIMIT or not book.get("tracked_target") is String:return bad
		if not book.tracked_target.is_empty() and not Data.valid_id(book.tracked_target):return bad
		var favorites:Dictionary={}
		for id:Variant in book.favorites:
			if not Data.valid_id(id) or favorites.has(id):return bad
			favorites[id]=true
	return {"ok":true}

func validate_extensions(_facts:Dictionary,overrides:Dictionary={})->Dictionary:
	return validate(overrides[KEY] if overrides.has(KEY) else _world.extension(KEY))

static func tile_key(tile:Dictionary)->String:
	return "%s:%d:%d"%[tile.region_id,int(tile.x),int(tile.z)]

static func _archive(row:Dictionary,now:float,why:String)->Dictionary:
	var copy:Dictionary=row.duplicate(true)
	copy.resolved=true;copy.resolved_at=now;copy.resolved_reason=why
	return copy

static func reconcile(previous:Dictionary,sources:Array,now:float,player:Dictionary={})->Dictionary:
	var next:Dictionary=previous.duplicate(true)
	var old:Dictionary={};var current:Dictionary={}
	for row:Dictionary in previous.active:old[row.key]=row
	for row:Variant in sources:
		if valid_source(row) and not current.has(row.key):current[row.key]=row
	var active:Array=[]
	var ordered:Array=current.keys();ordered.sort()
	for key:String in ordered:
		var source:Dictionary=current[key];var row:Dictionary=old.get(key,{}).duplicate(true)
		if not row.is_empty() and row.get("episode_id","")!=source.get("episode_id",""):
			if not row.pending:next.history.append(_archive(row,now,"new_source_episode"))
			row={}
		if row.is_empty():
			row={"id":"alert:%d"%int(next.next_episode),"episode":int(next.next_episode),"notification":1,"first_seen":now,"acknowledged":false,"ignored_until":0.0,"resolved":false,"resolved_at":0.0,"pending":int(SEVERITY[source.severity])<2}
			next.next_episode+=1
		elif int(SEVERITY[source.severity])>int(SEVERITY[row.severity]):
			row.acknowledged=false;row.ignored_until=0.0;row.notification+=1
		for field:String in ["key","object_id","reason_code","severity","location","title","detail","episode_id"]:
			row[field]=source.get(field,"" if field in ["detail","episode_id"] else null)
		if int(SEVERITY[source.severity])>=2 or now-float(row.first_seen)>=STABLE_SECONDS:row.pending=false
		active.append(row)
	for key:String in old:
		if not current.has(key) and not old[key].pending:next.history.append(_archive(old[key],now,"no_longer_reported"))
	next.active=active
	if next.history.size()>HISTORY_LIMIT:next.history=next.history.slice(next.history.size()-HISTORY_LIMIT)
	if not player.is_empty():
		var tile:Dictionary={"region_id":str(player.regionId),"x":floori(float(player.x)/TILE_METRES),"z":floori(float(player.z)/TILE_METRES)}
		var key:String=tile_key(tile)
		if not next.explored_tiles.any(func(v:Dictionary)->bool:return tile_key(v)==key):next.explored_tiles.append(tile)
	return next

func _current()->Dictionary:
	var host:Variant=_runtime.get_ref()
	if host==null:return state()
	return reconcile(state(),host.factory_alert_sources("player"),host.clock(),host.actor("player"))

func _plan(after:Dictionary,events:Array=[])->Dictionary:
	var before:Variant=_world.extension(KEY);var changes:Array=[]
	if before!=after:changes.append({"op":"extension.set","id":KEY,"before_exists":_world.has_extension(KEY),"before":before,"after":after.duplicate(true)})
	return {"ok":true,"code":"OK","reason":null,"world_changes":changes,"fact_changes":[],"events":events.duplicate(true)}

func advance(_dt:float)->Dictionary:
	var host:Variant=_runtime.get_ref()
	if host==null:return {"ok":false,"code":"UNAVAILABLE"}
	var now:float=host.clock()
	if _last_poll>=0 and now-_last_poll<POLL_SECONDS-0.000001:return {"ok":true}
	_last_poll=now
	return _plan(_current())

func availability(request:Dictionary)->Dictionary:
	var result:Dictionary=prepare(request)
	if result.get("ok",false):result.world_changes=[];result.fact_changes=[];result.events=[]
	return result

func prepare(request:Dictionary)->Dictionary:
	if request.get("actor_id","player")!="player":return _failure("FORBIDDEN","只能更改当前玩家的告警阅读状态")
	if str(request.get("kind","")).begins_with("handbook."):return _prepare_handbook(request)
	if request.kind not in ["alerts.acknowledge","alerts.ignore"]:return _failure("UNSUPPORTED","告警只支持确认或暂时忽略，不能点击解决")
	var after:Dictionary=_current();var target:String=str(request.get("target_id",""));var found:Dictionary={}
	var payload:Dictionary=request.get("payload",{})
	for row:Dictionary in after.active:
		if row.id==target and row.key==payload.get("key") and row.id+":"+str(row.notification)==payload.get("notification_token") and not row.pending:found=row;break
	if found.is_empty():return _failure("STALE_ALERT","告警已经结束或已是另一事件，请刷新")
	var host:Variant=_runtime.get_ref();var now:float=host.clock()
	if request.kind=="alerts.ignore":
		if found.severity=="critical":return _failure("CRITICAL_ALERT","紧急告警可以确认，但不能隐藏或静音")
		var duration:Variant=request.get("payload",{}).get("seconds",60.0)
		if not _number(duration) or float(duration)<=0 or float(duration)>300:return _failure("INVALID_DURATION","暂忽略时长须大于0且不超过300模拟秒")
		found.ignored_until=now+float(duration)
	found.acknowledged=true
	# Display commands deliberately produce no gameplay event. Recording a
	# read-state click in the survival/story ledger would alter unrelated facts.
	return _plan(after)

func _prepare_handbook(request:Dictionary)->Dictionary:
	if request.kind not in ["handbook.favorite","handbook.track"]:return _failure("UNSUPPORTED","手册只支持收藏与固定目标")
	var enabled:Variant=request.get("payload",{}).get("enabled")
	if not enabled is bool:return _failure("INVALID_HANDBOOK_PREFERENCE","阅读偏好需要明确的开关")
	var target:String=str(request.get("target_id",""))
	var host:Variant=_runtime.get_ref()
	if host==null:return _failure("UNAVAILABLE","当前手册不可用")
	var projection:Dictionary=host.handbook_snapshot("player")
	if not projection.get("available",false) or not projection.entries.any(func(row:Dictionary)->bool:return row.id==target):return _failure("UNKNOWN_HANDBOOK_ENTRY","条目已不存在，请刷新手册")
	# Reading preferences do not reconcile alerts or advance explored tiles.
	# Old captures remain byte-identical until an explicit preference command.
	var after:Dictionary=state();var book:Dictionary=Handbook.preferences(after)
	if request.kind=="handbook.favorite":
		if enabled and not book.favorites.has(target):
			if book.favorites.size()>=FAVORITES_LIMIT:return _failure("HANDBOOK_FAVORITES_FULL","手册收藏已达上限，请先取消其他收藏")
			book.favorites.append(target)
		elif not enabled:book.favorites.erase(target)
	else:
		if enabled:book.tracked_target=target
		elif book.tracked_target==target:book.tracked_target=""
	after.handbook=book
	return _plan(after)

func projection(raw:Array,now:float,include_history:bool=true)->Dictionary:
	# Query is pure. Rebuild from public owner facts for stale/urgent changes;
	# only advance or an explicit command persists the deterministic read state.
	var next:Dictionary=reconcile(state(),raw,now)
	var rows:Array=[];var summary:Dictionary={"new":0,"acknowledged":0,"ignored":0,"critical":0,"total":0}
	for source:Dictionary in next.active:
		if source.pending:continue
		var row:Dictionary=source.duplicate(true)
		row.status="ignored" if row.severity!="critical" and float(row.ignored_until)>now else "acknowledged" if row.acknowledged else "new"
		row.notification_token=row.id+":"+str(row.notification)
		row.allowed_actions=["acknowledge","locate"] if row.severity=="critical" else ["acknowledge","ignore","locate"]
		summary[row.status]+=1;summary.total+=1
		if row.severity=="critical":summary.critical+=1
		rows.append(row)
	rows.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if a.severity!=b.severity:return int(SEVERITY[a.severity])>int(SEVERITY[b.severity])
		return a.key<b.key)
	var result:Dictionary={"alerts":rows,"alert_summary":summary,"tile_metres":TILE_METRES}
	if include_history:
		result.alert_history=next.history.duplicate(true)
		result.explored_tiles=state().explored_tiles.duplicate(true)
	return result

static func _failure(code:String,reason:String)->Dictionary:return {"ok":false,"code":code,"reason":reason}
