local M = {}
local uv = vim.uv

local function read_binary(path)
	local fd, open_err = uv.fs_open(path, "r", 438)
	if not fd then
		return nil, "failed to open file: " .. tostring(open_err or "")
	end

	local stat, stat_err = uv.fs_fstat(fd)
	if not stat or not stat.size then
		uv.fs_close(fd)
		return nil, "failed to stat file: " .. tostring(stat_err or "")
	end

	local data, read_err = uv.fs_read(fd, stat.size, 0)
	uv.fs_close(fd)
	if not data then
		return nil, "failed to read file: " .. tostring(read_err or "")
	end
	return data, nil
end

local function run_cmd(cmd, stdin, timeout)
	local opts = { text = false }
	if stdin ~= nil then
		opts.stdin = stdin
	end
	local proc = vim.system(cmd, opts)
	local result
	if timeout ~= nil then
		result = proc:wait(timeout)
	else
		result = proc:wait()
	end
	if result == nil then
		return nil, "timeout"
	end
	if result.code == 0 then
		return true, nil
	end
	local reason = result.stderr
	if not reason or reason == "" then
		reason = "exit code " .. tostring(result.code)
	end
	return false, reason
end

local function env_has(name)
	local value = vim.env[name]
	return value ~= nil and value ~= ""
end

function M.detect_provider()
	if vim.fn.has("mac") == 1 and vim.fn.executable("osascript") == 1 then
		return "macos"
	end

	if env_has("WAYLAND_DISPLAY") and vim.fn.executable("wl-copy") == 1 then
		return "wayland"
	end

	if vim.fn.executable("xclip") == 1 then
		return "x11"
	end

	return nil
end

function M.copy_image(image_path, provider)
	if not provider then
		return false, "no clipboard provider available"
	end

	if provider == "x11" then
		local ok, err = run_cmd({ "xclip", "-selection", "clipboard", "-t", "image/png", "-i", image_path })
		if ok then return true, nil end
		return false, "xclip failed: " .. err
	elseif provider == "wayland" then
		local data, read_err = read_binary(image_path)
		if not data then
			return false, read_err
		end
		local ok, err = run_cmd({ "wl-copy", "--type", "image/png" }, data, 1000)
		if ok then return true, nil end
		if ok == nil and err == "timeout" then
			return true, nil
		end
		return false, "wl-copy failed: " .. err
	elseif provider == "macos" then
		local cmd = {
			"osascript",
			"-e",
			"on run argv",
			"-e",
			"set imagePath to POSIX file (item 1 of argv)",
			"-e",
			"set the clipboard to (read imagePath as «class PNGf»)",
			"-e",
			"end run",
			image_path,
		}
		local ok, err = run_cmd(cmd)
		if ok then return true, nil end
		return false, "osascript failed: " .. err
	end

	return false, "err " .. tostring(provider)
end

return M
