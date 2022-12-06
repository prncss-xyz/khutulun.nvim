local M = {}

local utils = require "khutulun.utils"

local path_sep = "/"

local log_error = vim.log.levels.ERROR

M.config = {
	bdelete = vim.cmd.bdelete,
	confirm_delete = true,
	mv = function(source, target)
		return os.rename(source, target)
	end,
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

local function mv(source, target)
	vim.cmd.update(source)
	source = vim.fn.fnamemodify(source, "%:p")
	target = vim.fn.fnamemodify(target, "%:p")
	if target == source then
		return
	end

	local success, errormsg
	success, errormsg = M.config.mv(source, target)
	if not success then
		vim.notify("Could not rename file: " .. errormsg, log_error)
		return false
	end

	local done
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		local path = vim.api.nvim_buf_get_name(bufnr)
		if path == source then
			vim.cmd.edit(target)
			vim.api.nvim_buf_delete(bufnr, {})
			done = true
			break
		end
	end
	if not done then
		-- the source was not opened
		vim.cmd.edit(target)
	end
	return true
end

function M.move(source)
	source = source or vim.fn.expand "%"
	local dirs
	if vim.fn.executable "fd" then
		local cmd = { "fd", "--type", "directory" }
		dirs = vim.fn.systemlist(cmd)
		if vim.v.shell_error ~= 0 then
			error(table.concat(dirs, "\n"))
		end
		dirs = vim.tbl_map(function(dir)
			return dir:sub(1, dir:len() - 1):sub(3)
		end, dirs)
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
		mv(source, target)
	end)
end

local function file_op(source, opts)
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

function M.rename(source)
	source = source or vim.fn.expand "%"
	file_op(source, {
		prompt = "rename",
		action = mv,
	})
end

function M.duplicate(source)
	source = source or vim.fn.expand "%"
	file_op(source, {
		prompt = "duplicate",
		action = function(_, target)
			vim.cmd.saveas(target)
			vim.cmd.edit(target)
		end,
	})
end

function M.create(source)
	source = source or vim.fn.expand "%"
	file_op(source, {
		prompt = "edit",
		action = function(_, target)
			vim.cmd.edit(target)
		end,
	})
end

local function leave_visual_mode()
	-- https://github.com/neovim/neovim/issues/17735#issuecomment-1068525617
	local esc_key = vim.api.nvim_replace_termcodes("<Esc>", false, true, true)
	vim.api.nvim_feedkeys(esc_key, "nx", false)
end

--TODO: winnr
function M.create_from_selection()
	file_op {
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
end

local function delete(target)
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
	M.config.bdelete()
end

function M.delete(target)
	target = target or vim.fn.expand "%"
	confirm(
		string.format("Delete %q (y/n)?", vim.fn.fnamemodify(target, "%:.")),
		function()
			delete(target)
		end,
		M.config.confirm_delete
	)
end

function M.chmod_x(target)
	target = target or vim.fn.expand "%"
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
	source = source or vim.fn.expand "%"
	M.yank(vim.fn.fnamemodify(source, "%:."))
end

---Copy name of current file
function M.yank_filename(source)
	source = source or vim.fn.expand "%"
	M.yank(vim.fn.fnamemodify(source, "%:t"))
end

function M.setup(user_config)
	utils.deep_merge(M.config, user_config or {})
end

return M
