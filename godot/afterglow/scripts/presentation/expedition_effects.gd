extends Node3D
## All cues consume committed events. The pool caps primitives and sound voices.
const G = preload("res://scripts/buildings/building_geometry.gd")
const LOOKUP_SECONDS = 0.15
var _runtime: RefCounted
var _pool: Array[Dictionary] = []
var _site: Node3D
var _exit: Node3D
var _entrances: Array[Node3D] = []
var _audio: Dictionary = {}
var _until_lookup := 0.0

func configure(runtime: RefCounted) -> void:
	_runtime = runtime
	for i: int in 20:
		var view := MeshInstance3D.new()
		view.mesh = ImmediateMesh.new()
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.material_override = material(Color.WHITE)
		view.hide()
		add_child(view)
		_pool.append({"view":view,"remaining":0.0,"life":1.0})
	for id: String in ["club","bow","impact","warning","clear"]:
		var source := AudioStreamPlayer.new()
		source.stream = sound(id)
		source.max_polyphony = 3 if id == "impact" else 1
		source.volume_db = -15.0 if id == "impact" else -11.0
		add_child(source)
		_audio[id] = source
	if not runtime.expedition_snapshot().is_empty():
		_site = signpost("废弃补给站",Color("ffd583"),true)
		_exit = signpost("撤离 · 旧村",Color("5edbd0"),false)
		for i: int in 2: _entrances.append(signpost("感染者来袭",Color("ff805c"),false))
	runtime.changed.connect(_events)

func _exit_tree() -> void:
	if _runtime != null and _runtime.changed.is_connected(_events):
		_runtime.changed.disconnect(_events)

func _events(change: Dictionary) -> void:
	for event: Dictionary in change.get("events", []):
		match event.kind:
			"expedition-warning", "village-defense-warning":
				_audio.warning.play()
				_until_lookup = 0.0
			"expedition-wave-cleared", "village-defense-wave-cleared":
				_audio.clear.play()
				_until_lookup = 0.0
			"combat-windup":
				if event.get("actor_id") == "player" and event.get("weapon") != "bow": _audio.club.play()
			"combat-miss":
				if event.get("actor_id") != "player" or not event.get("contact", false): continue
				var origin: Vector3 = G.point(event.from) + Vector3.UP * 0.95
				var direction: Vector3 = G.point(event.aim)
				if event.get("weapon") == "bow":
					_audio.bow.play()
				else:
					slash(origin, origin + direction, true)
			"combat-hit":
				var weapon: String = event.get("weapon", "")
				var manual: bool = event.get("manual", false)
				if manual or weapon in ["club", "bow"]:
					var origin: Vector3 = G.point(event.from) + Vector3.UP * 0.95
					var target: Vector3 = G.point(event.position) + Vector3.UP
					if event.get("primary_hit", false):
						if weapon == "bow":
							_audio.bow.play()
							arrow(origin, target)
						else:
							if not manual: _audio.club.play()
							slash(origin, target)
					impact(target, origin.direction_to(target), false)
				elif event.get("target_id") == "player":
					var actor: Dictionary = _runtime.actor("player")
					impact(G.point(actor) + Vector3.UP,Vector3.FORWARD,true)

func _process(delta: float) -> void:
	for entry: Dictionary in _pool:
		if float(entry.remaining) <= 0: continue
		entry.remaining = maxf(0.0, float(entry.remaining) - delta)
		var view: MeshInstance3D = entry.view
		view.visible = entry.remaining > 0
		var tint: Color = entry.tint
		tint.a *= smoothstep(0.0, 0.60, float(entry.remaining) / float(entry.life))
		view.material_override.albedo_color = tint
		if entry.get("drift",Vector3.ZERO) != Vector3.ZERO: view.position += entry.drift * delta
		if entry.get("flight", Vector3.ZERO) != Vector3.ZERO:
			view.position = entry.origin + entry.flight * (1.0 - float(entry.remaining) / float(entry.life))
	_until_lookup -= delta
	if _until_lookup > 0 or _site == null: return
	_until_lookup = LOOKUP_SECONDS
	var run: Dictionary = _runtime.expedition_snapshot()
	var actor: Dictionary = _runtime.actor("player")
	if actor.is_empty() or run.is_empty(): return
	var phase: String = run.phase
	_sync_site(_site,run.site,phase in ["idle","approach"] and actor.regionId == "RH-HOME")
	_sync_site(_exit,run.exit,phase in ["retreat","complete","between"] and actor.regionId == "RH-HOME")
	for i: int in _entrances.size():
		var enabled: bool = phase == "warning" and i < run.entrances.size()
		_sync_site(_entrances[i],run.entrances[i] if enabled else {},enabled)

func _sync_site(node: Node3D, point: Dictionary, enabled: bool) -> void:
	if not enabled:
		node.hide()
		return
	# Locations are presentation only; the gameplay query validates contact and spawn stands.
	var feet: Dictionary = _runtime._services.buildings.current_space().standing_point(point)
	node.visible = not feet.is_empty()
	if node.visible: node.position = G.point(feet)

func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat

