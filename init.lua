tpad = {}
tpad.version = "1.1"
tpad.tile_image = "tpad-16.png"

-- load storage facilities and verify it
dofile(minetest.get_modpath(minetest.get_current_modname()) .. "/storage.lua")

-- workaround storage to tell the main dialog about the last clicked pad
local last_clicked_pos = {}

-- workaround storage to tell the main dialog about last selected station in the list
local last_selected_index = {}

-- memory of shown waypoints
local waypoint_hud_ids = {}

-- not-so-cheap recipe
minetest.register_craft({
	output = 'tpad:tpad',
	recipe = {
		{'group:wood',           'default:bronze_ingot', 'group:wood'},
		{'default:bronze_ingot', 'group:wood',           'default:bronze_ingot'},
		{'group:wood',           'default:bronze_ingot', 'group:wood'},
	}
})

-- ========================================================================
-- callback bound in register_chatcommand("tpad")
-- ========================================================================

function tpad.command(playername, param)
	tpad.hud_off(playername)
	if(param == "off") then return end
	
	local player = minetest.get_player_by_name(playername)
	local pads = tpad._get_stored_pads(playername)
	local shortest_distance = nil
	local closest_pad = nil
	local playerpos = player:getpos()
	for strpos, padname in pairs(pads) do
		local pos = minetest.string_to_pos(strpos)
		local distance = vector.distance(pos, playerpos)
		if not shortest_distance or distance < shortest_distance then
			closest_pad = {
				pos = pos,
				name = padname .. " " .. strpos,
			}
			shortest_distance = distance
		end
	end
	if closest_pad then
		waypoint_hud_ids[playername] = player:hud_add({
			hud_elem_type = "waypoint",
			name = closest_pad.name,
			world_pos = closest_pad.pos,
			number = 0xFF0000,
		})
		minetest.chat_send_player(playername, "Waypoint to " .. closest_pad.name .. " displayed")
	end
end

function tpad.hud_off(playername)
	local player = minetest.get_player_by_name(playername)
	local hud_id = waypoint_hud_ids[playername]
	if hud_id then
		player:hud_remove(hud_id)
	end	
end

-- ========================================================================
-- callbacks bound in register_node("tpad:tpad")
-- ========================================================================

function tpad.on_construct(pos)
	local meta = minetest.env:get_meta(pos)
	meta:set_string("infotext", "Tpad Station - right click to interact")
end

function tpad.after_place_node(pos, placer)
	local meta = minetest.env:get_meta(pos)
	meta:set_string("owner", placer:get_player_name())
	tpad.set_pad_name(pos, "")
end

function tpad.on_rightclick(clicked_pos, node, clicker)
	local playername = clicker:get_player_name()
	local clicked_meta = minetest.env:get_meta(clicked_pos)
	local ownername = clicked_meta:get_string("owner")
	local padname = tpad.get_pad_name(clicked_pos)
	local formspec = tpad.get_main_dialog(playername, ownername, padname)
	last_clicked_pos[playername] = clicked_pos;
	minetest.show_formspec(clicker:get_player_name(), "form_padlist", formspec)
end

function tpad.can_dig(pos, player)
	local meta = minetest.env:get_meta(pos)
	local owner = meta:get_string("owner")
	local name = player:get_player_name()
	if owner == "" or owner == nil or name == owner then 
		return true
	end
	return false
end

function tpad.on_destruct(pos)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	tpad.del_pad(ownername, pos)
end

-- ========================================================================
-- callback bound in register_on_player_receive_fields()
-- ========================================================================

function tpad.on_receive_fields(player, formname, fields)
	if formname == "form_padlist" then
		tpad.process_padlist_fields(player, formname, fields)
	end
	if formname == "form_deletepad" then
		tpad.process_deletepad_fields(player, formname, fields)
	end
end

