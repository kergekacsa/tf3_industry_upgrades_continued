local util = ug_require "::/scripts/util.tl"
local core = require "stardorn_industry_upgrades::/industry_upgrades/core.lua"

function data()
    return {
        update = function(capture, params)
            local own = capture[core.KEY]
            core.configure(own.settings)
            local original = util.useFn(own.fileName)
            assert(original, "Industry Upgrades: original construction script is missing")
            local originalCapture = {}
            for key, value in pairs(capture) do
                if key ~= core.KEY then originalCapture[key] = value end
            end
            local result = original(originalCapture, params)
            -- industryutil's terminateConstructionHook only adjusts inputs/outputs for fields; the
            -- values changed here (capacity, consumption, boost factors, stocks, emissions) are untouched.
            return core.applyUpgrades(result, params)
        end,
    }
end
