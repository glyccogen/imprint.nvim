package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local provider = vim.env.IMPRINT_PROVIDER
local image_path = vim.env.IMPRINT_IMAGE

local clipboard = require("imprint.clipboard")
local ok, err = clipboard.copy_image(image_path, provider)
if not ok then
	error("clipboard.copy_image failed: " .. tostring(err))
end

print("clipboard_integration.lua: ok (" .. provider .. ")")
