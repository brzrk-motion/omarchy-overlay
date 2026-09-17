-- Five conceptual workspaces, paired across exactly two active monitors.
--
-- Pair 1 = workspaces 1 and 6, pair 2 = 2 and 7, and so on. The rightmost
-- monitor is primary and owns workspaces 1-5; the secondary owns 6-10.
-- Hyprland requires a unique workspace ID on each monitor, so the second half
-- is an implementation detail; the bindings below expose only pairs 1-5.

local pair_count = 5
local previous_pair = nil
local pair_rules = {}

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
  if not workspace or workspace.special or workspace.id < 1 or workspace.id > pair_count * 2 then
    return nil
  end

  return ((workspace.id - 1) % pair_count) + 1
end

local function active_pair()
  return conceptual_pair(hl.get_active_workspace()) or 1
end

local function active_offset(monitors)
  if #monitors == 2 then
    local monitor = hl.get_active_monitor()
    if monitor and monitor.id == monitors[1].id then
      return pair_count
    end
  end

  return 0
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
    }))
    table.insert(pair_rules, hl.workspace_rule({
      workspace = tostring(pair + pair_count),
      monitor = monitors[1].name,
      default = pair == 1,
    }))
  end
end

configure_pair_rules()
hl.on("monitor.added", function()
  hl.timer(configure_pair_rules, { timeout = 50, type = "oneshot" })
end)
hl.on("monitor.removed", function()
  hl.timer(configure_pair_rules, { timeout = 50, type = "oneshot" })
end)

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
    monitors[1]:set_workspace(tostring(pair + pair_count))
    monitors[2]:set_workspace(tostring(pair))
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
  local offset = active_offset(monitors)
  local workspace = pair + offset

  if follow and #monitors == 2 then
    local other_workspace = offset == 0 and pair + pair_count or pair
    local other_monitor = offset == 0 and monitors[1] or monitors[2]
    other_monitor:set_workspace(tostring(other_workspace))
  end

  hl.dispatch(hl.dsp.window.move({
    window = window,
    workspace = tostring(workspace),
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
