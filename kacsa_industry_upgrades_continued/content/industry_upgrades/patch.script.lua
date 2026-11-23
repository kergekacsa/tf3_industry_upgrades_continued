-- Keeps the delivery order's rule out of the industry window. The order has its own
-- card with the landmark's bar (ui.orderBar); as a booster rule it also showed in the booster card
-- ("+0%") and made the production card green while it consumed.
--
-- booster row: the card makes one CargoBoosterRow per booster rule (industry_eow.script.tl,
--   IndustryBoosters). That recipe is local to the base game's file, and recipe names are not unique,
--   so it is found as the only wrapper of builtin.Row besides industry_react_util.WorkplacesBoosterRow
--   (the base game has no other). A replacement (react's recipeReplace, looked up on every call)
--   returns nothing for the order's rule, and the card's row list skips it. Nor for a rule that is
--   gone: the card keeps its list of booster rules from the step before (IndustryBoosters'
--   ruleIndexState:old()), so right after the rebuild that drops the order's rule (completion or
--   cancel) it renders that row once more, and the base game's row then indexes the missing rule and
--   fails (industry_util.getNumCargosOfRule). The base game's booster rules never go away.
-- boost: the window calls an industry boosted once industry_util.getIndustryBoost is above 1, and the
--   order's rule needs a boostFactor above 0 (core.ORDER_BOOST). The wrapped function divides the
--   order's factor out again.
-- production row: as a plain rule (config.ORDER_RULE) the order's rule showed in the production card as
--   a second production line, the order's cargo with figures looked up for other rules (seen
--   2026-10-11). The card makes one industry_react_util.ProductionRuleWidget per non-booster rule
--   (ProductionRulesWidget); a replacement returns nothing for the order's rule, and for a rule that is
--   gone (the card keeps its rule list from the step before, as the booster card does).
-- HUD cargo: the icons over an industry (selected industry, its suppliers and buyers), the cargo flow
--   layer, the line manager's HUD and the statistics take an industry's inputs from its rules
--   (cargo_react_util.makeCargoInputOutputDataForStocklist), so the order's cargo showed as inputs
--   (seen 2026-10-11). The wrapped function leaves the cargo of the order's stocks out. Industries
--   making that cargo are still marked as suppliers when the industry is selected (the matching reads
--   the stocks, cargo_util.getCargoTypesForStockList).
-- worker row: the worker boost can be partial (workers.script.lua), so the row
--   (industry_react_util.WorkplacesBoosterRow, in the Industry tab and the perk window) is replaced by
--   one that shows the boost the industry has now with "Max." and its full boost under it, like the
--   production card, and ticks only at the full boost. The base game's row shows the full boost and
--   ticks at any boost above x1.
-- Anything unexpected leaves the window as it is.
local core = require "kacsa_industry_upgrades_continued::/industry_upgrades/core.lua"
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local industryUtil = ug_require "::/gui/main/industry_util.tl"
local industryReactUtil = ug_require "::/gui/entity_window/industry_react_util.tl"
local industryEow = ug_require "::/gui/entity_window/industry/industry_eow.script.tl" -- registers CargoBoosterRow
local cargoReactUtil = ug_require "::/gui/main/cargo_react_util.tl"
local engineReactUtil = ug_require "::/gui/main/engine_react_util.tl"
local entityWindowUtil = ug_require "::/gui/entity_window/entity_window_util.tl"
local guiReactUtil = ug_require "::/gui/main/gui_react_util.tl"
local langUtil = ug_require "::/scripts/lang_util.tl"
local productivityUtil = ug_require "::/industries/industry_productivity_util.tl"

local INSTALLED = "industryUpgradesPatched" -- marker on the patched base game module
local WORKER_ROW_INSTALLED = "industryUpgradesWorkerRow" -- marker on industry_react_util for the worker row
local FULL_BOOST_TOLERANCE = 0.001
local workerRow = nil -- our worker row recipe, registered with its patch (partialWorkerRow)

-- Whether the booster card's row for a rule shows nothing: the order's rule, or a rule that is gone.
-- A stock list that cannot be read (the industry is gone) keeps the base game's behaviour.
local function hiddenRow(entity, ruleNumber)
    local ok, hidden = pcall(function()
        local stockList = api.engine.getComponent(entity, api.type.ComponentType.STOCK_LIST)
        if not stockList then return false end
        local index = tonumber(ruleNumber)
        if not index or index < 1 or index > #stockList.rules then return true end
        return core.isOrderRule(stockList.rules[index])
    end)
    return ok and hidden == true
end

