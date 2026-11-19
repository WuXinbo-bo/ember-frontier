extends RefCounted
## Choose only actual free consumables published by the same Runtime.
const P=preload("res://scripts/ui/ui_projection.gd")
const C=preload("res://scripts/ui/ui_composition.gd")

static func render(ui,parent: Node,include_rest: bool=true) -> void:
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(column)
	for spec: Array in [["eat","进食","食物"],["drink","饮水","安全饮水"],["medicine","处理伤势","医疗物品"]]:
		var kind:=str(spec[0]);var choices: Array=[]
		if is_instance_valid(ui.runtime) and ui.runtime.has_method("life_consumables"):
			var raw: Variant=ui.runtime.call("life_consumables","player",kind)
			if raw is Array:
				for row: Variant in raw:
					if row is Dictionary and row.get("kind")==kind and row.get("item_id") is String and float(row.get("free",0))>=1:choices.append(row)
		var row:=HBoxContainer.new();column.add_child(row)
		var key:="care_item:"+kind
		var chosen:=str(ui.factory_view.get(key,""))
		if not choices.any(func(value:Dictionary):return value.item_id==chosen):chosen=str(choices[0].item_id) if not choices.is_empty() else ""
		ui.factory_view[key]=chosen
		if not choices.is_empty():
			var select:=OptionButton.new();select.size_flags_horizontal=Control.SIZE_EXPAND_FILL;select.clip_text=true;select.set_meta("ui_focus_key","care:select:"+kind)
			for index in choices.size():
				var value: Dictionary=choices[index]
				select.add_item(str(value.get("name",P.item_name(value.item_id)))+" · 可用 "+P.number(value.free));select.set_item_metadata(index,str(value.item_id))
				select.set_item_tooltip(index,P.item_name(value.item_id)+" · 每次消耗1份，实际生效需完成动作")
				if value.item_id==chosen:select.select(index)
			select.item_selected.connect(func(index:int):ui.factory_view[key]=str(select.get_item_metadata(index));ui.queue_refresh())
			row.add_child(select)
		var payload: Dictionary={"item_id":chosen} if not chosen.is_empty() else {}
		var ready: Dictionary=ui.availability(ui.request(kind,"",payload))
		var reason: String="随身没有可用的"+str(spec[2]) if choices.is_empty() else "" if ready.get("ok",false) else P.action_feedback(ready,kind)
		var button: Button=ui.add_button(str(spec[1]),func():ui.execute(kind,"",payload,true),"care:use:"+kind,reason,row)
		button.size_flags_horizontal=Control.SIZE_SHRINK_END
	if include_rest:
		var ready: Dictionary=ui.availability(ui.request("rest",""))
		ui.add_button("休息",func():ui.execute("rest","",{},true),"care:rest","" if ready.get("ok",false) else P.action_feedback(ready,"rest"),column)
	C.caption(ui,"原水、过滤原水、种子和生食材不进入饮食选项",column)
