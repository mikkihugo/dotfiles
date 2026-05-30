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

-- ── Vega tmux helper ──────────────────────────────────────────────────────────
-- Ensure Tailscale is up, then SSH to vega and attach/create a named tmux
-- session. `tmux new -A -s NAME` attaches if NAME exists, otherwise creates
-- it — so sessions persist on vega across wezterm restarts, reboots, drops.
local function vega_tmux(session, cwd)
	local tmux_cmd
	if cwd then
		tmux_cmd = string.format("tmux new -A -s %s -c %s", session, cwd)
	else
		tmux_cmd = string.format("tmux new -A -s %s", session)
	end
	return {
		"powershell.exe", "-NoProfile", "-NoLogo", "-Command",
		string.format([[
			$ts = 'C:\Program Files\Tailscale\tailscale.exe';
			& $ts status *> $null;
			if ($LASTEXITCODE -ne 0) { & $ts up | Out-Null };
			& ssh.exe -t mhugo@vega.ts.hugo.dk '%s'
		]], tmux_cmd),
	}
end

-- Persistent tabs spawned on every wezterm launch.
-- { tmux_session_name, optional_starting_cwd_on_first_create }
local PERSISTENT_TABS = {
	{ "vega" },                -- general shell, ~ on vega
	{ "root",    "/" },        -- root filesystem view
	{ "space",   "~" },        -- scratch space
	{ "work",    "~/code" },   -- work dir
}

-- On GUI startup, open one tab per persistent session and attach.
wezterm.on("gui-startup", function(cmd)
	-- If wezterm was invoked with CLI args (e.g. `wezterm ssh host`), let it
	-- handle that itself and don't double-spawn our 4-tab window.
	if cmd and cmd.args and #cmd.args > 0 then return end
	local first = PERSISTENT_TABS[1]
	local _, _, window = wezterm.mux.spawn_window { args = vega_tmux(first[1], first[2]) }
	for i = 2, #PERSISTENT_TABS do
		local t = PERSISTENT_TABS[i]
		window:spawn_tab { args = vega_tmux(t[1], t[2]) }
	end
	window:gui_window():maximize()
end)

-- ── Font ──────────────────────────────────────────────────────────────────────
config.font = wezterm.font_with_fallback({
	{ family = "JetBrainsMonoNL Nerd Font", weight = "Regular" },
	{ family = "JetBrainsMono Nerd Font Mono", weight = "Regular" },
	{ family = "JetBrains Mono",               weight = "Regular" },
	"Consolas",
})
config.font_size = 15.0  -- bumped for 38" hi-def
config.line_height = 1.15
config.cell_width = 1.0
config.underline_thickness = 2
config.underline_position = -4
config.harfbuzz_features = { "calt=1", "liga=1", "clig=1" }

