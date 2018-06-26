tpad = {}
tpad.version = "1.2"
tpad.mod_name = minetest.get_current_modname()
tpad.texture = "tpad-texture.png"
tpad.mesh = "tpad-mesh.obj"
tpad.nodename = "tpad:tpad"
tpad.mod_path = minetest.get_modpath(tpad.mod_name)

local smartfs = dofile(tpad.mod_path .. "/lib/smartfs.lua")

-- workaround storage to tell the main dialog about the last clicked pad
local last_clicked_pos = {}

-- workaround storage to tell the main dialog about last selected station in the list
local last_selected_index = {}

-- memory of shown waypoints
local waypoint_hud_ids = {}

-- ========================================================================
-- local helpers
-- ========================================================================

local function copy_file(source, dest)
	local src_file = io.open(source, "rb")
	if not src_file then 
		return false, "copy_file() unable to open source for reading"
	end
	local src_data = src_file:read("*all")
	src_file:close()

	local dest_file = io.open(dest, "wb")
	if not dest_file then 
		return false, "copy_file() unable to open dest for writing"
	end
	dest_file:write(src_data)
	dest_file:close()
	return true, "files copied successfully"
end

-- alias to make copy_file() available to storage.lua
tpad._copy_file = copy_file

local function custom_or_default(modname, path, filename)
	local default_filename = "default/" .. filename
	local full_filename = path .. "/custom." .. filename
	local full_default_filename = path .. "/" .. default_filename
	
	os.rename(path .. "/" .. filename, full_filename)
	
	local file = io.open(full_filename, "rb")
	if not file then
		minetest.debug("[" .. modname .. "] Copying " .. default_filename .. " to " .. filename .. " (path: " .. path .. ")")
		local success, err = copy_file(full_default_filename, full_filename)
		if not success then
			minetest.debug("[" .. modname .. "] " .. err)
			return false
		end
		file = io.open(full_filename, "rb")
		if not file then
			minetest.debug("[" .. modname .. "] Unable to load " .. filename .. " file from path " .. path)
			return false
		end
	end
	file:close()
	return full_filename
end

-- load storage facilities and verify it
dofile(tpad.mod_path .. "/storage.lua")

-- ========================================================================
-- load custom recipe
-- ========================================================================

local recipes_filename = custom_or_default(tpad.mod_name, tpad.mod_path, "recipes.lua")
if recipes_filename then
	local recipes = dofile(recipes_filename)	
	if type(recipes) == "table" and recipes[tpad.nodename] then
		minetest.register_craft({
			output = tpad.nodename,
			recipe = recipes[tpad.nodename],
		})
	end
