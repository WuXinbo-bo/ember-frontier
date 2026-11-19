extends SceneTree
const Data = preload("res://scripts/world/world_data.gd")
func _initialize() -> void:
	var out: Array = []
	out.append({"decimal_float_literal":str(9007199254740991.0),"integer_conversion":str(float(Data.MAX_SAFE_INTEGER)),"literal_equal_to_int_conversion":9007199254740991.0==float(Data.MAX_SAFE_INTEGER)})
	for value in [9007199254740990,9007199254740991,9007199254740992]:
		out.append({"int_string":str(value),"float_string":str(float(value)),"abs_string":str(abs(float(value))),"is_finite":is_finite(float(value)),"floor_equal":float(value)==floor(float(value)),"below_literal_limit":abs(float(value))<=9007199254740991.0,"integer":Data.integer(value),"safe_float":Data.integer(float(value))})
	print(JSON.stringify(out));quit()
