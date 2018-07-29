tpad = {}
tpad.version = "1.2"
tpad.mod_name = minetest.get_current_modname()
tpad.texture = "tpad-texture.png"
tpad.mesh = "tpad-mesh.obj"
tpad.nodename = "tpad:tpad"
tpad.mod_path = minetest.get_modpath(tpad.mod_name)
tpad.settings_file = minetest.get_worldpath() .. "/mod_storage/" .. tpad.mod_name .. ".custom.conf"

local PRIVATE_PAD_STRING = "Private (only owner)"
local  PUBLIC_PAD_STRING = "Public (only owner's network)"
local  GLOBAL_PAD_STRING = "Global (any network)"

local PRIVATE_PAD = 1
local  PUBLIC_PAD = 2
local  GLOBAL_PAD = 4

local RED_ESCAPE = minetest.get_color_escape_sequence("#FF0000")
local GREEN_ESCAPE = minetest.get_color_escape_sequence("#00FF00")
local BLUE_ESCAPE = minetest.get_color_escape_sequence("#0000FF")
local YELLOW_ESCAPE = minetest.get_color_escape_sequence("#FFFF00")
local CYAN_ESCAPE = minetest.get_color_escape_sequence("#00FFFF")
local MAGENTA_ESCAPE = minetest.get_color_escape_sequence("#FF00FF")
local WHITE_ESCAPE = minetest.get_color_escape_sequence("#FFFFFF")

local OWNER_ESCAPE_COLOR = CYAN_ESCAPE

local padtype_flag_to_string = {
	[PRIVATE_PAD] = PRIVATE_PAD_STRING,
	 [PUBLIC_PAD] =  PUBLIC_PAD_STRING,
	 [GLOBAL_PAD] =  GLOBAL_PAD_STRING,
}

local padtype_string_to_flag = {
	[PRIVATE_PAD_STRING] = PRIVATE_PAD,
	 [PUBLIC_PAD_STRING] =  PUBLIC_PAD,
	 [GLOBAL_PAD_STRING] =  GLOBAL_PAD,
}

local short_padtype_string = {
	[PRIVATE_PAD] = "private",
	 [PUBLIC_PAD] = "public",
	 [GLOBAL_PAD] = "global",
}

local smartfs = dofile(tpad.mod_path .. "/lib/smartfs.lua")
local notify = dofile(tpad.mod_path .. "/notify.lua")

-- workaround storage to tell the main dialog about the last clicked pad
local last_clicked_pos = {}

-- workaround storage to tell the main dialog about last selected pad in the lists
local last_selected_index = {}
local last_selected_global_index = {}

-- memory of shown waypoints
local waypoint_hud_ids = {}

minetest.register_privilege("tpad_admin", {
	description = "Can edit and destroy any tpad",
	give_to_singleplayer = true,
})

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
		notify(playername, "Waypoint to " .. closest_pad.name .. " displayed")
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
	if tpad.max_total_pads_reached(placer) then
		notify.warn(placer, "You can't place any more pads")
		return itemstack
	end
	local pos = tpad.get_pos_from_pointed(pointed_thing) or {}
	itemstack = minetest.rotate_node(itemstack, placer, pointed_thing)
	local placed = minetest.get_node_or_nil(pos)
	if placed and placed.name == tpad.nodename then		
		local meta = minetest.env:get_meta(pos)
		local playername = placer:get_player_name()
		meta:set_string("owner", playername)
		meta:set_string("infotext", "TPAD Station by " .. playername .. " - right click to interact")
		tpad.set_pad_data(pos, "", PRIVATE_PAD_STRING)
	end
	return itemstack
end

local submit = {}

function tpad.set_max_total_pads(max)
	if not max then max = 0 end
	local settings = Settings(tpad.settings_file)
	settings:set("max_total_pads_per_player", max)
	settings:write()
end

function tpad.get_max_total_pads()
	local settings = Settings(tpad.settings_file)
	local max = tonumber(settings:get("max_total_pads_per_player"))
	if not max then
		tpad.set_max_total_pads(100)
		return 100
	end
	return max
