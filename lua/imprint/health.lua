local M = {}

local health = vim.health or require("health")

local function plugin_root()
	local path = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
	return (path or "./") .. "../../"
end

local function path_exists(path)
	return vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1
end

local function check_python()
	if vim.fn.executable("python3") ~= 1 then
		health.error("python3 not found in PATH")
		return
	end
	health.ok("python3 found")

	local out = vim.fn.systemlist({
		"python3",
		"-c",
		"import sys; print('.'.join(map(str, sys.version_info[:3])))",
	})
	local version = out[1]
	local major, minor = version:match("^(%d+)%.(%d+)")
	major, minor = tonumber(major), tonumber(minor)
	if not major or not minor then
		health.warn("unexpected python3 version: " .. version)
		return
	end
	if major > 3 or (major == 3 and minor >= 8) then
		health.ok("python3 version is " .. version)
	else
		health.error("python3 version is " .. version .. " (needs 3.8+)")
	end
end

local function check_tohtml()
	local ok = pcall(require, "tohtml")
	if ok then
		health.ok("Lua tohtml module available")
	else
		health.error("Lua tohtml module not found (requires Neovim 0.10+)")
	end
end

local function check_optional()
	if vim.fn.executable("xclip") == 1 then
		health.ok("xclip found")
	else
		health.warn("xclip not found (needed only for copy_to_clipboard)")
	end

	local ok_devicons = pcall(require, "nvim-web-devicons")
	if ok_devicons then
		health.ok("nvim-web-devicons found")
	else
		health.info("nvim-web-devicons not found (optional)")
	end
end

local function check_venv()
	local root = plugin_root()
	local venv_path = root .. "/venv"
	local deps_flag = venv_path .. "/.deps_installed"

	if path_exists(deps_flag) then
		health.ok("playwright venv ready")
		return
	end

	if path_exists(venv_path) then
		health.warn("venv exists but Playwright not installed yet")
	else
		health.info("venv not created yet (will be created on first run)")
	end
end

function M.check()
	health.start("imprint.nvim")
	check_tohtml()
	check_python()
	check_venv()
	check_optional()
end

return M
