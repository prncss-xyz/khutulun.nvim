local M = {}

-- TODO: express error message where it happens

local utils = require "khutulun.utils"

local path_sep = "/"

local log_error = vim.log.levels.ERROR

local function get_filepath(filepath)
	if filepath then
		return vim.fn.fnamemodify(filepath, "%")
	else
		return vim.fn.expand "%"
	end
end

function M.bdelete_by_path(target)
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local path = vim.api.nvim_buf_get_name(bufnr)
		if path == target then
			vim.api.nvim_buf_delete(bufnr, {})
		end
	end
end

-- FIXME: not working for unwritten buffer
function M.default_mv(source, target)
	local ok, errormsg = os.rename(source, target)
	if not ok then
		return ok, errormsg
	end
	vim.cmd.edit(target)
	M.bdelete_by_path(source)
end

local function rm(target)
	-- avoid deleting file if buffer has never been written to disk
	if vim.fn.filereadable(target) == 1 then
		local success, errormsg = M.config.delete(target)
		if success then
			local filename = vim.fn.fnamemodify(target, "%:t")
			vim.notify(string.format("%q deleted.", filename))
		else
			vim.notify("Could not delete file: " .. errormsg, log_error)
			return
		end
	end
end

M.config = {
	bdelete = vim.cmd.bdelete,
	confirm_delete = true,
	mv = M.default_mv,
	rm = rm,
}

function M.config.delete(target)
	return os.remove(target)
end

local function confirm(message, cb, needs_confirm)
	if needs_confirm then
		vim.api.nvim_echo({ { message } }, false, {})
		local choice = string.char(vim.fn.getchar())
		if choice == "y" then
			cb()
		end
	else
		cb()
	end
end

local function create_dir(target)
	if vim.fn.isdirectory(target) == 0 then
		local success, errormsg = pcall(vim.fn.mkdir, target, "p")
		if success then
			vim.notify(string.format("Created directory %q", target))
		else
			vim.notify("Could not create directory: " .. errormsg, log_error)
			return false
		end
	end
	return true
end

local function ensure_dir(target)
	local new_dir = vim.fn.fnamemodify(target, ":h")
	return create_dir(new_dir)
end

local function move(source, target)
	source = vim.fn.fnamemodify(source, "%:p")
	target = vim.fn.fnamemodify(target, "%:p")
	if target == source then
		return
	end

	local success, errormsg = M.config.mv(source, target)
	if success == false then
		vim.notify("Could not rename file: " .. errormsg, log_error)
		return false
	end

	return true
end

function M.move(source)
	source = get_filepath(source)
	vim.cmd.update(source)
	local dirs
	if vim.fn.executable "fd" then
		local cmd = { "fd", "--type", "directory", "--strip-cwd-prefix" }
		dirs = vim.fn.systemlist(cmd)
		if vim.v.shell_error ~= 0 then
			error(table.concat(dirs, "\n"))
		end
	elseif vim.fn.executable "find" then
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
	vim.ui.select(dirs, { prompt = "Move to" }, function(target)
		-- slight optimization (avoids checking if dir is a directory)
		-- would be needed if `ui.select` could return values not in the list
		if target == nil then
			return
		end
		if target == "." then
			target = vim.fn.fnamemodify(source, ":p:t") -- ??
		else
			target = target .. path_sep .. vim.fn.fnamemodify(source, ":p:t")
		end
		move(source, target)
	end)
end

local function file_op(opts)
	return function(source)
		source = get_filepath(source)
		if opts.update then
			vim.cmd.update(source)
		end
		vim.ui.input(
			{ prompt = opts.prompt, default = vim.fn.fnamemodify(source, "%:.") },
			function(target)
				if target == nil or target == "" then
					return
				end
				if
					vim.endswith(target, "/")
					or vim.endswith(target, "\\")
					or vim.fn.isdirectory(target) == 1
				then
					if opts.dir_action then
						return opts.dir_action(source, target)
					end
					target = target .. path_sep .. vim.fn.fnamemodify(source, "%:t")
				end
				if target == source then
					return
				end
				if not ensure_dir(target) then
					return
				end
				opts.action(source, target)
			end
		)
	end
end

M.rename = file_op {
	prompt = "rename",
	update = true,
	action = move,
}

M.duplicate = file_op {
	prompt = "duplicate",
	update = true,
	action = function(source, target)
		local uv = require "luv"
		local succ, errormsg = uv.fs_copyfile(source, target, { excl = true })
		if succ then
			vim.cmd.edit(target)
		else
			vim.notify("Could not duplicate file: " .. errormsg, log_error)
		end
	end,
}

M.create = file_op {
	prompt = "edit",
	update = true,
	action = function(_, target)
		vim.cmd.edit(target)
	end,
	dir_action = function(_, target)
		create_dir(target)
	end,
}

local function leave_visual_mode()
	-- https://github.com/neovim/neovim/issues/17735#issuecomment-1068525617
	local esc_key = vim.api.nvim_replace_termcodes("<Esc>", false, true, true)
	vim.api.nvim_feedkeys(esc_key, "nx", false)
end

--TODO: winnr
M.create_from_selection = file_op {
	prompt = "create from selection",
	action = function(_, target)
		local prev_reg = vim.fn.getreg "z"
		leave_visual_mode()
		vim.cmd [['<,'>delete z]]
		vim.cmd.edit(target)
		vim.cmd "put z"
		vim.fn.setreg("z", prev_reg) -- restore register content
	end,
}

function M.delete(target)
	target = get_filepath(target)
	confirm(
		string.format("Delete %q (y/n)?", vim.fn.fnamemodify(target, "%:.")),
		function()
			rm(target)
			M.config.rm()
			M.config.bdelete()
		end,
		M.config.confirm_delete
	)
end

function M.chmod_x(target)
	target = get_filepath(target)
	vim.cmd.update(target)
	local perm = vim.fn.getfperm(target)
	perm = perm:gsub("r(.)%-", "r%1x") -- add x to every group that has r
	vim.fn.setfperm(target, perm)
	vim.cmd.filetype "detect"
end

function M.yank(contents)
	local reg = '"'
	-- use system clipboard?
	local clipboard_opt = vim.opt.clipboard:get()
	if #clipboard_opt > 0 and clipboard_opt[1]:find "unnamed" then
		reg = "+"
	end
	vim.fn.setreg(reg, contents)
	vim.notify("YANKED " .. contents)
end

---Copy absolute path of current file
function M.yank_filepath(source)
	source = get_filepath(source)
	M.yank(vim.fn.fnamemodify(source, "%:."))
end

---Copy name of current file
function M.yank_filename(source)
	source = get_filepath(source)
	M.yank(vim.fn.fnamemodify(source, "%:t"))
end

function M.setup(user_config)
	utils.deep_merge(M.config, user_config or {})
end

return M
