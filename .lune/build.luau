local pathfs = require("@pkg/pathfs")

local process = require("@lune/process")
local serde = require("@lune/serde")

if not table.find(process.args, "--skip-build") then
	process.exec("npm", { "run", "build" }, {
		cwd = "./TypeScriptToLua",
		shell = true,
		stdio = "forward",
	})
end

local packageFile = pathfs.FilePath.fromExisting("pesde.toml")
local package = serde.decode("toml", packageFile:readFile())

local scope = string.split(package.name, "/")[1]

local dist = pathfs.DirectoryPath.new("dist")

local tstlPath = pathfs.Path.from("TypeScriptToLua")
local tstlPackageFile = pathfs.FilePath.fromExisting(tstlPath:join("package.json"))
local tstlPackage = serde.decode("json", tstlPackageFile:readFile())

local polyfills = tstlPath:join("dist"):join("lualib"):join("universal")
local polyfillModules = pathfs.FilePath.fromExisting(polyfills:join("lualib_module_info.json"))
--pathfs.FilePath.new(pathfs.Path.new("src"):join("polyfills.json")):writeFile(polyfillModules:readFile())

if not table.find(process.args, "--keep-version") then
	package.version = tstlPackage.version
end

type Polyfill = string
type Dependencies = { Polyfill }
type Exports = { string }
type PolyfillInfo = {
	dependencies: Dependencies?,
	exports: Exports,
}

local moduleInfo = serde.decode("json", polyfillModules:readFile()) :: {
	[Polyfill]: PolyfillInfo,
}

-- Clear contents of dist
if dist:isDir() then
	dist:removeDir()
end
dist:writeDir()

local function getPolyfillPackageName(polyfill: Polyfill): string
	return `{scope}/tstl_{string.lower(polyfill)}`
end

type PackageDependency = { workspace: string, version: "=" }
type PackageDependencies = { [string]: PackageDependency }
local function getPolyfillPackageDepdendencies(polyfill: Polyfill, info: PolyfillInfo): PackageDependencies?
	if not info.dependencies then
		return nil
	end

	local result: PackageDependencies = {}
	for _, dependency in info.dependencies do
		if dependency == polyfill then
			continue
		end

		result[dependency] = { workspace = getPolyfillPackageName(dependency), version = "=" }
	end

	return result
end

local function getPolyfillSource(polyfill: Polyfill, info: PolyfillInfo): string
	if polyfill == "polyfill" then
		polyfill = "lualib_bundle"
	end

	local sourceFile = polyfills:join(polyfill):withExtension("lua")
	local source = pathfs.FilePath.fromExisting(sourceFile):readFile()

	if polyfill ~= "lualib_bundle" then
		if info.dependencies then
			local depdendencies: { string } = {}
			for _, dependency in info.dependencies do
				if dependency == polyfill then
					continue
				end

				local dependencyInfo = moduleInfo[dependency]
				for _, export in ipairs(dependencyInfo.exports) do
					if not string.find(source, export) then
						continue
					end

					table.insert(depdendencies, `local {export} = require("./luau_packages/{dependency}").{export}`)
				end
			end

			source = `{table.concat(depdendencies, "\n")}\n\n` .. source
		end

		local exports: { string } = {}
		for _, export in info.exports do
			table.insert(exports, `\t{export} = {export}`)
		end

		source = source .. `\nreturn \{\n{table.concat(exports, ",\n")}\n}\n`
	end

	source = "--!nocheck\n" .. source
	source = string.gsub(source, "_G%.", "")

	return source
end

if table.find(process.args, "--bundle") then
	local exports: Exports = {}
	for _, info in moduleInfo do
		for _, export in ipairs(info.exports) do
			table.insert(exports, export)
		end
	end

	moduleInfo = {
		polyfill = {
			exports = exports,
		},
	} :: {
		[Polyfill]: PolyfillInfo,
	}
end

for polyfill, info in moduleInfo do
	local dir = pathfs.DirectoryPath.new(dist.path:join(polyfill)):withDirWritten()
	local pesdeConfig = pathfs.FilePath.new(dir.path:join("pesde.toml"))
	local sourceFile = pathfs.FilePath.new(dir.path:join(`{polyfill}.luau`))

	pesdeConfig:writeFile(serde.encode("toml", {
		name = getPolyfillPackageName(polyfill),
		version = package.version,
		description = if polyfill == "polyfill"
			then "Polyfills from TypeScriptToLua"
			else `{polyfill} polyfill from TypeScriptToLua`,
		repository = package.repository,
		license = package.license,
		includes = { pesdeConfig.path:fileName(), sourceFile.path:fileName() },

		target = {
			environment = "luau",
		},

		indices = {
			default = "https://github.com/pesde-pkg/index",
		},

		dependencies = getPolyfillPackageDepdendencies(polyfill, info),
	}, true))

	sourceFile:writeFile(getPolyfillSource(polyfill, info))
end

packageFile:writeFile(serde.encode("toml", package, true))
if not table.find(process.args, "--skip-install") then
	process.exec("pesde", { "install" }, {
		shell = true,
		stdio = "forward",
	})
end
