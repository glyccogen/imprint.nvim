# imprint.nvim

create beautiful code screenshots instantly from Neovim, using TOhtml.

`imprint.nvim` is a Neovim plugin to take beautiful code-snippets images from code.

![sample screenshot](sample.png)

Code is exactly what you see in Neovim, preserved with the same colors, highlights, and diagnostics.

## Dependencies

-   **Python 3.8+** with `pip` and `venv`
-   `nvim-web-devicons` for file icons in the titlebar
-   `xclip` for copying images to the clipboard

## Configuration and default values

```lua
require('imprint').setup({
	-- default title used for the window header
	-- fallback if no title is provided
	default_title = nil,

	-- when true, prompt for a title if none was provided and --notitle is not set
    required_title_by_default = true,

	-- copy the generated image to the clipboard after saving
	-- works with xclip only
	copy_to_clipboard = false,

	-- output directory for saved screenshots
	-- when nil, saves to the current file's directory
	output_dir = nil,

	-- hex-code for the background outside the code window
	background = "#A5A6F6",

	-- line number visibility
	-- true:              current settings
	-- false:             no line numbers
	-- "absolute":        absolute line numbers
	-- "absolute_from_1": absolute line numbers starting from 1 in the image
	line_numbers = "absolute_from_1",

	-- highlight the line number the cursor is on
	highlight_current_line = false,

	-- show diagnostic signs highlights
	diagnostics_on = false,

	-- show a file icon in the titlebar
	-- depends on nvim-web-devicons
	icons_on = true,
})
```

## Command **Imprint**

create a screenshot from the current buffer or a selected range.

```vim
:Imprint [-c | --clipboard-only] [--notitle] [title]
```

-   `-c`, `--clipboard-only` - copy the image to the clipboard and donot save it to disk
-   `--notitle` - do not prompt for a title when none is provided
-   `title` - optional title for the window header

## Troubleshooting

**Playwright install fails on first run**

`imprint.nvim` installs Chromium for Playwright. If step fails, system may be missing OS packages Playwright needs. In that case, run:

```bash
/path/to/imprint/venv/bin/playwright install --with-deps chromium
```