function tpad.process_padlist_fields(player, formname, fields)
	local playername = player:get_player_name()
	local clicked_pos = last_clicked_pos[playername]
	local clicked_meta = minetest.env:get_meta(clicked_pos)
	local ownername = clicked_meta:get_string("owner");
	
	if fields.padlist then
		local action, index = fields.padlist:match("(.+):(.+)")
		index = tonumber(index)
		if action == "DCL" then
			-- player doubleclicked a station in the list
			tpad.checked_pad_teleport(formname, player, playername, ownername, index)
		else
			last_selected_index[playername .. ":" .. ownername] = index
		end
		return
	end

	local selected_index = last_selected_index[playername .. ":" .. ownername]
	
	if not selected_index and (fields.teleport or fields.delete) then
		minetest.chat_send_player(playername, "Tpad: Please select a station first")
		return
	end
	
	if fields.teleport then
		tpad.checked_pad_teleport(formname, player, playername, ownername, selected_index)
		return
	end
	
	if fields.delete then
		local selected_pad = tpad.get_pad_by_index(ownername, selected_index)
		if minetest.pos_to_string(selected_pad.pos) == minetest.pos_to_string(clicked_pos) then
			minetest.chat_send_player(playername, "Tpad: You can't delete the current pad, destroy it manually")
			return
		end
		tpad.confirm_pad_deletion(formname, player, playername, ownername, selected_index)
		return
	end
	
	if playername ~= ownername then return end
	
	local save_by_click = fields.save and fields.station
	local save_by_enter = fields.key_enter and fields.key_enter_field == "station"
	
	if save_by_click or save_by_enter then
		tpad.set_pad_name(clicked_pos, fields.station)
	end
end

function tpad.process_deletepad_fields(player, formname, fields)
	local playername = player:get_player_name()
	local clicked_pos = last_clicked_pos[playername]
	local clicked_meta = minetest.env:get_meta(clicked_pos)
	local ownername = clicked_meta:get_string("owner");
	local selected_index = last_selected_index[playername .. ":" .. ownername]
	local selected_pad = tpad.get_pad_by_index(ownername, selected_index)
	if fields.confirm then
		last_selected_index[playername .. ":" .. ownername] = nil
		tpad.del_pad(ownername, selected_pad.pos)
		minetest.remove_node(selected_pad.pos)
		minetest.chat_send_player(playername, "Tpad: station " .. selected_pad.name .. " deleted")
	else
		minetest.chat_send_player(playername, "Tpad: deletion of " .. selected_pad.name .. " cancelled")
	end
	minetest.close_formspec(playername, "form_deletepad")
	local clicked_padname = tpad.get_pad_name(clicked_pos)
	local formspec = tpad.get_main_dialog(playername, ownername, clicked_padname)
	minetest.show_formspec(playername, "form_padlist", formspec)
end

-- ========================================================================
-- helper functions
-- ========================================================================

function tpad.checked_pad_teleport(formname, player, playername, ownername, index)
	local pad = tpad.get_pad_by_index(ownername, index)
	if not pad then
		minetest.chat_send_player(playername, "Tpad: Unable to teleport to " .. pad.name .. ", pad not found!")
		return
	end

	player:moveto(pad.pos, false)
	minetest.chat_send_player(playername, "Tpad: Teleported to " .. pad.name)
	tpad.hud_off(playername)
	minetest.close_formspec(playername, formname)
end

function tpad.confirm_pad_deletion(formname, player, playername, ownername, index)
	local pad = tpad.get_pad_by_index(ownername, index)
	if not pad then
		minetest.chat_send_player(playername, "Tpad: Unable to delete " .. pad.name .. ", pad not found!")
		return
	end

	if playername ~= ownername then
		-- we should never come to this point, failsafe
		minetest.chat_send_player(playername, "Tpad: " .. pad.name .. " does not belong to you!")
		return
	end

	local formspec = tpad.get_deletion_dialog(pad.name)
	minetest.show_formspec(playername, "form_deletepad", formspec)
end

function tpad.table_to_formspec(formtable)
	local output = ""
	for r = 1, #formtable do
		local row = formtable[r]
		local fieldname = row[1]
		output = output .. fieldname .. "["
		for c = 2, #row do
			local cell = row[c]
			if type(cell) == "table" then
				cell = table.concat(cell, ",")
			end
			output = output .. cell
			if c < #row then
				output = output .. ";"
			end
		end
		output = output .. "]"
	end
	return output
end

