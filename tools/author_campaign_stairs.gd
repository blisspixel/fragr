extends SceneTree

## Append the registered stair architecture without moving earlier host indices.
## Offline usage: -- <input map directory> <output map directory>.
## Input maps contain the original geometry, before these bounded additions.
const FILES: Dictionary = {
	8:"m08_custodian_of_record.json",9:"m09_passenger_manifest.json",
	10:"m10_common_carrier.json",12:"m12-terms-of-cooperation.json",
}

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:
		push_error("author_campaign_stairs: require input and output map directories")
		quit(1)
		return
	var documents: Dictionary={}
	for stage: int in FILES:
		var path:=args[0].path_join(FILES[stage])
		var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not source is Dictionary or not source.get("solids") is Array:
			push_error("author_campaign_stairs: invalid source for M%02d" % stage)
			quit(1)
			return
		if not append_enclosures(source,stage):
			quit(1)
			return
		# JSON numbers must retain the schema's integer tokens after parsing.
		source.version=int(source.version)
		source.map_id=int(source.map_id)
		for supply: Dictionary in source.supplies:
			if supply.grant.has("amount"):
				supply.grant.amount=int(supply.grant.amount)
		for group: Dictionary in source.encounters:
			for enemy: Dictionary in group.enemies:
				if enemy.has("armor"):
					enemy.armor=int(enemy.armor)
		if stage==9:
			for crew: Dictionary in source.m09.crew:
				for index: int in range(crew.held_until.size()):
					crew.held_until[index]=int(crew.held_until[index])
		documents[stage]=source
	if DirAccess.make_dir_recursive_absolute(args[1])!=OK:
		quit(1)
		return
	for stage: int in FILES:
		var file:=FileAccess.open(args[1].path_join(FILES[stage]),FileAccess.WRITE)
		if file==null:
			push_error("author_campaign_stairs: output cannot be written")
			quit(1)
			return
		file.store_string(JSON.stringify(documents[stage],"  ",true,true)+"\n")
		file.close()
	print("author_campaign_stairs: PASS four bounded append-only maps")
	quit(0)

static func append_enclosures(source: Dictionary,stage: int) -> bool:
	var additions:=definitions(stage)
	if additions.is_empty():
		push_error("author_campaign_stairs: unregistered architecture stage")
		return false
	var ids: Dictionary={}
	for solid: Dictionary in source.solids:
		ids[solid.id]=true
	for solid: Dictionary in additions:
		if ids.has(solid.id):
			push_error("author_campaign_stairs: source already contains stair enclosure solids")
			return false
	source.solids.append_array(additions)
	return true

static func definitions(stage: int) -> Array[Dictionary]:
	var items: Array[Dictionary]=[]
	match stage:
		8:
			box(items,"west_tower_stair_inner_wall",[-26.0,0.0,-3.0],[-25.65,6.3,3.0])
			box(items,"west_tower_stair_outer_wall",[-30.35,0.0,-3.0],[-30.0,6.3,3.0])
			box(items,"west_tower_landing_south_guard",[-26.0,3.0,2.7],[-21.0,4.1,3.0])
			box(items,"west_tower_landing_north_guard",[-31.0,3.0,9.0],[-21.0,4.1,9.3])
			box(items,"east_tower_stair_inner_wall",[25.65,3.0,-4.0],[26.0,9.0,2.0])
			box(items,"east_tower_stair_outer_wall",[30.0,3.0,-4.0],[30.35,9.0,2.0])
			# Grounded return outside the standing landing footprint leaves the
			# narrow gallery portal's conservative navigation samples clear.
			box(items,"east_tower_landing_south_guard",[21.0,3.0,1.6],[26.0,7.1,1.9])
			box(items,"freight_west_stair_inner_wall",[-6.0,0.0,23.0],[-5.65,9.0,34.0])
			box(items,"freight_east_stair_inner_wall",[5.65,0.0,23.0],[6.0,9.0,34.0])
		9:
			box(items,"office_stair_top_turn",[-44.0,0.0,-27.0],[-38.0,4.0,-25.0])
			box(items,"office_stair_west_enclosure",[-44.3,0.0,-35.0],[-44.0,8.4,-25.0])
			box(items,"office_stair_east_enclosure",[-38.0,0.0,-35.0],[-37.7,8.4,-27.3])
			box(items,"office_stair_turn_end",[-44.3,0.0,-25.0],[-38.0,8.4,-24.7])
			box(items,"office_landing_south_guard",[-38.0,4.0,-35.3],[-18.0,5.1,-35.0])
			# The open transfer at z=-31 owns the first committed charge fall.
			box(items,"office_landing_east_guard",[-18.0,4.0,-35.0],[-17.7,5.1,-32.5])
			box(items,"office_landing_east_guard_north",[-18.0,4.0,-29.5],[-17.7,5.1,-27.0])
		10:
			box(items,"west_pressure_stair_inner_wall",[-3.55,2.0,-13.0],[-3.25,10.1,-2.7])
			box(items,"west_pressure_stair_turn_end",[-7.8,2.0,-3.0],[-3.25,10.1,-2.7])
			box(items,"west_pressure_stair_hull_join",[-7.8,2.0,-16.0],[-7.45,10.1,-3.0])
			box(items,"east_pressure_stair_inner_wall",[3.35,2.0,2.7],[3.65,10.1,13.0])
			box(items,"east_pressure_stair_turn_end",[3.35,2.0,2.7],[7.8,10.1,3.0])
			box(items,"east_pressure_stair_hull_join",[7.55,2.0,3.0],[7.8,10.1,16.0])
		12:
			for side: String in ["south","north"]:
				var low_z: float=-2.6 if side=="south" else 3.4
				var high_z: float=1.4 if side=="south" else 7.4
				box(items,"greenhouse_%s_stair_cheek_west" % side,[-2.4,0.3,low_z],[-2.0,3.3,high_z],"service_steel")
				box(items,"greenhouse_%s_stair_cheek_east" % side,[2.0,0.3,low_z],[2.4,3.3,high_z],"service_steel")
				var return_z: float=-2.6 if side=="south" else 7.1
				box(items,"greenhouse_%s_landing_return_west" % side,[-2.9,0.3,return_z],[-2.4,3.3,return_z+0.3],"service_steel")
				box(items,"greenhouse_%s_landing_return_east" % side,[2.4,0.3,return_z],[2.9,3.3,return_z+0.3],"service_steel")
			for edge: String in ["south","north"]:
				var low_z: float=1.1 if edge=="south" else 3.4
				box(items,"greenhouse_bridge_guard_%s_west" % edge,[-8.0,0.3,low_z],[-2.0,2.4,low_z+0.3],"service_steel")
				box(items,"greenhouse_bridge_guard_%s_east" % edge,[2.0,0.3,low_z],[8.0,2.4,low_z+0.3],"service_steel")
			box(items,"greenhouse_bridge_guard_west_end",[-8.3,0.3,1.1],[-8.0,2.4,3.7],"service_steel")
			box(items,"greenhouse_bridge_guard_east_end",[8.0,0.3,1.1],[8.3,2.4,3.7],"service_steel")
			for x: float in [-6.5,6.5]:
				for z: float in [1.9,2.9]:
					box(items,"greenhouse_bridge_support_%s_%s" % ["west" if x<0 else "east","south" if z<2.4 else "north"],[x-0.25,0.3,z-0.25],[x+0.25,1.05,z+0.25],"service_steel")
	return items

static func box(items: Array[Dictionary],id: String,low: Array,high: Array,surface: String="enamel") -> void:
	items.append({"id":id,"min":low,"max":high,"surface":surface})
