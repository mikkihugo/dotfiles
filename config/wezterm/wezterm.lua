local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- IBM Carbon × Dracula
-- Orange 40: #FF832B  Gray 60: #6F6F6F  on Dracula graphite
local carbon = {
	bg          = "#1C1C1C", -- between Carbon Gray 100 + Dracula, slightly warm
	bg_panel    = "#262626", -- Carbon Gray 90
	bg_select   = "#3D3D3D", -- Carbon Gray 80 adjusted
	fg          = "#F4F4F4", -- Carbon Gray 10
	fg_dim      = "#6F6F6F", -- Carbon Gray 60
	orange      = "#FF832B", -- Carbon Orange 40
	orange_dim  = "#FFB784", -- Carbon Orange 30 (bright variant)
	red         = "#FA4D56", -- Carbon Red 50
	red_bright  = "#FF8389", -- Carbon Red 30
	green       = "#42BE65", -- Carbon Green 50
	green_bright= "#6FDC8C", -- Carbon Green 40
	blue        = "#4589FF", -- Carbon Blue 50
	blue_bright = "#78A9FF", -- Carbon Blue 40
	cyan        = "#3DDBD9", -- Carbon Teal 40
	cyan_bright = "#82CFFF", -- Carbon Blue 30
	purple      = "#A56EFF", -- Dracula purple (kept — ties to Dracula roots)
	purple_bright="#D0A9F5",
	black       = "#262626", -- Carbon Gray 90
	black_bright= "#6F6F6F", -- Carbon Gray 60
	white       = "#F4F4F4", -- Carbon Gray 10
	white_bright= "#FFFFFF",
	cursor      = "#FF832B", -- Orange 40 cursor — the signature
	tab_bg      = "#161616", -- Carbon Gray 100
	tab_active  = "#FF832B", -- Orange 40 active tab
	tab_active_fg="#161616",
	tab_inactive= "#262626",
}

-- ── Font ──────────────────────────────────────────────────────────────────────
config.font = wezterm.font_with_fallback({
	{ family = "JetBrainsMono Nerd Font", weight = "Regular" },
	{ family = "JetBrains Mono",          weight = "Regular" },
	{ family = "Symbols Nerd Font Mono" },
	"Menlo",
})
config.font_size = 13.5
config.line_height = 1.2
config.cell_width = 1.0
config.underline_thickness = 2
config.underline_position = -4

-- ── Colors ────────────────────────────────────────────────────────────────────
config.color_scheme = nil -- using inline scheme
config.colors = {
	foreground    = carbon.fg,
	background    = carbon.bg,
	cursor_bg     = carbon.cursor,
	cursor_border = carbon.cursor,
	cursor_fg     = carbon.bg,
	selection_bg  = carbon.bg_select,
	selection_fg  = carbon.fg,

	ansi = {
		carbon.black,   -- 0 black
		carbon.red,     -- 1 red
		carbon.green,   -- 2 green
		carbon.orange,  -- 3 yellow → Carbon Orange 40
		carbon.blue,    -- 4 blue
		carbon.purple,  -- 5 magenta
		carbon.cyan,    -- 6 cyan
		carbon.white,   -- 7 white
	},
	brights = {
		carbon.black_bright,  -- 8
		carbon.red_bright,    -- 9
		carbon.green_bright,  -- 10
		carbon.orange_dim,    -- 11 bright yellow → Orange 30
		carbon.blue_bright,   -- 12
		carbon.purple_bright, -- 13
		carbon.cyan_bright,   -- 14
		carbon.white_bright,  -- 15
	},

	tab_bar = {
		background = carbon.tab_bg,
		active_tab = {
			bg_color  = carbon.tab_active,
			fg_color  = carbon.tab_active_fg,
			intensity = "Bold",
		},
		inactive_tab = {
			bg_color = carbon.tab_inactive,
			fg_color = carbon.fg_dim,
		},
		inactive_tab_hover = {
			bg_color = carbon.bg_select,
			fg_color = carbon.fg,
		},
		new_tab = {
			bg_color = carbon.tab_bg,
			fg_color = carbon.fg_dim,
		},
		new_tab_hover = {
			bg_color = carbon.bg_select,
			fg_color = carbon.orange,
		},
	},
}