-- main dialog shown when right-clicking a pad
function tpad.get_main_dialog(playername, ownername, padname)
	local padlist = tpad.get_padlist(ownername)
	local formtable = {{"size", {5, 5}}}
	padname = minetest.formspec_escape(padname)
	if playername == ownername then 
		table.insert(formtable, {"field", {0.5, 1}, {3, 0}, "station", 	"This station name", padname})
		table.insert(formtable, {"button_exit", {3.5, 0.7}, {1, 0}, "save", "Save"})
		table.insert(formtable, {"button", {3.5, 2.7}, {1, 0}, "delete", "Delete"})
	else
		ownername = minetest.formspec_escape(ownername)
		table.insert(formtable, {"label", {0.5, 1}, "Station \"" .. padname .. "\", owned by " .. ownername})
	end
	local last_index = last_selected_index[playername .. ":" .. ownername] 
	table.insert(formtable, {"textlist", {0.2, 1.4}, {3, 3}, "padlist", padlist, last_index})
	table.insert(formtable, {"button", {3.5, 1.7}, {1, 0}, "teleport", "Teleport"})
	table.insert(formtable, {"button_exit", {3.5, 3.7}, {1, 0}, "close", "Close"})
	table.insert(formtable, {"label", {0.5, 5}, "(you can doubleclick on a station to teleport)"})
	
	return tpad.table_to_formspec(formtable)
end

-- confirmation dialog when trying to delete a pad from the main dialog
function tpad.get_deletion_dialog(padname)
	padname = minetest.formspec_escape(padname)
	local formtable = {
		{"size", {5, 2}},
		{"label", {0, 0}, "Are you sure you want to destroy \"" .. padname .. "\" station?"},
		{"label", {0, 0.5}, "(you will not get the pad back)"},
		{"button_exit", {0, 1.7}, {2, 0}, "confirm", "Yes, delete it"},	
		{"button_exit", {2, 1.7}, {2, 0}, "deny", "No, don't delete it"},
	}
	return tpad.table_to_formspec(formtable)
end

-- prepare the list of stations to be shown in the main dialog
function tpad.get_padlist(ownername)
	local pads = tpad._get_stored_pads(ownername)
	local result = {}
	for strpos, padname in pairs(pads) do
		table.insert(result, minetest.formspec_escape(padname .. " " .. strpos))
	end
	table.sort(result)
	return result
end

-- used by the main dialog to pair up chosen station with stored pads
function tpad.get_pad_by_index(ownername, index)
	local pads = tpad._get_stored_pads(ownername)
	local padlist = tpad.get_padlist(ownername)
	local chosen = padlist[index]
	if not chosen then return end
	for strpos, padname in pairs(pads) do
		if chosen == minetest.formspec_escape(padname .. " " .. strpos) then
			return {
				pos = minetest.string_to_pos(strpos),
				name = padname .. " " .. strpos,
			}
		end
	end
end

function tpad.get_pad_name(pos)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	local pads = tpad._get_stored_pads(ownername)
	return pads[minetest.pos_to_string(pos)] or ""
end

function tpad.set_pad_name(pos, name)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	local pads = tpad._get_stored_pads(ownername)
	pads[minetest.pos_to_string(pos)] = name
	tpad._set_stored_pads(ownername, pads)
end

function tpad.del_pad(ownername, pos)
	local pads = tpad._get_stored_pads(ownername)
	pads[minetest.pos_to_string(pos)] = nil
	tpad._set_stored_pads(ownername, pads)
end

-- ========================================================================
-- register node and bind callbacks
-- ========================================================================

minetest.register_node("tpad:tpad", {
	tiles = {tpad.tile_image},
	drawtype = "signlike",
	paramtype = "light",
	paramtype2 = "wallmounted",
	walkable = false,
	description = "Teleporter Pad",
	inventory_image = tpad.tile_image,
	groups = {choppy = 2, dig_immediate = 2},
	selection_box = { type = "wallmounted"},
	on_construct = tpad.on_construct,
	after_place_node = tpad.after_place_node,
	on_rightclick = tpad.on_rightclick,
	can_dig = tpad.can_dig,
	on_destruct = tpad.on_destruct,
})

minetest.register_on_player_receive_fields(tpad.on_receive_fields)

minetest.register_chatcommand("tpad", {func = tpad.command})
