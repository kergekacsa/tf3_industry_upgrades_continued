local core = require "stardorn_industry_upgrades::/industry_upgrades/core.lua"

local PARAM_NAMES = {
    throughput = "Throughput upgrade",
    storage = "Storage upgrade",
    efficiency = "Efficiency upgrade",
    booster = "Booster upgrade",
    emission = "Environmental filter",
    workers = "Worker boost upgrade",
}

-- "None", "Level 1", ... "Level max": the values of a level parameter (value = level + 1).
local function levelValues(max)
    local values = {_("None")}
    for level = 1, max do
        values[#values + 1] = (_("Level {level}"):gsub("{level}", tostring(level)))
    end
    return values
end

function data()
    return {
        -- Parameters must not be called "_": that would hide the localisation function _().
        runFn = function(_captureParams, gameSettings, allModParams)
            local modParams = allModParams and allModParams[core.MOD_ID] or {}
            local ownTab = (tonumber(modParams[core.UI_PARAM]) or core.UI_TAB) == core.UI_TAB
            -- The balancing settings travel with every wrapped industry, see core.configure, and with
            -- them the game's economy, which decides the cargo of the deliveries.
            local settings = core.settings(modParams)
            settings.ECONOMY = core.economy(gameSettings)
            core.configure(settings)

            -- With "Workers needed per level" a worker boost could need more than 20 arrivals by line, but the
            -- base game's worker script keeps only the last 20. Once core.OWN_WORKER_SCRIPT is on, its game
            -- script runs our copy instead, which keeps as many as the boost needs (workers.script.lua);
            -- until then the workplaces stop at 40 (core.workplaceLimit). Without the setting nothing changes.
            if core.ownWorkerScript() then
                addModifier("loadGameScript", function(fileName, script)
                    local name = type(fileName) == "string" and fileName:gsub("\\", "/") or ""
                    if type(script) ~= "table" or not name:find(core.BASE_WORKERS_GAME_SCRIPT, 1, true) then return script end
                    script.updateScript = script.updateScript or {}
                    script.updateScript.fileName = core.WORKERS_SCRIPT .. "@update"
                    script.handleEventScript = script.handleEventScript or {}
                    script.handleEventScript.fileName = core.WORKERS_SCRIPT .. "@handleEvent"
                    local say = log and log.message or print
                    say(core.LOG_PREFIX .. "worker boost: " .. name .. " runs " .. core.WORKERS_SCRIPT)
                    return script
                end)
            end

            addModifier("loadConstruction", function(fileName, definition)
                if not definition.isIndustry then return definition end
                -- Export Hub (hary_export_hub) sets its updateScript params anew in its postRunFn, which
                -- drops our entry, so placing it failed. It only consumes cargo: nothing to upgrade.
                if definition.metadata and definition.metadata.haryExportHub then return definition end
                local script = definition.updateScript
                if not script or not script.fileName or script.fileName == "" then return definition end
                if script.fileName == core.UPDATE or (script.params and script.params[core.KEY]) then return definition end

                -- Keep the recipe fields at the top level: the base game's postRun filters
                -- updateScript.params.stockListConfig for the selected economy.
                local capture = {}
                for key, value in pairs(script.params or {}) do capture[key] = value end
                capture[core.KEY] = {fileName = core.absoluteRef(script.fileName, fileName), settings = settings, mod = core.MOD_ID}
                definition.updateScript = {fileName = core.UPDATE, params = capture}

                -- Declared so the levels are kept through every rebuild; not modifiable after
                -- construction, upgrades are bought in the industry window.
                definition.params = definition.params or {}
                for _index, upgrade in ipairs(core.UPGRADES) do
                    definition.params[#definition.params + 1] = {
                        key = upgrade.param,
                        name = _(PARAM_NAMES[upgrade.id]),
                        values = levelValues(upgrade.max),
                        defaultIndex = 1,
                        uiType = "ComboBox",
                        postConstructionModifiable = false,
                    }
                end
                -- The open delivery order travels with the construction like the levels: the level it
                -- builds up to per upgrade.
                for _index, upgrade in ipairs(core.UPGRADES) do
                    definition.params[#definition.params + 1] = {
                        key = upgrade.orderParam,
                        name = _("Delivery order") .. ": " .. _(PARAM_NAMES[upgrade.id]),
                        values = levelValues(upgrade.max),
                        defaultIndex = 1,
                        uiType = "ComboBox",
                        postConstructionModifiable = false,
                    }
                end

                -- Own "Upgrades" tab in the industry window, unless another mod already owns the window.
                local window = definition.entityWindowScript
                if ownTab and (not window or not window.fileName or window.fileName == "") then
                    definition.entityWindowScript = {fileName = core.WINDOW_SCRIPT}
                end
                return definition
            end)
        end,
    }
end