func signpost(title: String, tint: Color, crate: bool) -> Node3D:
	var marker := Node3D.new()
	add_child(marker)
	marker.hide()
	var sign_text := Label3D.new()
	sign_text.text = title
	sign_text.font_size = 43
	sign_text.pixel_size = .011
	sign_text.modulate = tint
	sign_text.outline_size = 10
	sign_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_text.position.y = 1.85 if crate else 1.2
	marker.add_child(sign_text)
	if crate:
		var box := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(0.9,0.5,0.54)
		box.mesh = shape
		box.material_override = material(Color("776040"))
		box.position.y = 0.26
		marker.add_child(box)
		for x: float in [-0.28, 0.28]:
			var strap := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.07,0.52,0.57)
			strap.mesh = mesh
			strap.material_override = material(Color("9da48b"))
			strap.position = Vector3(x,0.26,0)
			marker.add_child(strap)
	else:
		for i: int in 3:
			var line := MeshInstance3D.new()
			var shape := BoxMesh.new()
			shape.size = Vector3(.21,.045,1.7)
			line.mesh = shape
			line.material_override = material(Color(tint,.78))
			line.position = Vector3(-0.48 + float(i)*.48, .08, 0)
			line.rotation.y = -0.4
			marker.add_child(line)
	return marker

func activate(origin: Vector3, tint: Color, lifetime: float, drift: Vector3 = Vector3.ZERO, flight: Vector3 = Vector3.ZERO) -> ImmediateMesh:
	var selected: Dictionary = _pool[0]
	for entry: Dictionary in _pool:
		if float(entry.remaining) < float(selected.remaining): selected = entry
		if float(entry.remaining) <= 0:
			selected = entry
			break
	var view: MeshInstance3D = selected.view
	view.position = origin
	view.visible = true
	view.material_override.albedo_color = tint
	selected.merge({"remaining":lifetime,"life":lifetime,"tint":tint,"drift":drift,"flight":flight,"origin":origin},true)
	var mesh: ImmediateMesh = view.mesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	return mesh

func quad(mesh: ImmediateMesh, a:Vector3,b:Vector3,c:Vector3,d:Vector3) -> void:
	for vertex: Vector3 in [a,b,c,a,c,d]: mesh.surface_add_vertex(vertex)

func slash(from: Vector3,to: Vector3, miss: bool = false) -> void:
	var angle := atan2(to.z-from.z,to.x-from.x)
	var mesh := activate(from - Vector3.UP * .22, Color("9eadb7") if miss else Color("fff1be"), .16 if miss else .24)
	for i: int in 12:
		var a := angle + lerpf(-1.18,1.18,float(i)/12.0)
		var b := angle + lerpf(-1.18,1.18,float(i+1)/12.0)
		var first := Vector3(cos(a),0,sin(a)); var last := Vector3(cos(b),0,sin(b))
		var thick_a := .34*sin(PI*float(i)/12.0)
		var thick_b := .34*sin(PI*float(i+1)/12.0)
		quad(mesh,first*1.85,last*1.85,last*(1.85-thick_b),first*(1.85-thick_a))
	mesh.surface_end()

func arrow(from: Vector3,to: Vector3) -> void:
	var ray := to - from
	var forward := ray.normalized()
	var side := forward.cross(Vector3.UP).normalized() * .045
	var tail := -forward * .74
	var mesh := activate(from,Color("ffdfa0"),.145,Vector3.ZERO,ray)
	quad(mesh,tail-side,tail+side,side,-side)
	quad(mesh,tail-Vector3.UP*.045,tail+Vector3.UP*.045,Vector3.UP*.045,-Vector3.UP*.045)
	mesh.surface_end()

func impact(at: Vector3, direction: Vector3, player_hit: bool) -> void:
	_audio.impact.play()
	var mesh := activate(at,Color("ed715b") if player_hit else Color("ff9970"),.28,Vector3.UP*.75)
	for i: int in 7:
		var theta := TAU*float(i)/7.0
		var ray := Vector3(cos(theta), .28+sin(theta)*.45,sin(theta))
		var base := ray*.14
		var end := ray*(.25+.10*sin(theta*3)) + direction*.13
		quad(mesh,base-Vector3.UP*.035,base+Vector3.UP*.035,end+Vector3.UP*.015,end-Vector3.UP*.015)
	mesh.surface_end()

func sound(kind: String) -> AudioStreamWAV:
	# Original short cues. Modest headroom prevents many close hits clipping.
	var lengths := {"club":.13,"bow":.15,"impact":.11,"warning":.51,"clear":.34}
	var length: float = lengths[kind]
	var wav := AudioStreamWAV.new()
	wav.mix_rate = 22050
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	var bytes := PackedByteArray()
	bytes.resize(roundi(length*wav.mix_rate)*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7409
	var sample_previous := 0.0
	for i: int in bytes.size()/2:
		var t := float(i)/float(wav.mix_rate)
		var u := t/length
		var noise := rng.randf_range(-1,1)
		sample_previous = lerpf(sample_previous,noise,.2)
		var voice := 0.0
		match kind:
			"club": voice = sample_previous * sin(PI*u) * 1.8 + sin(TAU*(190.0*t-390.0*t*t))*.22*exp(-32.0*t)
			"bow": voice = (sin(TAU*(540.0*t-900.0*t*t))*.38 + (noise-sample_previous)*.18)*exp(-25.0*t)
			"impact": voice = (sin(TAU*(128.0*t-320.0*t*t))*.65 + sample_previous*.6)*exp(-33.0*t)
			"warning": voice = sin(TAU*t*211.0)*.38*sin(PI*u)*pow(sin(TAU*t*3.0),2.0)
			"clear": voice = (sin(TAU*t*330.0)*.38 + sin(TAU*t*493.88)*.22)*sin(PI*u)
		voice *= minf(1.0,t*700.0) * minf(1.0,(length-t)*350.0)
		bytes.encode_s16(i*2,roundi(clampf(voice,-.9,.9)*32767.0))
	wav.data = bytes
	return wav
