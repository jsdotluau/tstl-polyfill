local process = require("@lune/process")

local cwd = "TypeScriptToLua"
process.exec("git", { "fetch", "--tags" }, {
	cwd = cwd,
	shell = true,
	stdio = "forward",
})

local result = process.exec("git", { "rev-list", "--tags", "--max-count=1", "--no-walk" }, {
	cwd = cwd,
	shell = true,
})

local lines = string.split(result.stdout, "\n")
local releaseCommit = lines[#lines - 1]
process.exec("git", { "checkout", releaseCommit }, {
	cwd = cwd,
	shell = true,
	stdio = "forward",
})