end
tpad.get_max_total_pads()

function tpad.set_max_global_pads(max)
	if not max then max = 0 end
	local settings = Settings(tpad.settings_file)
	settings:set("max_global_pads_per_player", max)
	settings:write()
end

function tpad.get_max_global_pads()
	local settings = Settings(tpad.settings_file)
	local max = tonumber(settings:get("max_global_pads_per_player"))
	if not max then
		tpad.set_max_global_pads(4)
		return 4
	end
	return max
end
tpad.get_max_global_pads()

function tpad.max_total_pads_reached(placer)
	local placername = placer:get_player_name()
	if minetest.get_player_privs(placername).tpad_admin then
		return false
	end
	local localnet = submit.local_helper(placername)
	return #localnet.by_index >= tpad.get_max_total_pads()
end

function tpad.max_global_pads_reached(playername)
	if minetest.get_player_privs(playername).tpad_admin then
		return false
	end
	local localnet = submit.local_helper(playername)
	local count = 0
	for _, pad in pairs(localnet.by_name) do
		if pad.type == GLOBAL_PAD then
			count = count + 1
		end
	end
	return count >= tpad.get_max_global_pads()
end

function submit.global_helper()
	local allpads = tpad._get_all_pads()
	local result = {
		by_name = {},
		by_index = {},
	}
	for ownername, pads in pairs(allpads) do
		for strpos, pad in pairs(pads) do
			if pad.type == GLOBAL_PAD then
				pad = tpad.decorate_pad_data(strpos, pad, ownername)
				table.insert(result.by_index, pad.global_fullname)
				result.by_name[pad.global_fullname] = pad
			end
		end
	end	
	table.sort(result.by_index)
	return result
end

function submit.local_helper(ownername, omit_private_pads)
	local pads = tpad._get_stored_pads(ownername)
	local result = {
		by_name = {},
		by_index = {},
	}
	for strpos, pad in pairs(pads) do
		local skip = omit_private_pads and pad.type == PRIVATE_PAD
		if not skip then
			pad = tpad.decorate_pad_data(strpos, pad, ownername)
			table.insert(result.by_index, pad.local_fullname)
			result.by_name[pad.local_fullname] = pad
		end
	end
	table.sort(result.by_index)
	return result
end

function submit.save(form)
	if form.playername ~= form.ownername and not minetest.get_player_privs(form.playername).tpad_admin then
		notify.warn(form.playername, "The selected pad doesn't belong to you")
		return
	end
	local padname = form.state:get("padname_field"):getText()
	local strpadtype = form.state:get("padtype_dropdown"):getSelectedItem()
	if strpadtype == GLOBAL_PAD_STRING and tpad.max_global_pads_reached(form.playername) then
		notify.warn(form.playername, "Can't add more pads to the Global Network, set to 'Public' instead")
		strpadtype = PUBLIC_PAD_STRING
	end
	tpad.set_pad_data(form.clicked_pos, padname, strpadtype)
end

function submit.teleport(form)
	local pads_listbox = form.state:get("pads_listbox")
	local selected_item = pads_listbox:getSelectedItem()
	local pad
	if form.globalnet then
		pad = form.globalnet.by_name[selected_item]
	else
		pad = form.localnet.by_name[selected_item]
	end
	if not pad then
		notify.err(form.playername, "Error! Missing pad data!")
		return
	end
	local player = minetest.get_player_by_name(form.playername)
	player:moveto(pad.pos, false)
	
	local padname = form.globalnet and pad.global_fullname or pad.local_fullname
	notify(form.playername, "Teleported to " .. padname)
	
	tpad.hud_off(form.playername)
	minetest.after(0, function()
		minetest.close_formspec(form.playername, form.formname)
	end)
end