end

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
	for strpos, pad in pairs(pads) do
		local pos = minetest.string_to_pos(strpos)
		local distance = vector.distance(pos, playerpos)
		if not shortest_distance or distance < shortest_distance then
			closest_pad = {
				pos = pos,
				name = pad.name .. " " .. strpos,
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
-- callbacks bound in register_node()
-- ========================================================================

function tpad.get_pos_from_pointed(pointed)
	local node_above = minetest.get_node_or_nil(pointed.above)
	local node_under = minetest.get_node_or_nil(pointed.under)
	
	if not node_above or not node_under then return end
	
	local def_above = minetest.registered_nodes[node_above.name]
						or minetest.nodedef_default
	local def_under = minetest.registered_nodes[node_under.name]
						or minetest.nodedef_default
	
	if not def_above.buildable_to and not def_under.buildable_to then return end
	
	if def_under.buildable_to then
		return pointed.under
	end
	
	return pointed.above
end

function tpad.on_place(itemstack, placer, pointed_thing)
	local pos = tpad.get_pos_from_pointed(pointed_thing) or {}
	itemstack = minetest.rotate_node(itemstack, placer, pointed_thing)
	local placed = minetest.get_node_or_nil(pos)
	if placed and placed.name == tpad.nodename then		
		local meta = minetest.env:get_meta(pos)
		local playername = placer:get_player_name()
		meta:set_string("owner", playername)
		meta:set_string("infotext", "Tpad Station by " .. playername .. " - right click to interact")
		tpad.set_pad_name(pos, "")
	end
	return itemstack
end

function tpad.on_rightclick(clicked_pos, node, clicker)
	local playername = clicker:get_player_name()
	local clicked_meta = minetest.env:get_meta(clicked_pos)
	local ownername = clicked_meta:get_string("owner")
	local padname = tpad.get_pad_name(clicked_pos)
	local padlist = tpad.get_padlist(ownername)
	local last_index = last_selected_index[playername .. ":" .. ownername]
	local state
	local formname
	local pads_listbox
	last_clicked_pos[playername] = clicked_pos;
	
	local function save()
		if playername ~= ownername then
			minetest.chat_send_player(playername, "Tpad: the selected pad doesn't belong to you")
			return
		end
		tpad.set_pad_name(clicked_pos, state:get("padname_field"):getText())
	end

	local function teleport()
		local selected_index = pads_listbox:getSelected()
		local pad = tpad.get_pad_by_index(ownername, selected_index)
		local player = minetest.get_player_by_name(playername)
		player:moveto(pad.pos, false)
		minetest.chat_send_player(playername, "Tpad: Teleported to " .. pad.name)
		tpad.hud_off(playername)
		minetest.after(0, function()
			minetest.close_formspec(playername, formname)
		end)
	end

	local function delete()
		minetest.after(0, function()
			local delete_pad = tpad.get_pad_by_index(ownername, pads_listbox:getSelected())
			
			if not delete_pad then
				minetest.chat_send_player(playername, "Tpad: Please select a station first")
				return
			end
			
			if playername ~= ownername then
				minetest.chat_send_player(playername, "Tpad: the selected pad doesn't belong to you")
				return
			end
			
			if minetest.pos_to_string(delete_pad.pos) == minetest.pos_to_string(clicked_pos) then
				minetest.chat_send_player(playername, "Tpad: You can't delete the current pad, destroy it manually")
				return
			end
			
			local function reshow_main()
				minetest.after(0, function()
					tpad.on_rightclick(clicked_pos, node, minetest.get_player_by_name(playername))
				end)
			end

			local delete_state = tpad.forms.confirm_pad_deletion:show(playername)
			delete_state:get("padname_label"):setText("Are you sure you want to destroy \"" .. delete_pad.name .. "\" station?")
			
			local confirm_button = delete_state:get("confirm_button")
			confirm_button:onClick(function()
				last_selected_index[playername .. ":" .. ownername] = nil
				tpad.del_pad(ownername, delete_pad.pos)
				minetest.remove_node(delete_pad.pos)
				minetest.chat_send_player(playername, "Tpad: station " .. delete_pad.name .. " destroyed")
				reshow_main()
			end)
			
			local deny_button = delete_state:get("deny_button")
			deny_button:onClick(reshow_main)
		end)
	end
	
	if ownername == playername then
		formname = "tpad.forms.main_owner"
		state = tpad.forms.main_owner:show(playername)
		state:get("padname_field"):setText(padname)
		state:get("padname_field"):onKeyEnter(save)
		state:get("save_button"):onClick(save)		
		state:get("delete_button"):onClick(delete)
	else
		formname = "tpad.forms.main_visitor"
		state = tpad.forms.main_visitor:show(playername)
		state:get("visitor_label"):setText("Station \"" .. padname .. "\", owned by " .. ownername)
	end

	pads_listbox = state:get("pads_listbox")
	pads_listbox:clearItems()
	for _, pad_item in ipairs(padlist) do
		pads_listbox:addItem(pad_item)
	end
	pads_listbox:setSelected(last_index)
	pads_listbox:onClick(function(state)
		last_selected_index[playername .. ":" .. ownername] = pads_listbox:getSelected()
	end)
	
	pads_listbox:onDoubleClick(teleport)
	state:get("teleport_button"):onClick(teleport)
	
end

function tpad.can_dig(pos, player)
	local meta = minetest.env:get_meta(pos)
	local owner = meta:get_string("owner")
	local playername = player:get_player_name()
	if owner == "" or owner == nil or playername == owner then 
		return true
	end
	minetest.chat_send_player(playername, "Tpad: You can't delete the current pad, destroy it manually")
	return false
end

function tpad.on_destruct(pos)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	tpad.del_pad(ownername, pos)
end

-- ========================================================================
-- forms
-- ========================================================================

tpad.forms = {}

local function form_main_common(state)
	local pads_listbox = state:listbox(0.2, 1.4, 7.5, 4, "pads_listbox", {})	
	local teleport_button = state:button(0.2, 6, 1.5, 0, "teleport_button", "Teleport")
	local close_button = state:button(6.5, 6, 1.5, 0, "close_button", "Close")
	close_button:setClose(true)	
	state:label(0.2, 6.5, "teleport_label", "(you can doubleclick on a station to teleport)")
end

tpad.forms.main_owner = smartfs.create("tpad.forms.main_owner", function(state)
	state:size(8, 7);
	state:field(0.5, 1, 6, 0, "padname_field", "This station name", "")
	local save_button = state:button(6.5, 0.7, 1.5, 0, "save_button", "Save")
	save_button:setClose(true)
	local delete_button = state:button(3, 6, 1.5, 0, "delete_button", "Delete")
	form_main_common(state)
end)

tpad.forms.main_visitor = smartfs.create("tpad.forms.main_visitor", function(state)
	state:size(8, 7)
	state:label(0.2, 0.5, "visitor_label", "")
	form_main_common(state)
end)

tpad.forms.confirm_pad_deletion = smartfs.create("tpad.forms.confirm_pad_deletion", function(state)
	state:size(5, 2)
	state:label(0, 0, "padname_label", "")
	state:label(0, 0.5, "notice_label", "(you will not get the pad back)")
	state:button(0, 1.7, 2, 0, "confirm_button", "Yes, delete it")
	state:button(2, 1.7, 2, 0, "deny_button", "deny", "No, don't delete it")
end)

-- ========================================================================
-- helper functions
-- ========================================================================

-- prepare the list of stations to be shown in the main dialog
function tpad.get_padlist(ownername)
	local pads = tpad._get_stored_pads(ownername)
	local result = {}
	for strpos, pad in pairs(pads) do
		table.insert(result, pad.name .. " " .. strpos)
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
	for strpos, pad in pairs(pads) do
		if chosen == pad.name .. " " .. strpos then
			return {
				pos = minetest.string_to_pos(strpos),
				name = pad.name .. " " .. strpos,
			}
		end
	end
end

function tpad.get_pad_name(pos)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	local pads = tpad._get_stored_pads(ownername)
	local strpos = minetest.pos_to_string(pos)
	local pad = pads[strpos]
	return pad and pad.name or ""
end

function tpad.set_pad_name(pos, name)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	local pads = tpad._get_stored_pads(ownername)
	local strpos = minetest.pos_to_string(pos)
	local pad = pads[strpos]
	if pad then
		pad.name = name
	else
		pads[strpos] = { name = name }
	end
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

local collision_box =  {
	type = "fixed",
	fixed = {
		{ -0.5,   -0.5,  -0.5,   0.5,  -0.3, 0.5 },
	}
}

minetest.register_node(tpad.nodename, {
	drawtype = "mesh",
	tiles = { tpad.texture },
	mesh = tpad.mesh,
	paramtype2 = "facedir",
	on_place = tpad.on_place,
	collision_box = collision_box,
	selection_box = collision_box,
	description = "Teleporter Pad",
	groups = {choppy = 2, dig_immediate = 2},
	on_rightclick = tpad.on_rightclick,
	can_dig = tpad.can_dig,
	on_destruct = tpad.on_destruct,
})

minetest.register_chatcommand("tpad", {func = tpad.command})
