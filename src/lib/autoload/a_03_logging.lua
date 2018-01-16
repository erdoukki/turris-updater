--[[
Copyright 2016, CZ.NIC z.s.p.o. (http://www.nic.cz/)

This file is part of the turris updater.

Updater is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Updater is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Updater.  If not, see <http://www.gnu.org/licenses/>.
]]--

-- Generate appropriate logging functions
for _, name in ipairs({ 'ERROR', 'WARN', 'INFO', 'DBG', 'TRACE' }) do
	_G[name] = function(...)
		log(name, 1, ...)
	end
end

-- The DIE function (which should really terminate, not just throw)
function DIE(...)
	log('DIE', 1, ...)
	os.exit(1)
end

function log_event(action, package)
	if state_log_enabled() then
		local f = io.open("/tmp/update-state/log2", "a")
		if f then
			f:write(action, " ", package, "\n")
			f:close()
		end
	end
end

-- Function used from C to generate message from error
function c_pcall_error_handler(err)
	local function err2string(msg, err)
		if type(err) == "string" then
			msg = msg .. "\n" .. err
		elseif err.tp == "error" then
			msg = msg .. "\n" .. err.reason .. ": " .. err.msg
		else
			error(utils.exception("Unknown error", "Unknown error"))
		end
		return msg
	end

	local msg = ""
	if (err.errors) then -- multiple errors
		for _, merr in pairs(err.errors) do
			msg = err2string(msg, merr)
		end
	else
		msg = err2string(msg, err)
	end
	return {msg=msg, trace=stacktraceplus.stacktrace()}
end


-- BB extended logging, support for console UI

-- support functions
function split(s, delimiter)
	local result = {};
	for match in (s..delimiter):gmatch("(.-)"..delimiter) do
		table.insert(result, match);
	end
	return result;
end

local csi = "\27["

function set_cursor(row, col)
	io.write(csi .. row .. ";" .. col .. "H")
end

function reset_colors()
	io.write(csi .. "m")
end

function save_cursor()
	io.write(csi .. "s")
end

function restore_cursor()
	io.write(csi .. "u")
end

function show_progress(message, value)
	-- setup variables
	local size = get_screen_size()
	local row = size[1]
	local col = size[2]
	-- clear previous line
	save_cursor()
	set_cursor(row,1)		-- move to last line
	io.write(csi .. "1T")	-- scroll down
	io.write(csi .. "1S") 	-- scroll up (should clear, IMO)
	set_cursor(row,1)		-- move to last line
	INFO(message)
--	io.write("\n")
--	io.write(csi .. "1T")	-- scroll down
--	set_cursor(row - 1,1)
--	io.write(csi .. "2K")
	set_cursor(row,1)
	local length = ((math.floor(value * col)) - 5) / 2
	local bar = "["
	for i = 1, length do bar = bar .. "=" end
	bar = bar .. math.floor(100 * value) .. "%"
	for i = 1, length do bar = bar .. "=" end
	io.write(bar .. "]")
	restore_cursor()
end

function get_screen_size()
-- read size
	local handle = io.popen('stty size')
	local result = handle:read("*a")
	handle:close()
-- convert size to array
	result = result:gsub("\n", "")
	return split(result, " ")
end

--[[
	save_cursor()
	set_cursor(1,1)
	print('This is red->\27[31mred\n')
	reset_colors()
	restore_cursor()
	
	for i = 0, 1, 0.0001 do show_progress(i) end
]]
