extends RefCounted
## Public presentation seam for a future D handoff; no world/time authority.
## Native Mobile features only. No unsupported SSAO/GI or fake dark overlays.
static func mount(parent:Node3D)->Dictionary:
	var environment:=WorldEnvironment.new();environment.name="SettlementEnvironment"
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("87938d")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("b4c3cd");settings.ambient_light_energy=0.38
	settings.tonemap_mode=Environment.TONE_MAPPER_ACES
	environment.environment=settings;parent.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.name="SettlementSun"
	sun.rotation_degrees=Vector3(-52,-35,0);sun.light_color=Color("ffe8c9");sun.light_energy=1.0
	sun.shadow_enabled=true;sun.directional_shadow_max_distance=90
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	parent.add_child(sun)
	return {"environment":environment,"sun":sun}
