local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- IBM Big Orange — Scandinavian edition
-- Carbon Orange 40 (#FF832B) is the only accent. Carbon Gray 50 (#8D8D8D) for dim.
-- Everything else: warm graphite. No blue. No noise.
local c = {
	bg          = "#1C1C1C", -- warm graphite (Carbon Gray 100 + Dracula warmth)
	bg_panel    = "#262626", -- Carbon Gray 90
	bg_select   = "#393939", -- Carbon Gray 80
	fg          = "#F4F4F4", -- Carbon Gray 10
	fg_dim      = "#8D8D8D", -- Carbon Gray 50
	orange      = "#FF832B", -- Carbon Orange 40 — the one accent
	orange_soft = "#FFB784", -- Carbon Orange 30 (bright slots)
	red         = "#FA4D56", -- Carbon Red 50
	red_bright  = "#FF8389", -- Carbon Red 30
	green       = "#42BE65", -- Carbon Green 50
	green_bright= "#6FDC8C", -- Carbon Green 40
	blue        = "#4589FF", -- Carbon Blue 50 (ANSI slot only)
	blue_bright = "#78A9FF",
	teal        = "#3DDBD9", -- Carbon Teal 40 (ANSI slot only)
	teal_bright = "#82CFFF",
	purple      = "#A56EFF", -- Dracula purple (ANSI slot only)
	purple_bright="#D0A9F5",
	black       = "#262626",
	black_bright= "#8D8D8D", -- Gray 50 — intentional, keeps palette tight
	white       = "#F4F4F4",
	white_bright= "#FFFFFF",
	cursor      = "#FF832B", -- Orange 40 cursor
	tab_bg      = "#161616", -- Carbon Gray 100
	tab_active  = "#FF832B",
	tab_active_fg= "#161616",
	tab_inactive= "#262626",
}

-- ── Font ──────────────────────────────────────────────────────────────────────
config.font = wezterm.font_with_fallback({
	{ family = "JetBrainsMono Nerd Font Mono", weight = "Regular" },
	{ family = "JetBrains Mono",               weight = "Regular" },
	"Consolas",
})
config.font_size = 13.5
config.line_height = 1.2
config.cell_width = 1.0
config.underline_thickness = 2
config.underline_position = -4

-- No cursive italics — regular weight throughout.
config.font_rules = {
	{
		italic = true,
		font = wezterm.font("JetBrainsMono Nerd Font", { weight = "Regular", italic = false }),
	},
}

-- ── Colors ────────────────────────────────────────────────────────────────────
config.color_scheme = nil
config.colors = {
	foreground    = c.fg,
	background    = c.bg,
	cursor_bg     = c.cursor,
	cursor_border = c.cursor,
	cursor_fg     = c.bg,
	selection_bg  = c.bg_select,
	selection_fg  = c.fg,

	ansi = {
		c.black,   -- 0
		c.red,     -- 1
		c.green,   -- 2
		c.orange,  -- 3 yellow → Carbon Orange 40
		c.blue,    -- 4
		c.purple,  -- 5
		c.teal,    -- 6
		c.white,   -- 7
	},
	brights = {
		c.black_bright,  -- 8
		c.red_bright,    -- 9
		c.green_bright,  -- 10
		c.orange_soft,   -- 11
		c.blue_bright,   -- 12
		c.purple_bright, -- 13
		c.teal_bright,   -- 14
		c.white_bright,  -- 15
	},

	tab_bar = {
		background = c.tab_bg,
		active_tab = {
			bg_color  = c.tab_active,
			fg_color  = c.tab_active_fg,
			intensity = "Bold",
		},
		inactive_tab = {
			bg_color = c.tab_inactive,
			fg_color = c.fg_dim,
		},
		inactive_tab_hover = {
			bg_color = c.bg_select,
			fg_color = c.fg,
		},
		new_tab = {
			bg_color = c.tab_bg,
			fg_color = c.fg_dim,
		},
		new_tab_hover = {
			bg_color = c.bg_panel,
			fg_color = c.orange,
		},
	},
}

-- ── Window ────────────────────────────────────────────────────────────────────
config.window_decorations          = "INTEGRATED_BUTTONS|RESIZE"
config.window_background_opacity   = 1.0
config.window_padding = { left = 16, right = 16, top = 12, bottom = 8 }
config.initial_cols = 220
config.initial_rows = 50

-- ── Tab bar ───────────────────────────────────────────────────────────────────
config.enable_tab_bar              = true
config.use_fancy_tab_bar           = true
config.tab_bar_at_bottom           = false
config.hide_tab_bar_if_only_one_tab= false
config.tab_max_width               = 32
config.show_tab_index_in_tab_bar   = false
config.window_frame = {
	font      = wezterm.font("JetBrainsMono Nerd Font Mono", { weight = "Regular" }),
	font_size = 11.5,
}

wezterm.on("format-tab-title", function(tab, _tabs, _panes, _config, _hover, max_width)
	local pane  = tab.active_pane
	local title = pane.title
	local cwd   = pane.current_working_dir
	if cwd then
		local parts = {}
		for part in tostring(cwd):gmatch("[^/]+") do
			table.insert(parts, part)
		end
		title = parts[#parts] or title
	end
	return { { Text = "  " .. wezterm.truncate_right(title, max_width - 4) .. "  " } }
end)

wezterm.on("format-window-title", function(tab, _pane, _tabs, _panes, _config)
	local pane  = tab.active_pane
	local cwd   = pane.current_working_dir
	local title = pane.title
	if cwd then
		title = tostring(cwd):gsub("file://[^/]*", "")
	end
	return title
end)

-- ── Cursor ────────────────────────────────────────────────────────────────────
config.default_cursor_style         = "BlinkingBar"
config.cursor_blink_rate            = 600
config.cursor_blink_ease_in         = "Constant"
config.cursor_blink_ease_out        = "Constant"

-- ── Scrollback ────────────────────────────────────────────────────────────────
config.scrollback_lines             = 50000
config.enable_scroll_bar            = false

-- ── Bell ──────────────────────────────────────────────────────────────────────
config.audible_bell                 = "Disabled"
config.visual_bell = {
	fade_in_duration_ms  = 75,
	fade_out_duration_ms = 75,
	target               = "CursorColor",
}

-- ── Launch menu ───────────────────────────────────────────────────────────────
-- Dropdown next to the "+" tab button. First entry is the default for new tabs.
config.launch_menu = {
	{ label = "Hermes TUI",  args = { "wsl.exe", "bash", "-l", "-c", "hermes" } },
	{ label = "WSL ~/code",  args = { "wsl.exe", "bash", "-l", "-c", "cd ~/code && exec bash" } },
	{ label = "WSL ~",       args = { "wsl.exe", "bash", "-l" } },
	{ label = "PowerShell",  args = { "pwsh.exe" } },
	{ label = "cmd.exe",     args = { "cmd.exe" } },
}
config.default_prog = { "wsl.exe", "--cd", "~", "bash", "-l" }

-- ── Keys ──────────────────────────────────────────────────────────────────────
config.keys = {
	{ key = "t",          mods = "CMD",       action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "t",          mods = "CMD|SHIFT", action = act.ShowLauncherArgs({ flags = "LAUNCH_MENU_ITEMS" }) },
	{ key = "w",          mods = "CMD",       action = act.CloseCurrentTab({ confirm = false }) },
	{ key = "LeftArrow",  mods = "CMD|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "RightArrow", mods = "CMD|SHIFT", action = act.ActivateTabRelative(1) },
	{ key = "[",          mods = "CMD|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "]",          mods = "CMD|SHIFT", action = act.ActivateTabRelative(1) },
	{ key = "d",          mods = "CMD",       action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "d",          mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "w",          mods = "CMD|SHIFT", action = act.CloseCurrentPane({ confirm = false }) },
	{ key = "LeftArrow",  mods = "OPT",       action = act.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "OPT",       action = act.ActivatePaneDirection("Right") },
	{ key = "UpArrow",    mods = "OPT",       action = act.ActivatePaneDirection("Up") },
	{ key = "DownArrow",  mods = "OPT",       action = act.ActivatePaneDirection("Down") },
	{ key = "=",          mods = "CMD",       action = act.IncreaseFontSize },
	{ key = "-",          mods = "CMD",       action = act.DecreaseFontSize },
	{ key = "0",          mods = "CMD",       action = act.ResetFontSize },
	{ key = "k",          mods = "CMD",       action = act.ClearScrollback("ScrollbackAndViewport") },
	{ key = "f",          mods = "CMD",       action = act.Search({ CaseInSensitiveString = "" }) },
	{ key = "LeftArrow",  mods = "OPT",       action = act.SendString("\x1bb") },
	{ key = "RightArrow", mods = "OPT",       action = act.SendString("\x1bf") },
	{ key = "Home",       mods = "",          action = act.SendString("\x01") },
	{ key = "End",        mods = "",          action = act.SendString("\x05") },
}

-- ── Mouse ─────────────────────────────────────────────────────────────────────
config.mouse_bindings = {
	{
		event  = { Up = { streak = 1, button = "Left" } },
		mods   = "CMD",
		action = act.OpenLinkAtMouseCursor,
	},
}

config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- ── Misc ──────────────────────────────────────────────────────────────────────
config.window_close_confirmation     = "NeverPrompt"
config.automatically_reload_config   = true
config.check_for_updates             = false
config.warn_about_missing_glyphs     = false
config.adjust_window_size_when_changing_font_size = false

return config