function submit.admin(form)
	form.state = tpad.forms.admin:show(form.playername)
	form.formname = "tpad.forms.admin"
	
	local max_total_field = form.state:get("max_total_field")
	max_total_field:setText(tpad.get_max_total_pads())
	
	local max_global_field = form.state:get("max_global_field")
	max_global_field:setText(tpad.get_max_global_pads())

	local function admin_save()
		local max_total = tonumber(max_total_field:getText())
		local max_global = tonumber(max_global_field:getText())
		tpad.set_max_total_pads(max_total)
		tpad.set_max_global_pads(max_global)
		minetest.after(0, function()
			minetest.close_formspec(form.playername, form.formname)
		end)
	end
	max_total_field:onKeyEnter(admin_save)
	max_total_field:onKeyEnter(admin_save)	
	form.state:get("save_button"):onClick(admin_save)
end

function submit.global(form)
	if minetest.get_player_privs(form.playername).tpad_admin then
		form.state = tpad.forms.global_network_admin:show(form.playername)
		form.formname = "tpad.forms.global_network_admin"
		form.state:get("admin_button"):onClick(function()
			minetest.after(0, function()
				submit.admin(form)
			end)
		end)
	else
		form.state = tpad.forms.global_network:show(form.playername)
		form.formname = "tpad.forms.global_network"
	end
	
	form.globalnet = submit.global_helper()

	local last_index = last_selected_global_index[form.playername]
	local pads_listbox = form.state:get("pads_listbox")
	
	pads_listbox:clearItems()
	for _, pad_item in ipairs(form.globalnet.by_index) do
		pads_listbox:addItem(pad_item)
	end
	
	pads_listbox:setSelected(last_index)
	pads_listbox:onClick(function()
		last_selected_global_index[form.playername] = pads_listbox:getSelected()
	end)
	
	pads_listbox:onDoubleClick(function() submit.teleport(form) end)
	form.state:get("teleport_button"):onClick(function() submit.teleport(form) end)

	form.state:get("local_button"):onClick(function() 
		minetest.after(0, function()
			tpad.on_rightclick(form.clicked_pos, form.node, form.clicker)
		end)
	end)
end

function submit.delete(form)
	minetest.after(0, function()
		local pads_listbox = form.state:get("pads_listbox")
		local selected_item = pads_listbox:getSelectedItem()
		local delete_pad = form.localnet.by_name[selected_item]
		
		if not delete_pad then
			notify.warn(form.playername, "Please select a pad first")
			return
		end
		
		if form.playername ~= form.ownername and not minetest.get_player_privs(form.playername).tpad_admin then
			notify.warn(form.playername, "The selected pad doesn't belong to you")
			return
		end
		
		if minetest.pos_to_string(delete_pad.pos) == minetest.pos_to_string(form.clicked_pos) then
			notify.warn(form.playername, "You can't delete the current pad, destroy it manually")
			return
		end
		
		local function reshow_main()
			minetest.after(0, function()
				tpad.on_rightclick(form.clicked_pos, form.node, minetest.get_player_by_name(form.playername))
			end)
		end

		local delete_state = tpad.forms.confirm_pad_deletion:show(form.playername)
		delete_state:get("padname_label"):setText(
			YELLOW_ESCAPE .. delete_pad.local_fullname ..
			WHITE_ESCAPE .. " by " ..
			OWNER_ESCAPE_COLOR .. form.ownername
		)
		
		local confirm_button = delete_state:get("confirm_button")
		confirm_button:onClick(function()
			last_selected_index[form.playername .. ":" .. form.ownername] = nil
			tpad.del_pad(form.ownername, delete_pad.pos)
			minetest.remove_node(delete_pad.pos)
			notify(form.playername, "Pad " .. delete_pad.local_fullname .. " destroyed")
			reshow_main()
		end)
		
		local deny_button = delete_state:get("deny_button")
		deny_button:onClick(reshow_main)
	end)
end