local function cargoBoosterRowId()
    local rowId = react.GetRecipeId(builtin.Row)
    local workplacesId = react.GetRecipeId(industryReactUtil.WorkplacesBoosterRow)
    if not rowId or not workplacesId then error("builtin.Row or WorkplacesBoosterRow not found", 0) end
    local ownId = workerRow and react.GetRecipeId(workerRow) -- our worker row wraps builtin.Row as well
    local found = {}
    for id, meta in pairs(_react.recipeMetas) do
        if type(meta) == "table" and meta.innerRecipeId == rowId and id ~= workplacesId and id ~= ownId then found[#found + 1] = id end
    end
    if #found ~= 1 then error(#found .. " candidates for CargoBoosterRow", 0) end
    return found[1]
end

-- Returns true if it patched now, false if already patched; raises an error if the base game changed.
local function hideBoosterRow()
    if industryEow[INSTALLED] then return false end
    if type(_react) ~= "table" or type(_react.recipeReplace) ~= "table" or type(_react.originalRecipeFn) ~= "table"
        or type(_react.recipeMetas) ~= "table" then
        error("react internals not available", 0)
    end
    local id = cargoBoosterRowId()
    -- another mod's replacement stays in the chain
    local makeRow = _react.recipeReplace[id] or _react.originalRecipeFn[id]
    if type(makeRow) ~= "function" then error("CargoBoosterRow not found", 0) end
    industryEow[INSTALLED] = true
    _react.recipeReplace[id] = function(params, ...)
        if type(params) == "table" and hiddenRow(params.entity, params.ruleNumber) then return nil end
        return makeRow(params, ...)
    end
    return true
end

-- ruleBoosts carry each booster rule's factor, which tells the order's rule apart without reading the
-- stock list again (getIndustryBoost runs several times per step).
local function withoutOrderBoost(result)
    pcall(function()
        local boost = result.boost
        for _index, ruleBoost in pairs(result.ruleBoosts or {}) do
            if ruleBoost.boosted and core.isOrderRule({booster = true, boostFactor = ruleBoost.boostFactor}) then
                boost = boost / (1 + ruleBoost.boostFactor)
            end
        end
        -- the division need not land on 1 exactly, and the window asks for "above 1"
        if math.abs(boost - 1) < 1e-6 then boost = 1 end
        result.boost = boost
    end)
    return result
end

local function hideOrderBoost()
    if industryUtil[INSTALLED] then return false end
    local getIndustryBoost = industryUtil.getIndustryBoost
    if type(getIndustryBoost) ~= "function" then error("industry_util.getIndustryBoost not found", 0) end
    industryUtil[INSTALLED] = true
    industryUtil.getIndustryBoost = function(...)
        return withoutOrderBoost(getIndustryBoost(...))
    end
    return true
end

-- Returns true if it patched now, false if already patched; raises an error if the base game changed.
local function hideProductionRow()
    if industryReactUtil[INSTALLED] then return false end
    if type(_react) ~= "table" or type(_react.recipeReplace) ~= "table" or type(_react.originalRecipeFn) ~= "table" then
        error("react internals not available", 0)
    end
    local id = industryReactUtil.ProductionRuleWidget and react.GetRecipeId(industryReactUtil.ProductionRuleWidget)
    if not id then error("ProductionRuleWidget not found", 0) end
    -- another mod's replacement stays in the chain
    local makeRow = _react.recipeReplace[id] or _react.originalRecipeFn[id]
    if type(makeRow) ~= "function" then error("ProductionRuleWidget has no recipe function", 0) end
    industryReactUtil[INSTALLED] = true
    _react.recipeReplace[id] = function(params, ...)
        if type(params) == "table" and hiddenRow(params.entity, params.ruleNumber) then return nil end
        return makeRow(params, ...)
    end
    return true
end

-- The order's cargo left out of the inputs (CargoInputOutputData: {inputs = {{cargoType, ...}}, outputs}).
local function withoutOrderCargo(entity, result)
    pcall(function()
        if type(result) ~= "table" or type(result.inputs) ~= "table" then return end
        local stockList = api.engine.getComponent(entity, api.type.ComponentType.STOCK_LIST)
        local cargo = stockList and core.orderStockCargo(stockList.stocks, stockList.rules)
        if not cargo or next(cargo) == nil then return end
        local kept = {}
        for _index, item in ipairs(result.inputs) do
            if not cargo[item.cargoType] then kept[#kept + 1] = item end
        end
        result.inputs = kept
    end)
    return result
end

local function hideHudCargo()
    if cargoReactUtil[INSTALLED] then return false end
    local make = cargoReactUtil.makeCargoInputOutputDataForStocklist
    if type(make) ~= "function" then error("cargo_react_util.makeCargoInputOutputDataForStocklist not found", 0) end
    cargoReactUtil[INSTALLED] = true
    cargoReactUtil.makeCargoInputOutputDataForStocklist = function(entity, ...)
        return withoutOrderCargo(entity, make(entity, ...))
    end
    return true
end

-- The worker row's figures: workers arrived by line and needed for the full boost, the boost now and
-- the full boost (productivity factors, 1 = none).
local function workerFigures(entity)
    local figures = {arrived = 0, needed = 0, boost = 1, full = 1}
    pcall(function()
        local persons = api.engine.getComponent(entity, api.type.ComponentType.PERSON_CAPACITY)
        if not persons or persons.capacity <= 0 then return end
        figures.arrived = #productivityUtil.getVisitors(entity)
        figures.needed = core.workersNeeded(persons.capacity, productivityUtil.RequiredWorkersFractionForBoost)
        figures.boost = tonumber(productivityUtil.getIndustryProductivity(entity)) or 1
        figures.full = tonumber(productivityUtil.getPersonCapacityPotentialBoost(entity)) or 1
    end)
    return figures
end

local function boostText(factor)
    return "+" .. api.util.toStringPercentPrecision(factor - 1, 0)
end

local function registerWorkerRow()
    return react.RegisterWrapperRecipe("IndustryUpgradesWorkerRow", builtin.Row, function(params)
        local state = engineReactUtil.useStepState(function() return workerFigures(params.entity) end)
        local figures = state:old()
        local full = figures.full > 1 and figures.boost >= figures.full - FULL_BOOST_TOLERANCE
        local class = full and "boosted" or ""
        local function cell(child)
            return builtin.Component{meta = {class = class}, layout = builtin.BoxLayout{
                orientation = builtin.type.Orientation.Horizontal, children = {child}}}
        end
        local counted = math.min(figures.arrived, figures.needed)
        local workers = {currentWorkers = langUtil.formatInt(figures.arrived), neededWorkers = langUtil.formatInt(figures.needed)}
        return builtin.Row{cells = {
            cell(industryReactUtil.IconAndLabelWidget{
                icon = "::/gui/entity_window/icons/symbol_person.tga",
                iconTooltip = _("Workers"),
                count = langUtil.format("{currentWorkers}/{neededWorkers}", workers),
                countTooltip = langUtil.format(_("{currentWorkers} of {neededWorkers} Workers"), workers),
            }),
            cell(entityWindowUtil.ProgressDisplay{
                tooltip = langUtil.format("{count}/{total}", {count = langUtil.formatInt(counted), total = workers.neededWorkers}),
                value = figures.needed > 0 and counted / figures.needed or 0,
            }),
            cell(builtin.BoxLayout{orientation = builtin.type.Orientation.Vertical, children = {
                guiReactUtil.IconLabelIndicator{
                    meta = {class = "boost-factor-indicator"},
                    iconPath = "::/gui/entity_window/icons/building_industry.tga",
                    label = boostText(figures.boost),
                },
                builtin.TextView{meta = {class = "font-scale-annotation", tooltip = _("Max.")},
                    text = _("Max.") .. " " .. boostText(figures.full)},
            }}),
            cell(builtin.ImageView{meta = {class = "boost-tick-icon"}, path = "::/gui/entity_window/icons/circle_check.tga"}),
        }}
    end)
end

-- Returns true if it patched now, false if already patched; raises an error if the base game changed or
-- another mod replaces the row already.
local function partialWorkerRow()
    if industryReactUtil[WORKER_ROW_INSTALLED] then return false end
    if type(_react) ~= "table" or type(_react.recipeReplace) ~= "table" then error("react internals not available", 0) end
    local id = industryReactUtil.WorkplacesBoosterRow and react.GetRecipeId(industryReactUtil.WorkplacesBoosterRow)
    if not id then error("WorkplacesBoosterRow not found", 0) end
    if _react.recipeReplace[id] then error("another mod replaces it", 0) end
    workerRow = workerRow or registerWorkerRow()
    industryReactUtil[WORKER_ROW_INSTALLED] = true
    _react.recipeReplace[id] = function(params, ...) return workerRow(params, ...) end
    return true
end

-- what a part does: hide (the order's parts) or show (the worker row's partial boost)
local PARTS = {
    {name = "the order's booster row", done = "hidden", install = hideBoosterRow},
    {name = "the order's boost", done = "hidden", install = hideOrderBoost},
    {name = "the order's production row", done = "hidden", install = hideProductionRow},
    {name = "the order's HUD cargo", done = "hidden", install = hideHudCargo},
    {name = "the partial worker boost", done = "shown in the worker row", install = partialWorkerRow},
}

-- react-replacement-config: runs once before the GUI starts rendering. A part that fails (e.g. after a
-- game update) is reported and left out; the others still work.
local function doReplace(_replacementApi)
    local done = {}
    for _index, part in ipairs(PARTS) do
        local ok, result = pcall(part.install)
        if not ok then
            log.warning(core.LOG_PREFIX .. "window: " .. part.name .. " stays as in the base game, " .. tostring(result))
        elseif result then
            done[#done + 1] = part.name .. " " .. part.done
        end
    end
    if #done > 0 then log.message(core.LOG_PREFIX .. "window: " .. table.concat(done, ", ")) end
end

function data()
    return {doReplace = doReplace, hideBoosterRow = hideBoosterRow, hideOrderBoost = hideOrderBoost, hideProductionRow = hideProductionRow,
        hideHudCargo = hideHudCargo, partialWorkerRow = partialWorkerRow}
end
