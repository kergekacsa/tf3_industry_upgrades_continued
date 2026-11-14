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
-- Anything unexpected leaves the window as it is.
local core = require "stardorn_industry_upgrades::/industry_upgrades/core.lua"
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local industryUtil = ug_require "::/gui/main/industry_util.tl"
local industryReactUtil = ug_require "::/gui/entity_window/industry_react_util.tl"
local industryEow = ug_require "::/gui/entity_window/industry/industry_eow.script.tl" -- registers CargoBoosterRow
local cargoReactUtil = ug_require "::/gui/main/cargo_react_util.tl"

local INSTALLED = "industryUpgradesPatched" -- marker on the patched base game module

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
    local found = {}
    for id, meta in pairs(_react.recipeMetas) do
        if type(meta) == "table" and meta.innerRecipeId == rowId and id ~= workplacesId then found[#found + 1] = id end
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

local PARTS = {
    {name = "booster row", install = hideBoosterRow},
    {name = "boost", install = hideOrderBoost},
    {name = "production row", install = hideProductionRow},
    {name = "HUD cargo", install = hideHudCargo},
}

-- react-replacement-config: runs once before the GUI starts rendering. A part that fails (e.g. after a
-- game update) is reported and left out; the other still works.
local function doReplace(_replacementApi)
    local done = {}
    for _index, part in ipairs(PARTS) do
        local ok, result = pcall(part.install)
        if not ok then
            log.warning(core.LOG_PREFIX .. "window: the order's " .. part.name .. " stays, " .. tostring(result))
        elseif result then
            done[#done + 1] = part.name
        end
    end
    if #done > 0 then log.message(core.LOG_PREFIX .. "window: the order's " .. table.concat(done, " and ") .. " hidden") end
end

function data()
    return {doReplace = doReplace, hideBoosterRow = hideBoosterRow, hideOrderBoost = hideOrderBoost, hideProductionRow = hideProductionRow,
        hideHudCargo = hideHudCargo}
end
