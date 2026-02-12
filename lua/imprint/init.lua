local M = {}
local config = require('imprint.config')
local clipboard = require('imprint.clipboard')

local function notify(msg, level)
	vim.schedule(function()
		vim.notify(msg, level or vim.log.levels.INFO, { title = "Imprint" })
	end)
end

do
	local path = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
	M.plugin_path = path .. "../../"
end
M.data_path = vim.fn.stdpath("data") .. "/imprint.nvim"
M.venv_path = M.data_path .. "/venv"

local function check_deps(on_complete)
	local deps_installed = M.venv_path .. "/.deps_installed"
	if vim.fn.filereadable(deps_installed) == 1 then
		vim.schedule(on_complete)
		return
	end
	vim.fn.mkdir(M.data_path, "p")

	local function run_job(cmd, on_done)
		local stdout = {}
		local stderr = {}
		local job_id = vim.fn.jobstart(cmd, {
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data)
				vim.list_extend(stdout, data)
			end,
			on_stderr = function(_, data)
				vim.list_extend(stderr, data)
			end,
			on_exit = function(_, code)
				on_done(code, stdout, stderr)
			end,
		})
		if job_id <= 0 then
			return on_done(1, {}, { "failed to start: " .. table.concat(cmd, " ") })
		end
	end

	notify("installing deps...")
	run_job({ "python3", "-m", "venv", M.venv_path }, function(code, _, err)
		if code ~= 0 then
			notify("failed to create venv:\n" .. table.concat(err, "\n"), vim.log.levels.ERROR)
			return
		end

		local pip_cmd = {
			M.venv_path .. "/bin/python",
			"-m",
			"pip",
			"install",
			"playwright",
		}

		run_job(pip_cmd, function(pip_code, _, pip_err)
			if pip_code ~= 0 then
				notify("failed to install playwright:\n" .. table.concat(pip_err, "\n"),
					vim.log.levels.ERROR)
				return
			end

			local playwright_cmd = { M.venv_path .. "/bin/playwright", "install", "chromium" }

			run_job(playwright_cmd, function(pw_code, _, pw_err)
				if pw_code ~= 0 then
					notify("failed to install Playwright Chromium:\n" .. table.concat(pw_err, "\n"),
						vim.log.levels.ERROR)
					return
				end
				vim.fn.writefile({}, deps_installed)
				vim.schedule(on_complete)
			end)
		end)
	end)
end

local function do_copy_to_clipboard(image_path)
	if not config.opts.copy_to_clipboard then return false end
	local copied, err = clipboard.copy_image(image_path, clipboard.detect_provider())
	if copied then
		return true
	else
		notify("failed to copy to clipboard: " .. tostring(err), vim.log.levels.WARN)
		return false
	end
end

local function get_icon(buf_path)
	if not config.opts.icons_on then return nil, nil end
	local ok_devicons, devicons = pcall(require, "nvim-web-devicons")
	if not ok_devicons then
		notify("nvim-web-devicons not installed", vim.log.levels.WARN)
		return nil, nil
	end
	return devicons.get_icon_color(vim.fn.fnamemodify(buf_path, ":t"), vim.fn.fnamemodify(buf_path, ":e"),
		{ default = true })
end

local function plan_output(buf_path, clipboard_only, open_after)
	if clipboard_only then
		return { path = vim.fn.tempname() .. ".png", cleanup = not open_after }
	end
	local output_dir
	if config.opts.output_dir == nil then
		output_dir = vim.fn.fnamemodify(buf_path, ":p:h")
	else
		output_dir = vim.fn.expand(config.opts.output_dir)
	end
	vim.fn.mkdir(output_dir, "p")
	local out_filename = "imprint_" ..
	    vim.fn.fnamemodify(buf_path, ":t:r") .. "_" .. os.date("%Y%m%d%H%M%S") .. ".png"
	return { path = output_dir .. "/" .. out_filename, cleanup = false }
end

local function render_image(temp_html_path, output_path, title, icon, icon_color, on_complete)
	local cmd_args = {
		M.venv_path .. "/bin/python",
		M.plugin_path .. "/py/render.py",
		temp_html_path,
		output_path,
		"--title",
		title,
		"--background",
		config.opts.background,
		"--icon",
		icon or "",
		"--icon-color",
		icon_color or "",
	}
	local stdout = {}
	local stderr = {}
	vim.fn.jobstart(cmd_args, {
		stdout_buffered = true,
		stderr_buffered = true,
		on_stdout = function(_, data)
			vim.list_extend(stdout, data)
		end,
		on_stderr = function(_, data)
			vim.list_extend(stderr, data)
		end,
		on_exit = function(_, code)
			local out = table.concat(stdout, "\n")
			local err = table.concat(stderr, "\n")
			on_complete(code, out, err)
		end,
	})
end

local function open_image(output_path)
	local ok = pcall(vim.ui.open, output_path)
	if not ok then
		notify("failed to open image: " .. output_path, vim.log.levels.WARN)
		return false
	end
	return true
end

local function finalize_output(output_path, cleanup, open_after)
	local copy_success = do_copy_to_clipboard(output_path)
	local opened = open_after and open_image(output_path) or false
	local message_parts = {}
	if not cleanup then table.insert(message_parts, "saved to: \"" .. output_path .. "\"") end
	if copy_success then table.insert(message_parts, "copied to clipboard") end
	if opened then table.insert(message_parts, "image is opened") end
	notify(table.concat(message_parts, "\n"))
	if cleanup then vim.fn.delete(output_path) end
end

