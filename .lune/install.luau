local process = require("@lune/process")
process.exec("npm", { "install" }, {
	cwd = "./TypeScriptToLua",
	shell = true,
	stdio = "forward",
})
