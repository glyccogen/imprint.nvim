package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local clipboard = require("imprint.clipboard")
local uv = vim.uv

local function assert_eq(actual, expected)
	if actual ~= expected then
		error("failed: expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function with_mocks(run)
	local orig_exec = vim.fn.executable
	local orig_has = vim.fn.has
	local orig_wayland = vim.env.WAYLAND_DISPLAY
	local orig_sys = vim.system

	local executable_map = {}
	vim.fn.executable = function(name)
		return executable_map[name] or 0
	end
	vim.fn.has = function(feature)
		if feature == "mac" then return 0 end
		return orig_has(feature)
	end
	vim.system = function()
		return { wait = function() return { code = 0, stderr = "" } end }
	end

	local ctx = {
		set_executable = function(name, value)
			executable_map[name] = value and 1 or 0
		end,
		set_is_mac = function(value)
			vim.fn.has = function(feature)
				if feature == "mac" then return value and 1 or 0 end
				return orig_has(feature)
			end
		end,
		set_wayland = function(value)
			vim.env.WAYLAND_DISPLAY = value
		end,
		set_system = function(fn)
			vim.system = fn
		end,
	}

	local ok, err = pcall(run, ctx)

	vim.fn.executable = orig_exec
	vim.fn.has = orig_has
	vim.env.WAYLAND_DISPLAY = orig_wayland
	vim.system = orig_sys

	if not ok then
		error(err)
	end
end

with_mocks(function(ctx)
	ctx.set_executable("xclip", true)
	assert_eq(clipboard.detect_provider(), "x11")
end)

with_mocks(function(ctx)
	ctx.set_executable("xclip", true)
	ctx.set_executable("wl-copy", true)
	ctx.set_wayland("wayland-1")
	assert_eq(clipboard.detect_provider(), "wayland")
end)

with_mocks(function(ctx)
	ctx.set_is_mac(true)
	ctx.set_executable("osascript", true)
	ctx.set_executable("wl-copy", true)
	ctx.set_wayland("wayland-1")
	assert_eq(clipboard.detect_provider(), "macos")
end)

with_mocks(function(ctx)
	local temp_path = vim.fn.tempname()
	local fd = assert(uv.fs_open(temp_path, "w", 420))
	assert(uv.fs_write(fd, "PNG\0DATA", 0))
	assert(uv.fs_close(fd))

	local captured = {}
	ctx.set_system(function(cmd, opts)
		captured = { cmd = cmd, opts = opts }
		return { wait = function() return { code = 0, stderr = "" } end }
	end)

	local ok, err = clipboard.copy_image(temp_path, "wayland")
	assert_eq(ok, true)
	assert_eq(err, nil)
	assert_eq(captured.cmd[1], "wl-copy")
	assert_eq(captured.cmd[2], "--type")
	assert_eq(captured.cmd[3], "image/png")
	assert_eq(captured.opts.stdin, "PNG\0DATA")
	assert_eq(captured.opts.text, false)

	vim.fn.delete(temp_path)
end)

with_mocks(function(ctx)
	local called = {}
	ctx.set_system(function(cmd)
		called = cmd
		return { wait = function() return { code = 0, stderr = "" } end }
	end)

	local ok, err = clipboard.copy_image("/tmp/test image.png", "macos")
	assert_eq(ok, true)
	assert_eq(err, nil)
	assert_eq(called[1], "osascript")
	assert_eq(called[#called], "/tmp/test image.png")
end)

print("clipboard_spec.lua: ok")
