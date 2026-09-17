-- BRZRK creative workstation overlay for Omarchy Quattro.
-- Loaded last from hyprland.lua via require_optional.module("hypr.brzrk").

local creative_classes = {
  "^[Bb]lender$",
  "^org%.blender%.Blender$",
  "^[Kk]rita$",
  "^org%.kde%.krita$",
  ".*[Rr]esolve.*",
  "^[Pp]lasticity$",
  "^[Ss]ubstance.*$",
  "^Adobe Substance 3D.*$",
  "^[Nn]atron$",
  "^[Kk]denlive$",
  "^org%.kde%.kdenlive$",
}

local creative_dialog_titles = {
  ".*[Pp]references.*",
  ".*[Ss]ettings.*",
  ".*[Ff]ile [Bb]rowser.*",
  ".*[Oo]pen [Ff]ile.*",
  ".*[Ss]ave [Ff]ile.*",
}

for _, class_pattern in ipairs(creative_classes) do
  -- Effects, not match filters: Omarchy's Resolve rule floats first, so a
  -- float=false matcher would never see those windows.
  o.window(class_pattern, {
    tag = "-default-opacity",
    tile = true,
    maximize = true,
  })

  o.window({
    class = class_pattern,
    modal = true,
  }, {
    float = true,
    center = true,
    tag = "-default-opacity",
  })

  for _, title_pattern in ipairs(creative_dialog_titles) do
    o.window({ class = class_pattern, title = title_pattern, float = true }, { center = true })
  end
end

-- Five conceptual workspaces, paired across exactly two active monitors.
--
-- The rightmost primary monitor owns numeric workspaces 1-5. The secondary
-- monitor uses matching named workspaces, which keeps Hyprland's required
-- unique workspace identities from appearing as extra numbers in the bar.

local pair_count = 5
local previous_pair = nil
local pair_rules = {}

local function secondary_workspace_name(pair)
  return "brzrk-pair-" .. tostring(pair) .. "-secondary"
end

local function secondary_workspace_selector(pair)
  return "name:" .. secondary_workspace_name(pair)
end

local function monitors_left_to_right()
  local monitors = hl.get_monitors()
  table.sort(monitors, function(left, right)
    local left_x = left.position and left.position.x or 0
    local right_x = right.position and right.position.x or 0
    if left_x ~= right_x then
      return left_x < right_x
    end

    return left.id < right.id
  end)
  return monitors
end

local function conceptual_pair(workspace)
  if not workspace or workspace.special then
    return nil
  end

  if workspace.id >= 1 and workspace.id <= pair_count then
    return workspace.id
  end

  local named_pair = workspace.name and workspace.name:match("^brzrk%-pair%-(%d+)%-secondary$")
  named_pair = tonumber(named_pair)
  if named_pair and named_pair >= 1 and named_pair <= pair_count then
    return named_pair
  end

  return nil
end

local function active_pair()
  return conceptual_pair(hl.get_active_workspace()) or 1
end

local function active_on_secondary(monitors)
  if #monitors == 2 then
    local monitor = hl.get_active_monitor()
    if monitor and monitor.id == monitors[1].id then
      return true
    end
  end

  return false
end

local function configure_pair_rules()
  for _, rule in ipairs(pair_rules) do
    rule:set_enabled(false)
  end
  pair_rules = {}

  local monitors = monitors_left_to_right()
  if #monitors ~= 2 then
    return
  end

  for pair = 1, pair_count do
    table.insert(pair_rules, hl.workspace_rule({
      workspace = tostring(pair),
      monitor = monitors[2].name,
      default = pair == 1,
      persistent = true,
    }))
    table.insert(pair_rules, hl.workspace_rule({
      workspace = secondary_workspace_selector(pair),
      monitor = monitors[1].name,
      default = pair == 1,
      persistent = true,
    }))
  end
end

