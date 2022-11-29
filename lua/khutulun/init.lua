local M = {}

local default_config = {
	mv = function(source, target)
		return os.rename(source, target)
	end,
	bdelete = function()
		vim.cmd("bdelete")
	end,
	delete = function(current_file)
		return os.remove(current_file)
	end,
	confirm_delete = true,
}
local config

local path_sep = "/"

local log_error = vim.log.levels.ERROR

local function create_dir(new_dir)
	if vim.fn.isdirectory(new_dir) == 0 then
		local success, errormsg = pcall(vim.fn.mkdir, new_dir, "p")
		if success then
			vim.notify(string.format(" Created directory %q", new_dir))
		else
			vim.notify(" Could not create directory: " .. errormsg, log_error)
			return false
		end
	end
	return true
end

local function ensure_dir(target)
	local new_dir = vim.fn.fnamemodify(target, ":h")
	return create_dir(new_dir)
end

local function mv(target)
	vim.cmd("update") -- save current file; needed for users with `vim.opt.hidden=false`
	if not ensure_dir(target) then
		return
	end

	local source = vim.fn.expand("%:.")
	local success, errormsg
	success, errormsg = config.mv(source, target)
	if not success then
		vim.notify(" Could not rename file: " .. errormsg, log_error)
		return false
	end

	local win = vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(win)
	vim.cmd({ cmd = "edit", args = { target } })
	vim.api.nvim_buf_delete(bufnr, {})
	return true
end

function M.rename()
	local source = vim.fn.expand("%:.")
	vim.ui.input({ prompt = "rename", default = source }, function(target)
		if target == nil or target == "" or target == source then
			return
		end
		if mv(target) then
			vim.notify(string.format(" Renamed %q to %q. ", source, target))
		end
	end)
end

function M.move()
	local dirs
	local source = vim.fn.expand("%:.")
	if vim.fn.executable("fd") then
		local cmd = { "fd", "--type", "directory" }
		dirs = vim.fn.systemlist(cmd)
		if vim.v.shell_error ~= 0 then
			error(table.concat(dirs, "\n"))
		end
		dirs = vim.tbl_map(function(dir)
			return dir:sub(1, dir:len() - 1):sub(3)
		end, dirs)
	elseif vim.fn.executable("find") then
		local cmd = { "find", "-type", "d" }
		dirs = vim.fn.systemlist(cmd)
		if vim.v.shell_error ~= 0 then
			error(table.concat(dirs, "\n"))
		end
		table.remove(dirs, 1)
		dirs = vim.tbl_map(function(dir)
			return dir:sub(3)
		end, dirs)
	else
		vim.notify("Move needs an executable fd or find command", log_error)
		return
	end

	table.insert(dirs, 1, ".")
	vim.ui.select(dirs, { prompt = "Move to" }, function(dir)
		if dir and dir ~= "" then
			local target
			if dir == "." then
				target = vim.fn.expand("%:t")
			else
				target = dir .. path_sep .. vim.fn.expand("%:t")
			end
			if target ~= source and mv(target) then
				vim.notify(string.format(" Moved %q to %q. ", source, dir))
			end
		end
	end)
end

function M.duplicate()
	local source = vim.fn.expand("%:.")
	vim.ui.input({ prompt = "duplicate", default = source }, function(target)
		if target ~= nil and target ~= source then
			if vim.endswith(target, "/") or vim.endswith(target, "\\") or vim.fn.isdirectory(target) == 0 then
				target = target .. vim.fn.expand("%:t")
			end
			if ensure_dir(target) then
				vim.cmd({ cmd = "saveas", args = { target } })
				vim.cmd({ cmd = "edit", args = { target } })
			end
		end
	end)
end

function M.create()
	local source = vim.fn.expand("%:.")
	vim.ui.input({ prompt = "edit", default = source }, function(target)
		if target ~= nil and target ~= source and ensure_dir(target) then
			if vim.endswith(target, "/") or vim.endswith(target, "\\") then
				create_dir(target)
			else
				vim.cmd({ cmd = "edit", args = { target } })
			end
		end
	end)
end

local function leave_visual_mode()
	-- https://github.com/neovim/neovim/issues/17735#issuecomment-1068525617
	local esc_key = vim.api.nvim_replace_termcodes("<Esc>", false, true, true)
	vim.api.nvim_feedkeys(esc_key, "nx", false)
end

function M.create_from_selection()
	local source = vim.fn.expand("%:.")
	vim.ui.input({ prompt = "create from selection", default = source }, function(target)
		if target ~= nil and target ~= source and ensure_dir(target) then
			local prev_reg = vim.fn.getreg("z")
			leave_visual_mode()
			vim.cmd([['<,'>delete z]])
			vim.cmd({ cmd = "edit", args = { target } })
			vim.cmd("put z")
			vim.fn.setreg("z", prev_reg) -- restore register content
		end
	end)
end

local function delete()
	local current_file = vim.fn.expand("%:p")
	local filename = vim.fn.expand("%:t")
	local success, errormsg = config.delete(current_file)
	if success then
		config.bdelete()
		vim.notify(string.format("%q deleted.", filename))
	else
		vim.notify(" Could not delete file: " .. errormsg, log_error)
	end
end

function M.delete()
	if config.confirm_delete then
		vim.ui.input({ prompt = string.format("Delete %q (y/n)?", vim.fn.expand("%")) }, function(res)
			if res == "y" then
				delete()
			end
		end)
	else
		delete()
	end
end

function M.chmodx()
	local filename = vim.fn.expand("%")
	local perm = vim.fn.getfperm(filename)
	perm = perm:gsub("r(.)%-", "r%1x") -- add x to every group that has r
	vim.fn.setfperm(filename, perm)
end

---yanking file information
---@param operation string filename|filepath
local function yank_op(operation)
	local reg = '"'
	local clipboard_opt = vim.opt.clipboard:get()
	local use_system_clipboard = #clipboard_opt > 0 and clipboard_opt[1]:find("unnamed")
	if use_system_clipboard then
		reg = "+"
	end

	local to_yank = vim.fn.expand("%:p")
	if operation == "filename" then
		to_yank = vim.fn.expand("%:t")
	end

	vim.fn.setreg(reg, to_yank)
	vim.notify("YANKED \n " .. to_yank)
end

---Copy absolute path of current file
function M.yank_filepath()
	yank_op("filepath")
end

---Copy name of current file
function M.yank_filename()
	yank_op("filename")
end

function M.setup(user_config)
	config = vim.tbl_deep_extend("force", default_config, user_config or {})
end

return M