-- No cursive italics — regular weight throughout.
config.font_rules = {
	{
		italic = true,
		font = wezterm.font("JetBrainsMonoNL Nerd Font", { weight = "Regular", italic = false }),
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
config.initial_rows = 60

-- ── Tab bar ───────────────────────────────────────────────────────────────────
config.enable_tab_bar              = true
config.use_fancy_tab_bar           = true
config.tab_bar_at_bottom           = false
config.hide_tab_bar_if_only_one_tab= false
config.tab_max_width               = 32
config.show_tab_index_in_tab_bar   = false
config.show_new_tab_button_in_tab_bar = true
config.window_frame = {
	font      = wezterm.font("JetBrainsMonoNL Nerd Font", { weight = "Regular" }),
	font_size = 12.0,
}

-- Tab title: prefer the session name set on the tab; fall back to cwd basename.
wezterm.on("format-tab-title", function(tab, _tabs, _panes, _config, _hover, max_width)
	local title = tab.tab_title
	if not title or #title == 0 then
		local pane = tab.active_pane
		title = pane.title
		local cwd = pane.current_working_dir
		if cwd then
			local parts = {}
			for part in tostring(cwd):gmatch("[^/]+") do
				table.insert(parts, part)
			end
			title = parts[#parts] or title
		end
	end
	return { { Text = "  " .. wezterm.truncate_right(title, max_width - 4) .. "  " } }
end)

wezterm.on("format-window-title", function(tab, _pane, _tabs, _panes, _config)
	local cwd = tab.active_pane.current_working_dir
	if cwd then return (tostring(cwd):gsub("file://[^/]*", "")) end
	return tab.active_pane.title
end)

-- Right status: orange "vega" + day/time, with powerline arrows.
local ARROW_LEFT = wezterm.nerdfonts.pl_right_hard_divider  --
wezterm.on("update-right-status", function(window, _pane)
	local time_bg, time_fg = c.bg_panel, c.fg
	window:set_right_status(wezterm.format {
		{ Background = { Color = c.tab_bg } },
		{ Foreground = { Color = time_bg } },
		{ Text = ARROW_LEFT },
		{ Background = { Color = time_bg } },
		{ Foreground = { Color = time_fg } },
		{ Text = " " .. wezterm.strftime("%a %H:%M") .. " " },
		{ Foreground = { Color = c.orange } },
		{ Background = { Color = time_bg } },
		{ Text = ARROW_LEFT },
		{ Background = { Color = c.orange } },
		{ Foreground = { Color = c.tab_active_fg } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = "  vega " },
	})
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
-- Silent. Claude Code emits BEL on task completion; health-alarm on vega
-- uses OSC 9 desktop notifications instead, so neither flashes the window.
config.audible_bell                 = "Disabled"

-- ── Launch menu ───────────────────────────────────────────────────────────────
-- Dropdown next to the "+" tab button. First entry is the default for new tabs.
config.launch_menu = {
	{ label = "vega scratch (tmux)", args = vega_tmux("scratch") },
	{ label = "vega root  (tmux)",   args = vega_tmux("root", "/") },
	{ label = "vega work  (tmux)",   args = vega_tmux("work", "~/code") },
	{ label = "WSL ~/code",           args = { "wsl.exe", "bash", "-l", "-c", "cd ~/code && exec bash" } },
	{ label = "WSL ~",                args = { "wsl.exe", "bash", "-l" } },
	{ label = "PowerShell",           args = { "pwsh.exe" } },
}
-- Initial startup window prog (used only if gui-startup handler doesn't fire).
config.default_prog = vega_tmux("scratch")

-- ── Keys ──────────────────────────────────────────────────────────────────────
config.keys = {
	-- Ctrl+Shift+T → vega tmux 'scratch' (override default which would spawn pwsh).
	{ key = "t", mods = "CTRL|SHIFT", action = act.SpawnCommandInNewTab { args = vega_tmux("scratch") } },
	-- Ctrl+Shift+L → launcher menu (lets you pick a session or local shell).
	{ key = "l", mods = "CTRL|SHIFT", action = act.ShowLauncherArgs({ flags = "LAUNCH_MENU_ITEMS|TABS|WORKSPACES" }) },

	-- Tab navigation
	{ key = "w",          mods = "CTRL|SHIFT", action = act.CloseCurrentTab({ confirm = false }) },
	{ key = "LeftArrow",  mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "RightArrow", mods = "CTRL|SHIFT", action = act.ActivateTabRelative(1) },
	{ key = "[",          mods = "CTRL|SHIFT", action = act.ActivateTabRelative(-1) },
	{ key = "]",          mods = "CTRL|SHIFT", action = act.ActivateTabRelative(1) },

	-- Panes
	{ key = "d",          mods = "CTRL|SHIFT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "D",          mods = "CTRL|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "LeftArrow",  mods = "ALT",        action = act.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "ALT",        action = act.ActivatePaneDirection("Right") },
	{ key = "UpArrow",    mods = "ALT",        action = act.ActivatePaneDirection("Up") },
	{ key = "DownArrow",  mods = "ALT",        action = act.ActivatePaneDirection("Down") },

	-- Font size
	{ key = "=", mods = "CTRL", action = act.IncreaseFontSize },
	{ key = "-", mods = "CTRL", action = act.DecreaseFontSize },
	{ key = "0", mods = "CTRL", action = act.ResetFontSize },

	-- Search / scrollback
	{ key = "f", mods = "CTRL|SHIFT", action = act.Search({ CaseInSensitiveString = "" }) },
	{ key = "k", mods = "CTRL|SHIFT", action = act.ClearScrollback("ScrollbackAndViewport") },
}

-- ── Mouse ─────────────────────────────────────────────────────────────────────
config.mouse_bindings = {
	{
		event  = { Up = { streak = 1, button = "Left" } },
		mods   = "CTRL",
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