local function slice_html_pre_block(html_content, range)
	if not range then return html_content end
	local pre_start, pre_end
	for i, line in ipairs(html_content) do
		if not pre_start and line:match("<pre") then
			pre_start = i
		elseif pre_start and line:match("</pre>") then
			pre_end = i
			break
		end
	end
	if not pre_start or not pre_end then
		return html_content
	end
	local pre_lines = {}
	for i = pre_start + 1, pre_end - 1 do
		table.insert(pre_lines, html_content[i])
	end
	local sliced = {}
	local start_line = math.max(range.line1, 1)
	for i = start_line, math.min(range.line2, #pre_lines) do
		table.insert(sliced, pre_lines[i])
	end
	local out = {}
	for i = 1, pre_start do
		table.insert(out, html_content[i])
	end
	for _, line in ipairs(sliced) do
		table.insert(out, line)
	end
	for i = pre_end, #html_content do
		table.insert(out, html_content[i])
	end
	return out
end

local function renumber_line_numbers_from_1(html_content)
	local out = {}
	local in_pre = false
	local next_number = 1
	for _, line in ipairs(html_content) do
		if line:match("<pre") then
			in_pre = true
		end
		if in_pre and (line:match('class="LineNr"') or line:match('class="CursorLineNr"')) then
			line = line:gsub('id="L%d+"', 'id="L' .. next_number .. '"', 1)
			line = line:gsub('class="LineNr">%s*%d+%s*</span>',
				'class="LineNr"> ' .. next_number .. ' </span>', 1)
			line = line:gsub('class="CursorLineNr">%s*%d+%s*</span>',
				'class="CursorLineNr"> ' .. next_number .. ' </span>', 1)
			next_number = next_number + 1
		end
		table.insert(out, line)
		if in_pre and line:match("</pre>") then
			in_pre = false
		end
	end
	return out
end

local function create_imprint(title, range, clipboard_only, open_after)
	local tohtml_mod = require('tohtml')

	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_win_get_buf(win)
	local buf_path = vim.api.nvim_buf_get_name(buf)
	local saved_opts = {
		relativenumber = vim.wo[win].relativenumber,
		cursorline = vim.wo[win].cursorline,
		signcolumn = vim.wo[win].signcolumn,
	}
	local diagnostics_was_enabled = nil
	local html_content
	local ok, err_msg = xpcall(function()
		vim.wo[win].cursorline = config.opts.highlight_current_line
		vim.wo[win].signcolumn = config.opts.diagnostics_on and "yes" or "no"
		local tohtml_opts = { lsp = true }
		local line_numbers = config.opts.line_numbers
		if line_numbers == false then
			tohtml_opts.number_lines = false
		elseif line_numbers == 'absolute' or line_numbers == 'absolute_from_1' then
			vim.wo[win].relativenumber = false
			tohtml_opts.number_lines = true
		else
			tohtml_opts.number_lines = vim.wo[win].number or vim.wo[win].relativenumber
		end
		if not config.opts.diagnostics_on then
			local ok_enabled, enabled = pcall(vim.diagnostic.is_enabled, { bufnr = buf })
			if ok_enabled then
				diagnostics_was_enabled = enabled
			end
			vim.diagnostic.enable(false, { bufnr = buf })
		end
		html_content = tohtml_mod.tohtml(win, tohtml_opts)
		if range then html_content = slice_html_pre_block(html_content, range) end
		if config.opts.line_numbers == 'absolute_from_1' then
			html_content = renumber_line_numbers_from_1(html_content)
		end
	end, debug.traceback)

	vim.wo[win].relativenumber = saved_opts.relativenumber
	vim.wo[win].cursorline = saved_opts.cursorline
	vim.wo[win].signcolumn = saved_opts.signcolumn
	if diagnostics_was_enabled ~= nil then
		vim.diagnostic.enable(diagnostics_was_enabled, { bufnr = buf })
	end
	if not ok then
		return notify("failed to generate HTML: " .. tostring(err_msg), vim.log.levels.ERROR)
	end

	local temp_html_path = vim.fn.tempname() .. ".html"
	vim.fn.writefile(html_content, temp_html_path)

	local output_plan = plan_output(buf_path, clipboard_only, open_after)

	local icon, icon_color = get_icon(buf_path)
	notify("rendering image...")
	render_image(temp_html_path, output_plan.path, title, icon, icon_color, function(code, out, err)
		vim.schedule(function()
			vim.fn.delete(temp_html_path)
			if code ~= 0 then
				local message = err ~= "" and err or out
				return notify("failed to create screenshot:\n" .. message, vim.log.levels.ERROR)
			end
			finalize_output(output_plan.path, output_plan.cleanup, open_after)
		end)
	end)
end

function M.imprint_command(opts)
	local parts = opts.fargs or {}
	local clipboard_only = false
	local open_after = false
	local no_title = false
	local title_parts = {}
	for _, part in ipairs(parts) do
		if part == "-c" or part == "--clipboard-only" then
			clipboard_only = true
		elseif part == "-o" or part == "--open" then
			open_after = true
		elseif part == "--no-title" then
			no_title = true
		else
			table.insert(title_parts, part)
		end
	end
	local title_arg = table.concat(title_parts, " ")

	local range = (opts.range > 0) and { line1 = opts.line1, line2 = opts.line2 } or nil

	local function run(title)
		check_deps(function()
			create_imprint(title, range, clipboard_only, open_after)
		end)
	end

	if title_arg ~= "" then
		return run(title_arg)
	end
	if config.opts.required_title_by_default and not no_title then
		return vim.ui.input({ prompt = "title: ", default = config.opts.default_title or "" },
			function(input)
				if input == nil then return end
				run(input)
			end)
	end
	run(config.opts.default_title or "")
end

function M.setup(user_opts)
	config.setup(user_opts)
	vim.api.nvim_create_user_command('Imprint', M.imprint_command, {
		nargs = '*',
		range = true,
		complete = 'file',
		bang = false,
	})
end

return M
