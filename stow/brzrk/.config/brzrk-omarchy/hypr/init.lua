-- BRZRK creative workstation overlay for Omarchy Quattro.
-- User-owned only. Never edit /usr/share/omarchy.

dofile((os.getenv("HOME") or "") .. "/.config/brzrk-omarchy/hypr/workspaces.lua")

local creative_classes = {
  "^[Bb]lender$",
  "^blender$",
  "^org%.blender%.Blender$",
  "^[Kk]rita$",
  "^org%.kde%.krita$",
  "^[Rr]esolve$",
  "^DaVinci Resolve$",
  "^com%.blackmagicdesign%.resolve$",
  "^[Pp]lasticity$",
  "^[Ss]ubstance.*$",
  "^Adobe Substance 3D.*$",
  "^[Nn]atron$",
  "^[Kk]denlive$",
  "^org%.kde%.kdenlive$",
}

local function creative_window(class_pattern)
  -- Creative/color-critical apps should not inherit Omarchy's subtle opacity.
  o.window(class_pattern, {
    tag = "-default-opacity",
  })

  -- Keep the main DCC window tiled but maximized so it behaves like a normal
  -- full-size workstation application rather than a floating tiling-WM oddity.
  o.window({
    class = class_pattern,
    modal = false,
    float = false,
  }, {
    maximize = true,
  })

  -- Conventional desktop behavior for real modal dialogs.
  o.window({
    class = class_pattern,
    modal = true,
  }, {
    float = true,
    center = true,
    tag = "-default-opacity",
  })
end

for _, class_pattern in ipairs(creative_classes) do
  creative_window(class_pattern)
end

-- Fallbacks for tool/dialog windows that do not reliably advertise modal=true.
local creative_dialog_titles = {
  ".*[Pp]references.*",
  ".*[Ss]ettings.*",
  ".*[Ff]ile [Bb]rowser.*",
  ".*[Oo]pen [Ff]ile.*",
  ".*[Ss]ave [Ff]ile.*",
}

for _, title_pattern in ipairs(creative_dialog_titles) do
  o.window({ title = title_pattern, float = true }, { center = true })
end