function tpad.on_rightclick(clicked_pos, node, clicker)
	local playername = clicker:get_player_name()
	local clicked_meta = minetest.env:get_meta(clicked_pos)
	local ownername = clicked_meta:get_string("owner")
	local pad = tpad.get_pad_data(clicked_pos)
	
	if not pad or not ownername then
		notify.err(playername, "Error! Missing pad data!")
		return
	end
	
	local form = {}
	
	form.playername = playername
	form.clicker = clicker
	form.ownername = ownername
	form.clicked_pos = clicked_pos
	form.node = node
	form.omit_private_pads = false
	
	last_clicked_pos[playername] = clicked_pos;
	if ownername == playername or minetest.get_player_privs(playername).tpad_admin then
		form.formname = "tpad.forms.main_owner"
		form.state = tpad.forms.main_owner:show(playername)
		local padname_field = form.state:get("padname_field")
		padname_field:setLabel("This pad name (owned by " .. OWNER_ESCAPE_COLOR .. ownername .. WHITE_ESCAPE .. ")")
		padname_field:setText(pad.name)
		padname_field:onKeyEnter(function() submit.save(form) end)
		form.state:get("save_button"):onClick(function() submit.save(form) end)
		form.state:get("delete_button"):onClick(function() submit.delete(form) end)
		form.state:get("padtype_dropdown"):setSelectedItem(padtype_flag_to_string[pad.type])
	elseif pad.type == PRIVATE_PAD then
		notify.warn(playername, "This pad is private")
		return
	else
		form.omit_private_pads = true
		form.formname = "tpad.forms.main_visitor"
		form.state = tpad.forms.main_visitor:show(playername)
		form.state:get("visitor_label"):setText("Pad \"" .. pad.name .. "\", owned by " .. OWNER_ESCAPE_COLOR .. ownername)
	end

	form.localnet = submit.local_helper(ownername, form.omit_private_pads)
	
	local last_click_key = playername .. ":" .. ownername
	local last_index = last_selected_index[last_click_key]

	local pads_listbox = form.state:get("pads_listbox")
	pads_listbox:clearItems()
	for _, pad_item in ipairs(form.localnet.by_index) do
		pads_listbox:addItem(pad_item)
	end
	pads_listbox:setSelected(last_index)
	pads_listbox:onClick(function()
		last_selected_index[last_click_key] = pads_listbox:getSelected()
	end)
	
	pads_listbox:onDoubleClick(function() submit.teleport(form) end)
	form.state:get("teleport_button"):onClick(function() submit.teleport(form) end)
	form.state:get("global_button"):onClick(function() 
		minetest.after(0, function()
			submit.global(form)
		end)
	end)
	
end

function tpad.can_dig(pos, player)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	local playername = player:get_player_name()
	if ownername == "" or ownername == nil or playername == ownername 
			or minetest.get_player_privs(playername).tpad_admin then 
		return true
	end
	notify.warn(playername, "This pad doesn't belong to you")
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

local function forms_add_padlist(state, is_global)
	local pads_listbox = state:listbox(0.2, 2.4, 7.6, 4, "pads_listbox", {})	
	local teleport_button = state:button(0.2, 7, 1.5, 0, "teleport_button", "Teleport")
	local close_button = state:button(6.5, 7, 1.5, 0, "close_button", "Close")
	close_button:setClose(true)	
	if is_global then
		local local_button = state:button(1.8, 7, 2.5, 0, "local_button", "Local Network")
		local_button:setClose(true)
	else
		local global_button = state:button(1.8, 7, 2.5, 0, "global_button", "Global Network")
		global_button:setClose(true)
	end
	state:label(0.2, 7.5, "teleport_label", "(you can doubleclick on a pad to teleport)")
end

