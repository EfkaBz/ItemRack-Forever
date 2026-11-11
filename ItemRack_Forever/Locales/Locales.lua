-- ItemRack Forever: localization. Strings are written in English in the code; the French
-- ones are in ns.LFR (Locales/frFR.lua). The language is a setting (English by default),
-- read when the saved variables load: strings used before that are looked up again later.
local _, ns = ...

ns.LFR = {}
ns.LANGUAGES = { { "enUS", "English" }, { "frFR", "Français" } }
local lang = "enUS"

ns.L = setmetatable({}, { __index = function(_, k)
  if lang == "frFR" then
    local v = ns.LFR[k]
    if v then return v end
  end
  return k
end })

function ns.SetLanguage(code)
  lang = (code == "frFR") and "frFR" or "enUS"
end

function ns.GetLanguage() return lang end
