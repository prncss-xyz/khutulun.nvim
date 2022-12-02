local M = require("khutulun.utils.init")

describe("deep_merge", function()
	it("should merge recursively", function()
		assert.are.same({ a = { b = 2, c = 3 } }, M.deep_merge({ a = { b = 2 } }, { a = { c = 3 } }))
	end)
end)
