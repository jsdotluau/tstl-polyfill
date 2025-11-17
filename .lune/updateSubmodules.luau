local process = require("@lune/process")
process.exec("git", { "submodule", "update", "--remote" }, {
	shell = true,
	stdio = "forward",
})