tpad.forms.main_owner = smartfs.create("tpad.forms.main_owner", function(state)
	state:size(8, 8);
	state:field(0.5, 1, 6, 0, "padname_field", "", "")
	local save_button = state:button(6.5, 0.7, 1.5, 0, "save_button", "Save")
	save_button:setClose(true)

	local padtype_dropdown = state:dropdown(0.2, 1.2, 6.4, 0, "padtype_dropdown")
	padtype_dropdown:addItem(PRIVATE_PAD_STRING)
	padtype_dropdown:addItem(PUBLIC_PAD_STRING)
	padtype_dropdown:addItem(GLOBAL_PAD_STRING)

	local delete_button = state:button(4.4, 7, 1.5, 0, "delete_button", "Delete")

	forms_add_padlist(state)
end)

tpad.forms.main_visitor = smartfs.create("tpad.forms.main_visitor", function(state)
	state:size(8, 8)
	state:label(0.2, 1, "visitor_label", "")
	forms_add_padlist(state)
end)

tpad.forms.confirm_pad_deletion = smartfs.create("tpad.forms.confirm_pad_deletion", function(state)
	state:size(8, 2.5)
	state:label(0, 0, "intro_label", "Are you sure you want to destroy pad")
	state:label(0, 0.5, "padname_label", "")
	state:label(0, 1, "outro_label", "(you will not get the pad back)")
	state:button(0, 2.2, 2, 0, "confirm_button", "Yes, delete it")
	state:button(6, 2.2, 2, 0, "deny_button", "No, keep it")
end)

tpad.forms.global_network = smartfs.create("tpad.forms.global_network", function(state)
	state:size(8, 8)
	state:label(0.2, 1, "visitor_label", "Pick a pad from the Global Pads Network")
	local is_global = true
	forms_add_padlist(state, is_global)
end)

tpad.forms.global_network_admin = smartfs.create("tpad.forms.global_network_admin", function(state)
	state:size(8, 8)
	state:label(0.2, 1, "visitor_label", "Pick a pad from the Global Pads Network")
	local admin_button = state:button(4.4, 7, 1.5, 0, "admin_button", "Admin")
	admin_button:setClose(true)
	local is_global = true
	forms_add_padlist(state, is_global)
end)

tpad.forms.admin = smartfs.create("tpad.forms.admin", function(state)
	state:size(8, 8)
	state:label(0.2, 0.2, "admin_label", "TPAD Settings")
	state:field(0.5, 2, 6, 0, "max_total_field", "Max total pads per player")
	state:field(0.5, 3.5, 6, 0, "max_global_field", "Max global pads per player")
	local save_button = state:button(6.5, 0.7, 1.5, 0, "save_button", "Save")
	save_button:setClose(true)
	local close_button = state:button(6.5, 7, 1.5, 0, "close_button", "Close")
	close_button:setClose(true)	
end)

-- ========================================================================
-- helper functions
-- ========================================================================

function tpad.decorate_pad_data(pos, pad, ownername)
	pad = table.copy(pad)
	if type(pos) == "string" then
		pad.strpos = pos
		pad.pos = minetest.string_to_pos(pos)
	else
		pad.pos = pos
		pad.strpos = minetest.pos_to_string(pos)
	end
	pad.owner = ownername
	pad.name = pad.name or ""
	pad.type = pad.type or PUBLIC_PAD
	pad.local_fullname = pad.name .. " " .. pad.strpos .. " " .. short_padtype_string[pad.type]
	pad.global_fullname = "[" .. ownername .. "] " .. pad.name .. " " .. pad.strpos
	return pad
end

function tpad.get_pad_data(pos)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	local pads = tpad._get_stored_pads(ownername)
	local strpos = minetest.pos_to_string(pos)
	local pad = pads[strpos]
	if not pad then return end
	return tpad.decorate_pad_data(pos, pad, ownername)
end

function tpad.set_pad_data(pos, padname, padtype)
	local meta = minetest.env:get_meta(pos)
	local ownername = meta:get_string("owner")
	local pads = tpad._get_stored_pads(ownername)
	local strpos = minetest.pos_to_string(pos)
	local pad = pads[strpos]
	if not pad then
		pad = {}
	end
	pad.name = padname
	pad.type = padtype_string_to_flag[padtype]
	pads[strpos] = pad
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
	paramtype = "light",	
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