configure_pair_rules()
local function schedule_pair_rules()
  hl.timer(configure_pair_rules, { timeout = 50, type = "oneshot" })
end
hl.on("monitor.added", schedule_pair_rules)
hl.on("monitor.removed", schedule_pair_rules)

-- Workspace focus normally warps the cursor. With focus-follows-mouse that can
-- steal focus between the two dispatches and put the pair out of sync.
hl.config({ cursor = { no_warps = true } })

local function switch_pair(pair, remember_previous)
  local monitors = monitors_left_to_right()
  local old_pair = active_pair()

  if remember_previous and old_pair ~= pair then
    previous_pair = old_pair
  end

  if #monitors == 2 then
    -- Change the secondary directly so it never receives keyboard focus, then
    -- explicitly focus the rightmost primary half of the pair.
    monitors[1]:set_workspace({ workspace = secondary_workspace_name(pair) })
    monitors[2]:set_workspace({ workspace = tostring(pair) })
    hl.dispatch(hl.dsp.focus({ workspace = tostring(pair) }))
  else
    hl.dispatch(hl.dsp.focus({ workspace = tostring(pair) }))
  end
end

local function cycle_pair(offset)
  local pair = ((active_pair() - 1 + offset) % pair_count) + 1
  switch_pair(pair, true)
end

local function move_window_to_pair(pair, follow)
  local window = hl.get_active_window()
  if not window then
    return
  end

  local monitors = monitors_left_to_right()
  local on_secondary = active_on_secondary(monitors)
  local workspace = on_secondary and secondary_workspace_selector(pair) or tostring(pair)

  if follow and #monitors == 2 then
    local other_workspace = on_secondary and tostring(pair) or secondary_workspace_name(pair)
    local other_monitor = on_secondary and monitors[2] or monitors[1]
    other_monitor:set_workspace({ workspace = other_workspace })
  end

  hl.dispatch(hl.dsp.window.move({
    window = window,
    workspace = workspace,
    follow = follow,
  }))
end

-- Remove Omarchy's individual workspace bindings (1-10), then expose five
-- paired workspaces. Keycodes 10-19 are the physical number-row keys 1-0.
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  hl.unbind("SUPER + " .. key)
  hl.unbind("SUPER + SHIFT + " .. key)
  hl.unbind("SUPER + SHIFT + ALT + " .. key)
end

for pair = 1, pair_count do
  local key = "code:" .. tostring(pair + 9)

  o.bind("SUPER + " .. key, "Switch to workspace pair " .. pair, function()
    switch_pair(pair, true)
  end)

  o.bind("SUPER + SHIFT + " .. key, "Move window to workspace pair " .. pair, function()
    move_window_to_pair(pair, true)
  end)

  o.bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace pair " .. pair, function()
    move_window_to_pair(pair, false)
  end)
end

hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
hl.unbind("SUPER + CTRL + TAB")
hl.unbind("SUPER + mouse_down")
hl.unbind("SUPER + mouse_up")

o.bind("SUPER + TAB", "Next workspace pair", function()
  cycle_pair(1)
end)

o.bind("SUPER + SHIFT + TAB", "Previous workspace pair", function()
  cycle_pair(-1)
end)

o.bind("SUPER + CTRL + TAB", "Former workspace pair", function()
  if previous_pair then
    local target = previous_pair
    previous_pair = active_pair()
    switch_pair(target, false)
  end
end)

o.bind("SUPER + mouse_down", "Scroll workspace pairs forward", function()
  cycle_pair(1)
end)

o.bind("SUPER + mouse_up", "Scroll workspace pairs backward", function()
  cycle_pair(-1)
end)

-- Reconcile either monitor from an older configuration after all persistent
-- pair workspaces have been created. This also establishes the matching pair
-- on login without transferring focus to the secondary monitor.
hl.timer(function()
  switch_pair(active_pair(), false)
end, { timeout = 50, type = "oneshot" })
