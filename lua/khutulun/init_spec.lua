local M = require "khutulun"

describe("delete", function()
	local cwd, root, config

	before_each(function()
		cwd = vim.fn.getcwd()
		root = vim.fn.tempname()
		vim.fn.mkdir(root, "p")
		vim.cmd.cd(root)
		config = vim.deepcopy(M.config)
		M.setup { confirm_delete = false }
	end)

	after_each(function()
		vim.cmd.enew { bang = true }
		vim.cmd.cd(cwd)
		vim.fn.delete(root, "rf")
		M.config = config
	end)

	local function write(path)
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		vim.fn.writefile({ "contents" }, path)
	end

	it("removes empty ancestors and preserves the working directory", function()
		write "parent/child/file.txt"
		vim.cmd.edit "parent/child/file.txt"
		local buffer = vim.api.nvim_get_current_buf()

		M.delete()

		assert.are.equal(0, vim.fn.filereadable "parent/child/file.txt")
		assert.are.equal(0, vim.fn.isdirectory "parent")
		assert.are.equal(1, vim.fn.isdirectory(root))
		assert.is_false(vim.api.nvim_buf_is_loaded(buffer))
	end)

	it("stops at an ancestor containing another file", function()
		write "parent/child/file.txt"
		write "parent/.keep"

		M.delete "parent/child/file.txt"

		assert.are.equal(0, vim.fn.isdirectory "parent/child")
		assert.are.same({ "contents" }, vim.fn.readfile "parent/.keep")
	end)

	it("preserves a sibling empty directory", function()
		write "parent/child/file.txt"
		vim.fn.mkdir "parent/sibling"

		M.delete(root .. "/parent/child/file.txt")

		assert.are.equal(0, vim.fn.isdirectory "parent/child")
		assert.are.equal(1, vim.fn.isdirectory "parent/sibling")
	end)

	it("leaves files and directories intact when deletion is declined", function()
		write "parent/child/file.txt"
		M.setup { confirm_delete = true }
		vim.api.nvim_feedkeys("n", "nt", false)

		M.delete "parent/child/file.txt"

		assert.are.same({ "contents" }, vim.fn.readfile "parent/child/file.txt")
	end)

	it("cleans up after a configured delete callback", function()
		write "parent/child/file.txt"
		M.setup {
			delete = function(target)
				assert(os.rename(target, root .. "/saved.txt"))
			end,
		}

		M.delete "parent/child/file.txt"

		assert.are.equal(0, vim.fn.isdirectory "parent")
		assert.are.same({ "contents" }, vim.fn.readfile "saved.txt")
	end)

	it(
		"preserves directories if the configured callback leaves the file",
		function()
			write "parent/child/file.txt"
			M.setup { delete = function() end }

			M.delete "parent/child/file.txt"

			assert.are.same({ "contents" }, vim.fn.readfile "parent/child/file.txt")
		end
	)

	it("preserves directories when deleting an unwritten buffer", function()
		vim.fn.mkdir("parent/child", "p")
		vim.cmd.edit "parent/child/file.txt"

		M.delete()

		assert.are.equal(1, vim.fn.isdirectory "parent/child")
	end)
end)