-- ── Window ────────────────────────────────────────────────────────────────────
config.window_decorations          = "RESIZE"
config.window_background_opacity   = 0.96
config.macos_window_background_blur= 20
config.window_padding = { left = 12, right = 12, top = 10, bottom = 6 }
config.initial_cols = 220
config.initial_rows = 50

-- ── Tab bar ───────────────────────────────────────────────────────────────────
config.enable_tab_bar              = true
config.use_fancy_tab_bar           = false  -- retro/compact like iTerm
config.tab_bar_at_bottom           = false
config.hide_tab_bar_if_only_one_tab= false
config.tab_max_width               = 36
config.show_tab_index_in_tab_bar   = false

-- Pretty tab title: icon + cwd basename
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
	title = wezterm.truncate_right(title, max_width - 4)
	if tab.is_active then
		return { { Text = "  " .. title .. "  " } }
	end
	return { { Text = "  " .. title .. "  " } }
end)

-- Window title
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
config.cursor_blink_rate            = 500
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

-- ── Keys (iTerm2-like) ────────────────────────────────────────────────────────
config.keys = {
	-- Tabs
	{ key = "t",          mods = "CMD",       action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "w",          mods = "CMD",       action = act.CloseCurrentTab({ confirm = false }) },
	{ key = "LeftArrow",  mods = "CMD|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "RightArrow", mods = "CMD|SHIFT", action = act.ActivateTabRelative(1) },
	{ key = "[",          mods = "CMD|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "]",          mods = "CMD|SHIFT", action = act.ActivateTabRelative(1) },

	-- Splits (iTerm2 Cmd+D / Cmd+Shift+D)
	{ key = "d",          mods = "CMD",       action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "d",          mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "w",          mods = "CMD|SHIFT", action = act.CloseCurrentPane({ confirm = false }) },

	-- Pane navigation (Opt+Arrow)
	{ key = "LeftArrow",  mods = "OPT",       action = act.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "OPT",       action = act.ActivatePaneDirection("Right") },
	{ key = "UpArrow",    mods = "OPT",       action = act.ActivatePaneDirection("Up") },
	{ key = "DownArrow",  mods = "OPT",       action = act.ActivatePaneDirection("Down") },

	-- Font size
	{ key = "=",          mods = "CMD",       action = act.IncreaseFontSize },
	{ key = "-",          mods = "CMD",       action = act.DecreaseFontSize },
	{ key = "0",          mods = "CMD",       action = act.ResetFontSize },

	-- Scrollback (iTerm2 Cmd+K = clear)
	{ key = "k",          mods = "CMD",       action = act.ClearScrollback("ScrollbackAndViewport") },

	-- Find (iTerm2 Cmd+F)
	{ key = "f",          mods = "CMD",       action = act.Search({ CaseInSensitiveString = "" }) },

	-- Word jump (Opt+Left/Right)
	{ key = "LeftArrow",  mods = "OPT",       action = act.SendString("\x1bb") },
	{ key = "RightArrow", mods = "OPT",       action = act.SendString("\x1bf") },
	{ key = "Home",       mods = "",          action = act.SendString("\x01") },
	{ key = "End",        mods = "",          action = act.SendString("\x05") },
}

-- ── Mouse ─────────────────────────────────────────────────────────────────────
config.mouse_bindings = {
	-- Cmd+click opens URLs
	{
		event  = { Up = { streak = 1, button = "Left" } },
		mods   = "CMD",
		action = act.OpenLinkAtMouseCursor,
	},
}

-- ── Hyperlinks ────────────────────────────────────────────────────────────────
config.hyperlink_rules = wezterm.default_hyperlink_rules()

-- ── Misc ──────────────────────────────────────────────────────────────────────
config.automatically_reload_config   = true
config.check_for_updates             = false
config.warn_about_missing_glyphs     = false
config.adjust_window_size_when_changing_font_size = false

return config
