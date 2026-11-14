-- Pure functions shared by the load-time modifier, the construction script, the game script and the GUI.
local config = require "kacsa_industry_upgrades::/industry_upgrades/config.lua"

local core = {}

core.MOD_ID = "kacsa_industry_upgrades"
core.KEY = "industryUpgrades"                         -- our entry in updateScript.params
core.UPDATE = "kacsa_industry_upgrades::/industry_upgrades/construction.script@update"
core.GAME_SCRIPT = "kacsa_industry_upgrades::/industry_upgrades/upgrades.gs"
core.WINDOW_SCRIPT = "kacsa_industry_upgrades::/industry_upgrades/window.script@entityWindowFn"
-- The base game's worker boost script, and our copy that can run instead (core.ownWorkerScript,
-- workers.script.lua).
core.BASE_WORKERS_GAME_SCRIPT = "industries/industry_workers.gs"
core.WORKERS_SCRIPT = "kacsa_industry_upgrades::/industry_upgrades/workers.script"
-- The workplaces an industry was last built with and its own before the upgrade, in its construction's
-- metadata (persistentMetadata in the engine, like the base game's workersBoostFactor).
core.WORKPLACES_META = "industryUpgradesWorkplaces"
core.WORKPLACES_BASE_META = "industryUpgradesWorkplacesBase"

-- Mod setting "Upgrades display" (1-based like all mod params): 1 = own tab, 2 = card in the industry tab.
core.UI_PARAM = "uiMode"
core.UI_TAB = 1
core.EVENT_ID = "IndustryUpgrades"
core.EVENT_BUY = "industryUpgradesBuy"

-- Construction parameters travel with the construction through every rebuild.
core.THROUGHPUT_PARAM = "industryUpgradesThroughput"  -- declared, value = level + 1
core.CARRY_POINTS_PARAM = "industryUpgradesCarryPoints"
core.CARRY_EXP_PARAM = "industryUpgradesCarryExp"
core.CARRY_TIME_PARAM = "industryUpgradesCarryTime"

-- Shape of the order's stocks and rules a construction was built with. A construction with an open
-- order and another format is rebuilt, so a later change of the shape never meets old stocks.
core.ORDER_FORMAT_PARAM = "industryUpgradesOrderFormat"
-- 5: the order's rule is a booster; a plain rule (config.ORDER_RULE): 6 with long cycles over the
-- minimum duration (blocked production), 7 with short cycles in at most ORDER_STEPS lots
core.ORDER_FORMAT = config.ORDER_RULE == "booster" and 5 or 7
-- boostFactor of a booster order rule: a booster without effect worth mentioning (the base game
-- multiplies production by 1 + boostFactor of every active booster). Vanilla boosters have 0.5 or
-- more. 0 is not possible: building the stock list asserts "slr.boostFactor > .0f" (a savegame with
-- an open order crashed while loading). The industry window counts 0.001 as a boost (green line in
-- the production card); patch.script takes the order's rule out of that again.
core.ORDER_BOOST = 0.001
-- A plain order rule runs capacity x consumptionFactor cycles a year, like every rule. capacity is a
-- whole number in the engine, so it gets the rate x ORDER_RATE_SCALE and consumptionFactor
-- 1 / ORDER_RATE_SCALE: the rate can be any fraction (the minimum duration holds exactly), and the tiny
-- consumptionFactor tells the order's rule apart (the base game's production rules have the industry's
-- size, about 0.6, and stay above 0.01 with every upgrade and malus).
core.ORDER_RATE_SCALE = 1000
core.ORDER_FACTOR = 1 / core.ORDER_RATE_SCALE
-- An industry runs one of its plain rules at a time (verified 2026-10-11: the order's cycle waited for
-- the production cycle, and production stood still while the order's ran). So a plain order rule
-- runs short cycles (ORDER_FAST_RATE a year, about 2.4 game hours each) that hold up production only
-- briefly, in at most ORDER_STEPS cycles (lots of a tenth), so it needs few turns between the
-- production's cycles (a farm runs only about five a year). The minimum duration is the game
-- script's then (core.orderTimeOver).
core.ORDER_FAST_RATE = 3650
core.ORDER_STEPS = 10
-- The order's rule gets its turn after each cycle of the production (verified 2026-10-11: no cycle at a
-- coal mine for a month with cargo in stock, its production cycle takes 1.4 months). So an order
-- takes at most as many cycles as ORDER_TURN_SHARE of the production cycles that fit into its minimum
-- duration (core.orderSteps): a farm (about five cycles a year) does a single level in three.
core.ORDER_TURN_SHARE = 0.8
core.EVENT_CANCEL = "industryUpgradesCancel"
-- Planning: {construction, upgrade, change = 1 or -1} adds or removes the highest planned level;
-- start opens the delivery order for the whole plan, discard drops the plan.
core.EVENT_PLAN = "industryUpgradesPlan"
core.EVENT_START = "industryUpgradesStart"
core.EVENT_DISCARD = "industryUpgradesDiscard"
-- The base game's event for cargo an industry is about to consume (see landmarks.script.tl).
core.CONSUMED_SOURCE = "StockListSystem"
core.CONSUMED_EVENT = "ItemsAboutToBeConsumed"
core.LOG_PREFIX = "Industry Upgrades: "

-- The most levels of an upgrade under the current config. Efficiency: the levels of its setting, but
-- only as many as keep the input at EFFICIENCY_MIN or above (10 % steps: 5, 5 % steps: 10).
local function maxLevel(id)
    if id == "throughput" then return config.MAX_LEVEL end
    if id == "efficiency" then
        if config.EFFICIENCY_STEP <= 0 then return 0 end
        return math.max(0, math.min(config.EFFICIENCY_LEVELS, math.floor((1 - config.EFFICIENCY_MIN) / config.EFFICIENCY_STEP + 1e-9)))
    end
    return config.OTHER_MAX_LEVEL
end

-- All upgrades. Each level lives in its own declared construction parameter (value = level + 1).
core.UPGRADES = {
    {id = "throughput", param = core.THROUGHPUT_PARAM},
    {id = "storage", param = "industryUpgradesStorage"},
    {id = "efficiency", param = "industryUpgradesEfficiency"},
    {id = "booster", param = "industryUpgradesBooster"},
    {id = "emission", param = "industryUpgradesEmission"},
    {id = "workers", param = "industryUpgradesWorkers"},
}
core.UPGRADE_BY_ID = {}
for _index, upgrade in ipairs(core.UPGRADES) do
    upgrade.max = maxLevel(upgrade.id)
    core.UPGRADE_BY_ID[upgrade.id] = upgrade
    -- the level an open order builds up to (declared, value = level + 1, 1 = not in the order)
    upgrade.orderParam = "industryUpgradesOrder" .. upgrade.id:sub(1, 1):upper() .. upgrade.id:sub(2)
end

core.SETTINGS = require "kacsa_industry_upgrades::/industry_upgrades/settings.lua"
local DEFAULTS = {}
for key, value in pairs(config) do DEFAULTS[key] = value end

-- The chosen mod settings as config values. modParams: this mod's entry of allModParams, the
-- choices 1-based; a missing or unknown choice keeps the default.
function core.settings(modParams)
    local result = {}
    for _index, setting in ipairs(core.SETTINGS) do
        local choice = tonumber(modParams and modParams[setting.key])
        local value = choice and setting.values[choice]
        if value == nil then value = DEFAULTS[setting.config] end
        result[setting.config] = value
    end
    return result
end

-- The economy each base game climate brings (climates/*.clima.lua).
core.CLIMATE_ECONOMY = {temperate = "temperate", dry = "dry", subarctic = "subarctic", tropical = "tropic"}

-- A game setting: runFn gets the settings as a table (settings.climate, as the base game's
-- base_mod.lua reads it), preRunFn as pairs ({{"economy", value}}, the base game's mod.script).
local function gameSetting(settings, key)
    if type(settings) ~= "table" then return nil end
    if settings[key] ~= nil then return settings[key] end
    for _index, entry in ipairs(settings) do
        if type(entry) == "table" and entry[1] == key then return entry[2] end
    end
    return nil
end

-- The file name of a base game resource ("::/economy/dry.eco", "eco" -> "dry"); nil for one of
-- another mod (a namespace before "::") or none.
local function baseFileName(value, extension)
    if type(value) ~= "string" then return nil end
    local namespace = value:match("^(.-)::")
    if namespace and namespace ~= "" then return nil end
    return value:match("([%w_]+)%." .. extension .. "$")
end

-- The economy whose cargo the deliveries ask for, from the game settings: the base game's economy by
-- its file name ("::/economy/dry.eco" -> "dry"), "" when there is none or it comes from another mod.
-- "All industries" has every cargo, so there the base game climate decides (subarctic climate ->
-- "subarctic"); "all" with another mod's climate.
function core.economy(settings)
    local economy = baseFileName(gameSetting(settings, "economy"), "eco") or ""
    if economy == "all" then
        economy = core.CLIMATE_ECONOMY[baseFileName(gameSetting(settings, "climate"), "clima") or ""] or economy
    end
    return economy
end

-- Applies settings (from core.settings, nil = defaults) in this Lua state. The load script, the
-- construction script, the game script and the GUI each run in a state of their own; the settings
-- travel with every wrapped industry construction (updateScript.params[core.KEY].settings).
function core.configure(settings)
    for key, value in pairs(DEFAULTS) do config[key] = value end
    for key, value in pairs(settings or {}) do
        local default = DEFAULTS[key]
        if type(default) == "number" and tonumber(value) then
            config[key] = tonumber(value)
        elseif type(default) == "string" and type(value) == "string" then
            config[key] = value
        end
    end
    for _index, upgrade in ipairs(core.UPGRADES) do
        upgrade.max = maxLevel(upgrade.id)
    end
end

-- Version of the game script state. 2 = EXP system (version 1 awarded up to 3 points per month),
-- 3 = a bought level per upgrade (version 2 kept one pending upgrade per industry), 4 = delivery
-- orders and plans.
core.STATE_VERSION = 4

-- Game time (ms) a rebuild waits for further purchases at the same industry, so levels bought one
-- after another end up in one rebuild. Rebuilding an oil platform freezes the game for a while.
core.BUNDLE_WAIT = 5000

local function clamp(level, max)
    level = math.floor(tonumber(level) or 0)
    return math.max(0, math.min(max, level))
end

-- ComboBox values are 1-based: value 1 = no upgrade.
function core.level(params, id)
    local upgrade = core.UPGRADE_BY_ID[id]
    local value = params and tonumber(params[upgrade.param])
    if not value then return 0 end
    return clamp(value - 1, upgrade.max)
end

function core.setLevel(params, id, level)
    local upgrade = core.UPGRADE_BY_ID[id]
    params[upgrade.param] = clamp(level, upgrade.max) + 1
end

function core.throughputLevel(params) return core.level(params, "throughput") end
function core.setThroughputLevel(params, level) core.setLevel(params, "throughput", level) end

-- record.targets: the bought level per upgrade (id -> level), kept until the construction has it.
-- Bought levels that the construction has not built yet, nil when nothing is pending. A level above a
-- lowered maximum (settings changed when a savegame is loaded) counts as the maximum: the parameter
-- never holds more, so it would stay pending for ever.
function core.pendingTargets(record, params)
    local pending
    for id, level in pairs(record and record.targets or {}) do
        local upgrade = core.UPGRADE_BY_ID[id]
        local target = upgrade and clamp(level, upgrade.max) or 0
        if upgrade and target > core.level(params, id) then
            pending = pending or {}
            pending[id] = target
        end
    end
    return pending
end

-- The level an upgrade has once the pending rebuild is done.
function core.pendingLevel(record, params, id)
    local target = record and record.targets and tonumber(record.targets[id])
    return math.max(core.level(params, id), clamp(target, core.UPGRADE_BY_ID[id].max))
end

-- Version 2 kept a single pending upgrade per industry (target, targetUpgrade).
function core.migrateTargets(record)
    if record.target ~= nil then
        local id = record.targetUpgrade or "throughput"
        record.targets = record.targets or {}
        record.targets[id] = math.max(tonumber(record.targets[id]) or 0, tonumber(record.target) or 0)
    end
    record.target, record.targetUpgrade = nil, nil
end

-- Multiplier of an upgrade at a level (for "workers": the bonus added to the boost factor).
local EFFECTS = {
    throughput = function(level) return 1 + config.THROUGHPUT_STEP * level end,
    storage = function(level) return 1 + config.STORAGE_STEP * level end,
    efficiency = function(level) return 1 - config.EFFICIENCY_STEP * level end,
    booster = function(level) return 1 + config.BOOSTER_STEP * level end,
    emission = function(level) return math.max(0, 1 - config.EMISSION_STEP * level) end,
    workers = function(level) return config.WORKER_BOOST_STEP * level end,
}

function core.effect(id, level)
    return EFFECTS[id](clamp(level, core.UPGRADE_BY_ID[id].max))
end

function core.throughputFactor(level) return core.effect("throughput", level) end

function core.cost(nextLevel)
    return config.COST_BASE + config.COST_STEP * (nextLevel - 1)
end

-- Upkeep ------------------------------------------------------------------------------------------

-- The base game's inflation (finances_util.scaleWithInflation, without its rounding to 10,000): x1 up
-- to 1900, rising to x4 in 2000.
function core.inflation(year)
    year = tonumber(year)
    if not year then return 1 end
    return 1 + 3 * math.max(0, math.min(1, (year - 1900) / 100))
end

-- Upkeep units of an upgrade at a level: one per level, or 1 + 2 + ... + level with UPKEEP_RISING.
function core.upkeepUnits(level)
    level = math.max(0, math.floor(tonumber(level) or 0))
    if config.UPKEEP_RISING ~= 0 then return level * (level + 1) / 2 end
    return level
end

local function upkeepMoney(units, year)
    return math.floor(units * config.UPKEEP_BASE * core.inflation(year) + 0.5)
end

-- Money the levels of an industry (id -> level) cost a month in a year; 0 without upkeep.
function core.upkeep(levels, year)
    if config.UPKEEP_BASE <= 0 then return 0 end
    local units = 0
    for _index, upgrade in ipairs(core.UPGRADES) do units = units + core.upkeepUnits(levels and levels[upgrade.id]) end
    return upkeepMoney(units, year)
end

-- What the next level of an upgrade (from level to level + 1) adds to the upkeep a month.
function core.upkeepStep(level, year)
    if config.UPKEEP_BASE <= 0 then return 0 end
    return upkeepMoney(core.upkeepUnits(level + 1) - core.upkeepUnits(level), year)
end

-- The worker boost factor the base game rolls for an industry (industry_productivity_util).
function core.baseWorkerBoost(seed)
    if seed == nil then return 2 end
    math.randomseed(seed * 13 + 47)
    return 1.5 + math.random()
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = deepCopy(item) end
    return result
end

-- Efficiency works on the recipe (see lowerConsumption): every amount x the recipe scale, the rate / the
-- scale, then the inputs x consumption. A larger scale means larger lots: a cycle takes scale x the
-- base game's amounts at once and runs scale times less often.
-- - Steps of 5 or 10 %: every level is a whole 5 %, so every input comes out whole by 20 at the latest.
--   Each recipe and level gets the smallest scale at which it does (steel mill 6 + 6 at -50 %: 3 + 3,
--   scale 1, the base game's lot and rate; refinery 4 at -10 %: 18, scale 5).
-- - Steps of 1 or 2 %: always MAX_RECIPE_SCALE, rounded where a level is no whole 5 %: an input of 4 saves
--   in steps of 1.25 %, one of 1 in steps of 5 %. A fixed scale lets the preview find the base game's
--   amounts again (core.efficiencyRatio); with the smallest one a built 19 at -5 % could come from 1 at
--   20, 4 at 5 or 20 at 1, which round differently at the next level. Exact 1 % would need 100: the
--   machine factory's 700 steel a cycle would not fit its stock of 400.
core.MAX_RECIPE_SCALE = 20

-- Whether every efficiency level is a whole 5 % (steps of 5 or 10 %).
function core.wholeEfficiencySteps()
    local twentieths = config.EFFICIENCY_STEP * 20
    return math.abs(twentieths - math.floor(twentieths + 0.5)) < 1e-9
end

function core.recipeScale(amounts, consumption)
    if not core.wholeEfficiencySteps() then return core.MAX_RECIPE_SCALE end
    for scale = 1, core.MAX_RECIPE_SCALE do
        local exact = true
        for _index, amount in ipairs(amounts) do
            local value = amount * scale * consumption
            if math.abs(value - math.floor(value + 0.5)) > 1e-6 then
                exact = false
                break
            end
        end
        if exact then return scale end
    end
    return core.MAX_RECIPE_SCALE
end

-- A recipe input of the base game (amount per cycle) at consumption, on the recipe scale.
function core.efficientAmount(amount, consumption, scale)
    if amount <= 0 then return 0 end
    return math.max(1, math.floor(amount * scale * consumption + 0.5))
end

local function hasInput(rule)
    for _set, inputs in ipairs(rule.input or {}) do
        for _index, amount in ipairs(inputs) do
            if amount > 0 then return true end
        end
    end
    return false
end

-- The inputs of a rule above 0, of every input set in order.
local function inputAmounts(rule)
    local amounts = {}
    for _set, inputs in ipairs(rule.input or {}) do
        for _index, amount in ipairs(inputs) do
            if amount > 0 then amounts[#amounts + 1] = amount end
        end
    end
    return amounts
end

-- Every rule of an industry but its boosters and a delivery order's rule is a production rule, also
-- one without output (a consumer of another mod, such as a power plant).
function core.isProductionRule(rule)
    return not rule.booster and not core.isOrderRule(rule)
end

-- The rule of a delivery order: a booster without effect worth mentioning (core.ORDER_BOOST), or a plain
-- rule without output and with the order's tiny consumptionFactor (core.ORDER_FACTOR).
function core.isOrderRule(rule)
    if rule.booster == true then return (tonumber(rule.boostFactor) or 1) < 0.01 end
    return (tonumber(rule.consumptionFactor) or 1) <= 2 * core.ORDER_FACTOR and next(rule.output or {}) == nil
end

-- Whether open orders get a plain rule (config.ORDER_RULE), else a booster.
function core.plainOrderRule()
    return config.ORDER_RULE ~= "booster"
end

-- The industry's own boosters, without the rules of a delivery order.
function core.isRealBooster(rule)
    return rule.booster == true and not core.isOrderRule(rule)
end

-- Whether one of the industry's own boosters runs right now: its last cycle is not over yet, as the
-- base game's window tells it (industry_util.getIndustryBoost). rules and ruleDatas (with their
-- applyHistory) as in the engine's StockList. The engine's own flag boostFromRule is also set by a
-- delivery order's booster.
function core.realBoosterRunning(rules, ruleDatas, now)
    for index, rule in ipairs(rules or {}) do
        if core.isRealBooster(rule) then
            local history = ruleDatas and ruleDatas[index] and ruleDatas[index].applyHistory
            local last = history and history[#history]
            if last and last.time + last.interval >= now then return true end
        end
    end
    return false
end

-- An open order built with another shape of stocks and rules (see core.ORDER_FORMAT).
function core.orderOutdated(params)
    return core.hasOrderStocks(params) and tonumber(params[core.ORDER_FORMAT_PARAM]) ~= core.ORDER_FORMAT
end

-- A rule runs capacity x consumptionFactor cycles per year (the base game's production card).
-- capacity is a whole number in the engine, so rate changes go into consumptionFactor (the
-- industry's size, a decimal), which slows or speeds up inputs and outputs alike.
local function scaleRate(rule, factor)
    rule.consumptionFactor = (tonumber(rule.consumptionFactor) or 1) * factor
end

-- Efficiency: consumptionFactor cannot save input on its own (see scaleRate), so the saving goes
-- into the recipe: every amount x core.recipeScale and the rate / the scale (same yearly amounts),
-- then the inputs x consumption (core.efficientAmount). The recipe tables are replaced, not changed,
-- because the original script hands out the shared configuration.
local function lowerConsumption(rule, consumption)
    if not hasInput(rule) then return end
    local scale = core.recipeScale(inputAmounts(rule), consumption)
    if scale ~= 1 then
        scaleRate(rule, 1 / scale)
        local output = {}
        for cargo, amount in pairs(rule.output or {}) do output[cargo] = amount * scale end
        rule.output = output
    end
    local input = {}
    for set, amounts in ipairs(rule.input) do
        input[set] = {}
        for index, amount in ipairs(amounts) do input[set][index] = core.efficientAmount(amount, consumption, scale) end
    end
    rule.input = input
end

-- Input stocks only booster rules draw from, by position among the input stocks (as rule inputs
-- are numbered).
local function boosterOnlyInputs(rules)
    local booster, production = {}, {}
    for _index, rule in ipairs(rules or {}) do
        local used = rule.booster and booster or production
        for _set, inputs in ipairs(rule.input or {}) do
            for index, amount in ipairs(inputs) do
                if amount > 0 then used[index] = true end
            end
        end
    end
    for index in pairs(production) do booster[index] = nil end
    return booster
end

-- Booster demand (setting "Booster demand per level"): every booster strength level raises a booster's
-- cargo per cycle by BOOSTER_DEMAND, however strong the level makes it (+25 % a level: level 4 needs
-- twice the cargo). 1 without the setting.
function core.boosterDemand(level)
    return 1 + config.BOOSTER_DEMAND * math.max(0, math.min(core.UPGRADE_BY_ID.booster.max, math.floor(tonumber(level) or 0)))
end

-- The cargo per cycle x the demand factor, rounded, at least 1. Its rate stays, so the boost lasts as
-- long per cycle as before. The recipe tables are replaced, not changed, because the original script
-- hands out the shared configuration.
local function raiseBoosterDemand(rule, factor)
    local input = {}
    for set, amounts in ipairs(rule.input or {}) do
        input[set] = {}
        for index, amount in ipairs(amounts) do
            input[set][index] = amount > 0 and math.max(1, math.floor(amount * factor + 0.5)) or 0
        end
    end
    rule.input = input
end

-- Workers needed (setting "Workers needed per level"): every worker boost level adds WORKERS_NEEDED of
-- the industry's workplaces (its person capacity, which the original script sets from industrialCapacity).
-- The base game asks half of the workplaces to be reached by line within two years for the boost
-- (industry_productivity_util.isIndustryWorkersBoosted: arrivals >= capacity x 0.5), so it needs more
-- workers; the towns assign their residents to the new workplaces by themselves. 1 without the setting.
function core.workplaceFactor(level)
    return 1 + config.WORKERS_NEEDED * clamp(level, core.UPGRADE_BY_ID.workers.max)
end

-- The base game's worker script (industries/industry_workers.script.tl) keeps only the last 20 arrivals
-- by line of an industry (KeepHistoryCount), and the boost needs half of the workplaces to arrive
-- (RequiredWorkersFractionForBoost), so beyond 40 workplaces a boost could never come (reported on
-- mod.io 2026-10-16). "Workers needed per level" builds at most MAX_WORKPLACES; an industry with more
-- workplaces of its own keeps them. OWN_WORKER_SCRIPT (not yet released, see workers.script.lua): the
-- base game's script runs our copy instead, which keeps as many arrivals as the boost needs, and the
-- workplaces have no limit.
core.ARRIVALS_KEPT = 20
core.MAX_WORKPLACES = 40
core.OWN_WORKER_SCRIPT = false

-- Whether the base game's worker script runs our copy in this game (mod.script.lua).
function core.ownWorkerScript()
    return core.OWN_WORKER_SCRIPT and config.WORKERS_NEEDED ~= 0
end

-- The most workplaces "Workers needed per level" builds at an industry whose own are base.
function core.workplaceLimit(base)
    if core.ownWorkerScript() then return math.huge end
    return math.max(tonumber(base) or 0, core.MAX_WORKPLACES)
end

-- The workplaces an industry whose own are base gets at a worker boost level.
function core.builtWorkplaces(base, level)
    return math.min(math.max(1, math.floor(base * core.workplaceFactor(level) + 0.5)), core.workplaceLimit(base))
end

-- The workplaces a capacity built at one worker boost level has at another, rounded like the rebuild:
-- the base game's capacity is found again from the built one. One that does not fit (built under other
-- settings) gets the plain share. A capacity at the limit stays there.
function core.workplaces(capacity, level, toLevel)
    local limit = core.workplaceLimit(0)
    if capacity >= limit then return capacity end
    local from, to = core.workplaceFactor(level), core.workplaceFactor(toLevel)
    local original = math.floor(capacity / from + 0.5)
    if original < 1 or math.max(1, math.floor(original * from + 0.5)) ~= capacity then
        return math.min(math.floor(capacity * to / from + 0.5), limit)
    end
    return math.min(math.max(1, math.floor(original * to + 0.5)), limit)
end

-- Whether an industry's workplaces (built) differ from what its own (base) give at its worker boost
-- level now: "Workers needed per level" can change when a savegame is loaded, and the limit came with
-- revision 8, but the workplaces only change with a rebuild. Nothing is outdated while either is
-- unknown, nor without worker boost levels (those keep the base game's workplaces).
function core.workplacesOutdated(level, built, base)
    if level <= 0 or not built or not base then return false end
    return built ~= core.builtWorkplaces(base, level)
end

-- The arrivals by line our copy of the base game's worker script keeps per industry: the base game's
-- 20, or as many as the boost needs if that is more (industry_productivity_util.isIndustryWorkersBoosted:
-- arrivals >= workplaces x fraction).
function core.arrivalsKept(capacity, fraction)
    return math.max(core.ARRIVALS_KEPT, math.ceil((tonumber(capacity) or 0) * (tonumber(fraction) or 0.5)))
end

-- Applies every bought upgrade to the result of the original construction script.
-- Throughput: scaling the rate of the production rules (see scaleRate) raises input demand and
-- output together and keeps every recipe ratio exact; the stocks grow along so they keep buffering
-- the same time. Booster rules keep their rate: the boost multiplies the whole production, so the
-- same booster supply still covers the year, and their stocks only grow with the storage upgrade.
-- Efficiency changes the recipe (see lowerConsumption). Emissions are copied before scaling
-- because the original script hands out the shared configuration table.
function core.applyUpgrades(result, params)
    local throughput = core.effect("throughput", core.level(params, "throughput"))
    local storage = core.effect("storage", core.level(params, "storage"))
    local consumption = core.effect("efficiency", core.level(params, "efficiency"))
    local booster = core.effect("booster", core.level(params, "booster"))
    local boosterDemand = core.boosterDemand(core.level(params, "booster"))
    local workers = core.level(params, "workers")
    local emission = core.effect("emission", core.level(params, "emission"))
    for _index, sub in ipairs(result.subconstructions or {}) do
        if sub.industry then
            local boosterStocks = boosterOnlyInputs(sub.rules)
            local persons = sub.personCapacity
            if workers > 0 and persons and persons.type == "INDUSTRIAL" and tonumber(persons.capacity) then
                local copy = {}
                for key, value in pairs(persons) do copy[key] = value end
                copy.capacity = core.builtWorkplaces(tonumber(persons.capacity), workers)
                sub.personCapacity = copy
                -- recorded for the check on loading (core.workplacesOutdated)
                result.metadata = result.metadata or {}
                result.metadata[core.WORKPLACES_META] = copy.capacity
                result.metadata[core.WORKPLACES_BASE_META] = tonumber(persons.capacity)
            end
            for _rule, rule in ipairs(sub.rules or {}) do
                if rule.booster then
                    if rule.boostFactor and booster ~= 1 then rule.boostFactor = rule.boostFactor * booster end
                    if boosterDemand ~= 1 then raiseBoosterDemand(rule, boosterDemand) end
                else
                    if throughput ~= 1 then scaleRate(rule, throughput) end
                    if consumption ~= 1 then lowerConsumption(rule, consumption) end
                end
            end
            local inputIndex = 0
            for _stock, stock in ipairs(sub.stocks or {}) do
                local factor = throughput * storage
                if stock.type == "INPUT_STOCK" then
                    inputIndex = inputIndex + 1
                    if boosterStocks[inputIndex] then factor = storage end
                end
                if (stock.type == "INPUT_STOCK" or stock.type == "OUTPUT_STOCK") and stock.capacity then
                    stock.capacity = math.floor(stock.capacity * factor + 0.5)
                end
            end
            if emission ~= 1 and sub.metadata and sub.metadata.emissions then
                local emissions = deepCopy(sub.metadata.emissions)
                for _state, values in ipairs(emissions) do
                    if values.noise then values.noise = values.noise * emission end
                    if values.pollution then values.pollution = values.pollution * emission end
                end
                sub.metadata.emissions = emissions
            end
        end
    end
    if workers > 0 then
        result.metadata = result.metadata or {}
        result.metadata.workersBoostFactor = core.baseWorkerBoost(params.seed) + core.effect("workers", workers)
    end
    -- after the upgrades, so the order's stocks and rules are never scaled
    return core.addOrder(result, params)
end

-- Delivery orders ---------------------------------------------------------------------------------

-- In delivery mode (setting "Upgrade costs") every upgrade costs a delivery; in EXP mode, or without
-- tiers, every upgrade costs points. The setting comes with each construction (core.configure), so ask
-- only after configuring for the construction in question.
function core.deliveryMode()
    return config.DELIVERY_MODE ~= 0 and #core.tiers() > 0
end

-- The material of the game's economy: {cargo, amount} (ECONOMY_MATERIAL, else MATERIAL).
function core.material()
    return config.ECONOMY_MATERIAL[config.ECONOMY] or config.MATERIAL
end

-- The ladder of cargo (RESOURCE_TIERS) with the material of the game's economy (core.material) in its
-- place: {{level, untilLevel?, cargo, amount}}.
function core.tiers()
    local material = core.material()
    local result = {}
    for _index, tier in ipairs(config.RESOURCE_TIERS) do
        if tier.material then
            result[#result + 1] = {level = tier.level, untilLevel = tier.untilLevel, cargo = material.cargo, amount = material.amount}
        else
            result[#result + 1] = tier
        end
    end
    return result
end

-- The step of the ladder (1..LADDER_LEVELS) a level of an upgrade (id) stands on: the levels are
-- spread over the ladder by their share of the upgrade's maximum, so its last level is the top step
-- (throughput 1..10 is the ladder itself, the five levels of the others steps 2, 4, 6, 8, 10). Without
-- an upgrade, the level itself.
function core.ladderLevel(level, id)
    local upgrade = id and core.UPGRADE_BY_ID[id]
    if not upgrade or (tonumber(upgrade.max) or 0) <= 0 then return level end
    return math.ceil(level * config.LADDER_LEVELS / upgrade.max - 1e-9)
end

-- "::/cargos/steel/steel.cargo" -> "steel"
function core.cargoShortName(cargo)
    return tostring(cargo):match("([^/]+)%.cargo$") or tostring(cargo)
end

-- The levels an open order builds up to, from the construction parameters: id -> level, nil when no
-- order is open. Not cut to the maximum: stocks built for more levels than a lowered maximum allows
-- must not match the order cut to it (the game script's fitOrders).
function core.orderTargets(params)
    local targets
    for _index, upgrade in ipairs(core.UPGRADES) do
        local value = params and tonumber(params[upgrade.orderParam])
        if value and value > 1 then
            targets = targets or {}
            targets[upgrade.id] = math.floor(value) - 1
        end
    end
    return targets
end

-- targets = nil closes the order.
function core.setOrderTargets(params, targets)
    for _index, upgrade in ipairs(core.UPGRADES) do
        local target = targets and tonumber(targets[upgrade.id])
        params[upgrade.orderParam] = target and clamp(target, upgrade.max) + 1 or 1
    end
end

-- Whether two sets of order targets (id -> level, nil = no order) name the same levels.
function core.sameTargets(a, b)
    for _index, upgrade in ipairs(core.UPGRADES) do
        local left = a and tonumber(a[upgrade.id]) or 0
        local right = b and tonumber(b[upgrade.id]) or 0
        if left ~= right then return false end
    end
    return true
end

-- Whether the construction is built with the stocks of an order.
function core.hasOrderStocks(params)
    return core.orderTargets(params) ~= nil
end

-- The pool's cargo in tier order, each once.
function core.poolCargo()
    local result, seen = {}, {}
    for _index, tier in ipairs(core.tiers()) do
        if not seen[tier.cargo] then
            seen[tier.cargo] = true
            result[#result + 1] = tier.cargo
        end
    end
    return result
end

-- The cargo an industry delivers for each cargo of the pool: pool cargo -> cargo, false when nothing
-- is left, and the factor of its amounts (pool cargo -> factor). A cargo the industry already uses or
-- produces (isUsed(name)) is replaced by the first free one of its RESOURCE_FALLBACK list: the base
-- game's consumption event names the stock list, not the stock, so an order must never share a cargo
-- with production, nor two of its cargos one stock. Chosen over the whole pool, so a cargo keeps its
-- replacement whichever levels an order holds.
function core.cargoMapping(isUsed)
    local pool, kept, taken = core.poolCargo(), {}, {}
    for _index, cargo in ipairs(pool) do
        if not isUsed(cargo) then kept[cargo], taken[cargo] = true, true end
    end
    local mapping, factors = {}, {}
    for _index, cargo in ipairs(pool) do
        if kept[cargo] then
            mapping[cargo], factors[cargo] = cargo, 1
        else
            mapping[cargo] = false
            for _fallback, fallback in ipairs(config.RESOURCE_FALLBACK[cargo] or {}) do
                if not mapping[cargo] and not taken[fallback.cargo] and not isUsed(fallback.cargo) then
                    mapping[cargo], factors[cargo] = fallback.cargo, tonumber(fallback.factor) or 1
                    taken[fallback.cargo] = true
                end
            end
        end
    end
    return mapping, factors
end

-- Amounts are rounded to this step, so the order's lots stay small (core.orderLots divides the amounts
-- by their greatest common divisor): 18 + 12 at 10 % storage would make 3 + 2 in 6 cycles, 20 + 10
-- make 2 + 1 in 10.
core.AMOUNT_STEP = 5

-- What one level of an upgrade (id) costs: every tier that holds its step of the ladder
-- (core.ladderLevel), x RESOURCE_SHARE x the upgrade's weight (RESOURCE_WEIGHTS, 1 when it has none)
-- x the factor of the cargo's replacement (factors from core.cargoMapping, none: 1).
-- {{cargo = pool cargo, amount}}
function core.levelCost(level, id, factors)
    local weight = tonumber(id and config.RESOURCE_WEIGHTS[id]) or 1
    local step = core.ladderLevel(level, id)
    local result = {}
    for _index, tier in ipairs(core.tiers()) do
        if step >= tier.level and (tier.untilLevel == nil or step <= tier.untilLevel) then
            local factor = tonumber(factors and factors[tier.cargo]) or 1
            local steps = math.floor(tier.amount * config.RESOURCE_SHARE * weight * factor / core.AMOUNT_STEP + 0.5)
            result[#result + 1] = {cargo = tier.cargo, amount = math.max(1, steps) * core.AMOUNT_STEP}
        end
    end
    return result
end

-- What a delivery order for the levels from(id) + 1 up to targets[id] needs at an industry: the cost of
-- every level summed per cargo, in pool order ({{cargo = resource name, amount}}), and the number of
-- levels. The construction script and the game script both call this with the industry's own stocks
-- (without the order's), so they agree on the cargo.
function core.orderRequirements(targets, from, isUsed)
    local mapping, factors = core.cargoMapping(isUsed)
    local sums, count = {}, 0
    for _index, upgrade in ipairs(core.UPGRADES) do
        local target = targets and tonumber(targets[upgrade.id])
        if target then
            for level = (tonumber(from(upgrade.id)) or 0) + 1, math.min(target, upgrade.max) do
                count = count + 1
                for _cost, cost in ipairs(core.levelCost(level, upgrade.id, factors)) do sums[cost.cargo] = (sums[cost.cargo] or 0) + cost.amount end
            end
        end
    end
    local needs = {}
    for _index, cargo in ipairs(core.poolCargo()) do
        if sums[cargo] and mapping[cargo] then needs[#needs + 1] = {cargo = mapping[cargo], amount = sums[cargo]} end
    end
    return needs, count
end

-- The level planning starts from for an upgrade: built, bought and waiting for the rebuild, or being
-- delivered in the open order.
function core.planBase(record, params, id)
    local order = record and record.order
    local ordered = order and order.targets and tonumber(order.targets[id])
    return math.max(core.pendingLevel(record, params, id), ordered or 0)
end

-- The level an upgrade has once the plan is built (record.plan: id -> level).
function core.plannedLevel(record, params, id)
    local base = core.planBase(record, params, id)
    local planned = record and record.plan and tonumber(record.plan[id])
    return math.max(base, math.min(core.UPGRADE_BY_ID[id].max, planned or base))
end

-- The order the plan opens: from and targets (id -> level) of every upgrade planned above its base;
-- nil, nil when nothing is planned. The game script's start and the window's plan card both use it.
function core.planTargets(record, params)
    local from, targets = {}, nil
    for _index, upgrade in ipairs(core.UPGRADES) do
        local base = core.planBase(record, params, upgrade.id)
        local planned = core.plannedLevel(record, params, upgrade.id)
        if planned > base then
            targets = targets or {}
            from[upgrade.id], targets[upgrade.id] = base, planned
        end
    end
    if not targets then return nil, nil end
    return from, targets
end

-- The plan after an order was cancelled. record.plan holds levels, and planning started above the
-- ordered ones (core.planBase); they move down by the cancelled order's levels, so the plan keeps its
-- number of levels per upgrade. nil when nothing is left.
function core.shiftPlan(plan, order)
    if not plan then return nil end
    local result = {}
    for id, level in pairs(plan) do
        local target = order and order.targets and tonumber(order.targets[id])
        local from = tonumber(order and order.from and order.from[id]) or 0
        local planned = tonumber(level) or 0
        if target then planned = planned - math.max(0, target - from) end
        if planned > (target and from or 0) then result[id] = planned end
    end
    return next(result) and result or nil
end

-- The number of levels an order builds.
function core.orderLevelCount(order)
    local count = 0
    for id, target in pairs(order and order.targets or {}) do
        count = count + math.max(0, (tonumber(target) or 0) - (tonumber(order.from and order.from[id]) or 0))
    end
    return count
end

-- "throughput 0->2, storage 1->2" for the log.
function core.orderText(order)
    local parts = {}
    for _index, upgrade in ipairs(core.UPGRADES) do
        local target = order and order.targets and order.targets[upgrade.id]
        if target then
            parts[#parts + 1] = string.format("%s %d->%d", upgrade.id, math.floor(tonumber(order.from and order.from[upgrade.id]) or 0),
                math.floor(tonumber(target) or 0))
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or "nothing"
end

-- The cargo of an industry's own stocks (cargo -> true), without the stocks of a delivery order (those
-- the order's rules consume). Works on the construction result (cargo names) and on the engine's
-- stock list (cargo type ids) alike. A closed order keeps its stocks until the next rebuild; a new
-- order must still choose its cargo from the industry's own stocks.
function core.ownCargo(stocks, rules)
    local orderInput = {} -- rule inputs are numbered by input stock
    for _index, rule in ipairs(rules or {}) do
        if core.isOrderRule(rule) then
            for _set, inputs in ipairs(rule.input or {}) do
                for index, amount in ipairs(inputs) do
                    if amount > 0 then orderInput[index] = true end
                end
            end
        end
    end
    local cargo, inputIndex = {}, 0
    for _position, stock in ipairs(stocks or {}) do
        local order = false
        if core.isInputStock(stock) then
            inputIndex = inputIndex + 1
            order = orderInput[inputIndex] == true
        end
        if not order and stock.cargoType then cargo[stock.cargoType] = true end
    end
    return cargo
end

-- The cargo of a delivery order's stocks (cargo -> true; empty without an order): the input stocks the
-- order's rules consume. Order cargo is never one of the industry's own (core.cargoMapping).
function core.orderStockCargo(stocks, rules)
    local orderInput = {} -- rule inputs are numbered by input stock
    for _index, rule in ipairs(rules or {}) do
        if core.isOrderRule(rule) then
            for _set, inputs in ipairs(rule.input or {}) do
                for index, amount in ipairs(inputs) do
                    if amount > 0 then orderInput[index] = true end
                end
            end
        end
    end
    local cargo, inputIndex = {}, 0
    for _position, stock in ipairs(stocks or {}) do
        if core.isInputStock(stock) then
            inputIndex = inputIndex + 1
            if orderInput[inputIndex] and stock.cargoType then cargo[stock.cargoType] = true end
        end
    end
    return cargo
end

-- Input stock of a construction result ("INPUT_STOCK") or of the engine's stock list (enum).
function core.isInputStock(stock)
    if stock.type == "INPUT_STOCK" then return true end
    local ok, inputType = pcall(function() return api.type["enum"].StockListType.InputStock end)
    return ok and inputType ~= nil and stock.type == inputType
end

-- Every input set of a rule as a new table with exactly `count` amounts, missing ones 0. New tables:
-- the original script hands out the shared configuration.
local function padInputs(input, count)
    local result = {}
    for set, amounts in ipairs(input or {{}}) do
        result[set] = {}
        for index = 1, count do result[set][index] = amounts[index] or 0 end
    end
    if #result == 0 then result[1] = padInputs(nil, count)[1] end
    return result
end

local function gcd(a, b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

-- How many cycles a plain order may take at an industry: ORDER_TURN_SHARE of the cycles its production
-- runs in the order's minimum duration (count levels), at least 1, at most ORDER_STEPS. rules: the
-- industry's rules without the order's malus (the construction result before core.addOrder slows them,
-- or the engine's stock list before an order is open); the fastest production rule counts.
function core.orderSteps(rules, count)
    local perYear = 0
    for _index, rule in ipairs(rules or {}) do
        if core.isProductionRule(rule) then
            perYear = math.max(perYear, (tonumber(rule.capacity) or 0) * (tonumber(rule.consumptionFactor) or 1))
        end
    end
    local turns = perYear * (1 - config.ORDER_MALUS) * core.orderYears(count) * core.ORDER_TURN_SHARE
    return math.max(1, math.min(core.ORDER_STEPS, math.floor(turns + 1e-9)))
end

-- Lot size per cargo and number of cycles of an order, like the landmark construction sites
-- (lighthouse: 1200 stone and 200 fuel as 6 + 1 per cycle): the amounts divided by their greatest
-- common divisor, 300 + 200 -> 3 + 2 in 100 cycles. A plain order rule takes the largest divisor of it
-- up to `steps` (core.orderSteps; nil: ORDER_STEPS): 300 + 200 -> 30 + 20 in 10 cycles.
-- needs = {{amount}}.
function core.orderLots(needs, steps)
    local divisor = 0
    for _index, need in ipairs(needs or {}) do divisor = gcd(math.max(0, math.floor(tonumber(need.amount) or 0)), divisor) end
    local lots = {}
    if divisor <= 0 then return lots, 0 end
    local cycles = divisor
    if core.plainOrderRule() then
        local most = math.max(1, math.min(core.ORDER_STEPS, math.floor(tonumber(steps) or core.ORDER_STEPS)))
        for steps = math.min(divisor, most), 1, -1 do
            if divisor % steps == 0 then
                cycles = steps
                break
            end
        end
    end
    for index, need in ipairs(needs) do lots[index] = math.floor(math.floor(tonumber(need.amount) or 0) / cycles) end
    return lots, cycles
end

-- The shortest time in years an order for `count` levels takes: RESOURCE_YEARS for the first level,
-- BUNDLE_SHARE of it for every further one.
function core.orderYears(count)
    return config.RESOURCE_YEARS * (1 + config.BUNDLE_SHARE * math.max(0, (tonumber(count) or 1) - 1))
end

-- Cycles per year of the rule of an order for `count` levels. A plain rule runs short cycles
-- (ORDER_FAST_RATE); its minimum duration is the game script's (core.orderTimeOver). A booster runs all
-- its cycles in core.orderYears, its rate is its capacity, a whole number, at least 1.
function core.orderRate(cycles, count)
    if cycles <= 0 then return 1 end
    if core.plainOrderRule() then return core.ORDER_FAST_RATE end
    return math.max(1, math.floor(cycles / core.orderYears(count) + 0.5))
end

-- Whole months of a time in years, rounded up (a fraction a hair above a whole month is not one more).
local function monthsOf(years)
    return math.ceil(years * 12 - 1e-6)
end

-- Months an order needs at least: needs = {{amount}}.
function core.orderMonths(needs, count)
    local _lots, cycles = core.orderLots(needs)
    if cycles <= 0 then return 0 end
    if core.plainOrderRule() then return monthsOf(core.orderYears(count)) end
    return monthsOf(cycles / core.orderRate(cycles, count))
end

-- The minimum duration of an open order in years: core.orderYears with the RESOURCE_YEARS it was
-- opened with (order.years; the game script's fitOrders keeps it in line with the settings).
function core.orderDuration(order)
    local years = tonumber(order and order.years) or config.RESOURCE_YEARS
    return years * (1 + config.BUNDLE_SHARE * math.max(0, core.orderLevelCount(order) - 1))
end

-- Whether an order's minimum duration has passed: order.at (game time it was opened) +
-- core.orderDuration, year = game time of a year. A booster's rule runs the duration itself; an order
-- without a start time (opened before there was one) only waits for its cargo.
-- Whether an order's last cycle has run. The engine takes a lot when a cycle of the order's rule
-- starts, and the consumption event the order is counted by comes with it, so the last lot is counted
-- with a whole cycle still to run (seen 2026-10-11: the order completed as soon as its last lot was
-- set by debug). The order waits one cycle of its rule (a year / core.orderRate) after order.lastLot,
-- the game time it was first found complete (the game script sets it); a started cycle runs to its
-- end even when the industry stops producing. Without game time it does not wait.
function core.orderLastCycleOver(order, now, year)
    local at = tonumber(order and order.lastLot)
    if not at then return false end
    if not now or not year or year <= 0 then return true end
    local _lots, cycles = core.orderLots(order.cargo, order.steps)
    return now - at >= year / core.orderRate(cycles, core.orderLevelCount(order))
end

function core.orderTimeOver(order, now, year)
    if not core.plainOrderRule() then return true end
    local at = tonumber(order and order.at)
    if not at or not now or not year or year <= 0 then return true end
    return now - at >= core.orderDuration(order) * year
end

-- How far an order is: {lots, cycles, rate, left (cycles still to run), fraction (0..1), months (left
-- at full supply)}. The rule consumes every cargo together, so the cargo with the most cycles still
-- missing decides. A plain order's months are the rest of its minimum duration (now and year: game
-- time and the game time of a year; without them the whole duration).
function core.orderProgress(order, now, year)
    local cargo = order and order.cargo or {}
    local count = core.orderLevelCount(order)
    local lots, cycles = core.orderLots(cargo, order and order.steps)
    local rate = core.orderRate(cycles, count)
    local left = 0
    for index, need in ipairs(cargo) do
        local missing = (tonumber(need.amount) or 0) - (tonumber(need.delivered) or 0)
        if missing > 0 and (lots[index] or 0) > 0 then left = math.max(left, math.ceil(missing / lots[index])) end
    end
    left = math.min(left, cycles)
    local months = monthsOf(left / rate)
    if left == 0 and cycles > 0 then
        -- all cargo counted: the last cycle still runs (core.orderLastCycleOver)
        local at = tonumber(order and order.lastLot)
        local passed = (at and now and year and year > 0) and math.max(0, (now - at) / year) or 0
        months = monthsOf(math.max(0, 1 / rate - passed))
    end
    if core.plainOrderRule() then
        local at = tonumber(order and order.at)
        local passed = (at and now and year and year > 0) and math.max(0, (now - at) / year) or 0
        months = monthsOf(math.max(0, core.orderDuration(order) - passed))
    end
    return {
        lots = lots, cycles = cycles, rate = rate, left = left,
        fraction = cycles > 0 and 1 - left / cycles or 0,
        months = months,
    }
end

-- Industries with fields (farms, forests) built with fewer fields than they can have: the base game's
-- industryutil scales the inputs of every rule but boosters once the fields are placed
-- (terminateConstructionHook, adjustStocklistRule), after the construction script. A plain order rule
-- gets its lots back right after that, so its cycles still take the amounts it was built for.
function core.keepOrderLots(result, rule)
    local hook = result.terminateConstructionHook
    if type(hook) ~= "function" then return end
    local lots = padInputs(rule.input, #(rule.input[1] or {}))
    result.terminateConstructionHook = function(...)
        local returned = hook(...)
        rule.input = padInputs(lots, #(lots[1] or {}))
        return returned
    end
end

-- An open delivery order: one input stock per cargo, right behind the industry's own input stocks
-- and holding the whole amount, and one booster rule without effect (core.ORDER_BOOST) that consumes
-- all of them together in lots (core.orderLots), like a landmark construction site. A cycle only runs
-- when every cargo has a lot in stock, at core.orderRate cycles per year.
-- - Rule input j is the j-th stock of the whole list (engine and base game GUI alike: the order's
--   rules consumed a coal mine's own coal while their stocks came after the output stocks, and the
--   window drew the mine as its own coal supplier, a zero-length flow that crashes in
--   CargoFlowRenderable.cpp), and the engine asserts that every input set has one amount per input
--   stock (create_proposal_data.cpp: "rule.input[orId].size() == numInputStocks"). Both only fit
--   together with the input stocks first, as every base game industry lists them. The output stocks
--   move back; the base game's own "Input" switch changes the stock list in a rebuild as well.
-- - All rules get zeros for the new stocks.
-- - The rule (config.ORDER_RULE): a plain rule without output like the landmark construction sites
--   (being tried, 2026-10-11) runs whenever its cargo is there, its rate a fraction (core.ORDER_RATE_SCALE).
--   Still to be seen in-game: the base game's window may show it as a second production bar, whose
--   figures it looks up by position across all production rules (industry_util.getIndustryProductionData),
--   and the industry's boost may speed it up. industryutil scales a plain rule of an industry with
--   missing fields, so core.keepOrderLots restores its lots. A booster (the earlier shape) only starts
--   a cycle while the industry produces; patch.script hides its row in the booster card, and
--   industryutil leaves boosters alone. ui.orderBar draws the landmark's bar either way.
-- - The industry's production runs at 1 - ORDER_MALUS while the order is open (its production rules'
--   rate, see scaleRate). It comes and goes with the order's stocks, so it costs no rebuild of its own.
function core.addOrder(result, params)
    local targets = core.orderTargets(params)
    if not targets then return result end
    for _index, sub in ipairs(result.subconstructions or {}) do
        if sub.industry then
            sub.stocks = sub.stocks or {}
            sub.rules = sub.rules or {}
            local used = core.ownCargo(sub.stocks, sub.rules)
            local needs, count = core.orderRequirements(targets, function(id) return core.level(params, id) end,
                function(cargo) return used[cargo] end)
            if #needs == 0 then return result end
            local ownInputs = 0
            for _stock, stock in ipairs(sub.stocks) do
                if core.isInputStock(stock) then ownInputs = ownInputs + 1 end
            end
            local inputs = ownInputs + #needs
            -- before the malus slows the production rules, as the game script counts them at the start
            local steps = core.orderSteps(sub.rules, count)
            for _rule, rule in ipairs(sub.rules) do
                rule.input = padInputs(rule.input, inputs)
                if core.isProductionRule(rule) and config.ORDER_MALUS ~= 0 then scaleRate(rule, 1 - config.ORDER_MALUS) end
            end
            local lots, cycles = core.orderLots(needs, steps)
            local input = padInputs(nil, inputs)
            for index, need in ipairs(needs) do
                -- right behind the own input stocks (every base game industry lists its inputs first)
                table.insert(sub.stocks, ownInputs + index,
                    {type = "INPUT_STOCK", cargoType = need.cargo, capacity = need.amount, decayRateFactor = 0})
                input[1][ownInputs + index] = lots[index]
            end
            local rate = core.orderRate(cycles, count)
            local rule
            if core.plainOrderRule() then
                rule = {input = input, output = {}, capacity = math.max(1, math.floor(rate * core.ORDER_RATE_SCALE + 0.5)),
                    consumptionFactor = core.ORDER_FACTOR}
                core.keepOrderLots(result, rule)
            else
                rule = {input = input, output = {}, capacity = rate, booster = true, boostFactor = core.ORDER_BOOST}
            end
            sub.rules[#sub.rules + 1] = rule
            return result
        end
    end
    return result
end

-- All cargo of the order delivered.
function core.orderComplete(order)
    for _index, need in ipairs(order and order.cargo or {}) do
        if (tonumber(need.delivered) or 0) < (tonumber(need.amount) or 0) then return false end
    end
    return order ~= nil
end

-- Yearly amounts now and after a change, one row {inputs, outputs} per production rule (recipe) like
-- the base game's production card (industry_util.getIndustryProductionData): a rule runs capacity x
-- consumptionFactor cycles per year, sped up by boost (the caller includes the difficulty's industry
-- productivity), so per year = cycles x amount for inputs and outputs alike. Booster rules are left
-- out, no upgrade with a preview changes them. rules/stocks as in the StockList component; inputs
-- map onto the input stocks in order. ratios = {output, input}: change of each kind; input may also
-- be a function of the rule and the input's index (efficiency changes each input on its own).
function core.preview(rules, stocks, boost, isInputStock, cargoName, ratios)
    local inputStocks = {}
    for _index, stock in ipairs(stocks or {}) do
        if isInputStock(stock.type) then inputStocks[#inputStocks + 1] = stock end
    end
    local function item(cargo, perYear, ratio)
        return {cargo = cargo, name = cargoName(cargo), now = math.floor(perYear + 0.5), next = math.floor(perYear * ratio + 0.5)}
    end
    local rows = {}
    for _index, rule in ipairs(rules or {}) do
        if core.isProductionRule(rule) then
            local cycles = (tonumber(rule.capacity) or 0) * (tonumber(rule.consumptionFactor) or 1) * (boost or 1)
            local row = {inputs = {}, outputs = {}}
            for index, amount in ipairs(rule.input and rule.input[1] or {}) do
                local stock = inputStocks[index]
                if stock and amount > 0 then
                    local ratio = type(ratios.input) == "function" and ratios.input(rule, index) or ratios.input
                    row.inputs[#row.inputs + 1] = item(stock.cargoType, cycles * amount, ratio)
                end
            end
            local outputs = {}
            for cargo, amount in pairs(rule.output or {}) do
                if amount > 0 then outputs[#outputs + 1] = {cargo = cargo, amount = amount} end
            end
            table.sort(outputs, function(a, b) return a.cargo < b.cargo end) -- like the base game's sorted output cargos
            for _output, output in ipairs(outputs) do
                row.outputs[#row.outputs + 1] = item(output.cargo, cycles * output.amount, ratios.output)
            end
            if #row.inputs + #row.outputs > 0 then rows[#rows + 1] = row end
        end
    end
    return rows
end

-- The rules are those of the built level; toLevel (default level + 1) lies further ahead while
-- bought levels still wait for their rebuild.

-- Preview of a throughput level: inputs and outputs of every recipe grow by the same ratio.
function core.throughputPreview(rules, stocks, boost, level, isInputStock, cargoName, toLevel)
    local ratio = core.throughputFactor(toLevel or level + 1) / core.throughputFactor(level)
    return core.preview(rules, stocks, boost, isInputStock, cargoName, {output = ratio, input = ratio})
end

-- The real change of input index (of the first input set) of a rule built at level when it goes to
-- toLevel. With whole 5 % steps every level is exact: the input changes by exactly the nominal share.
-- With 1 or 2 % steps the recipe is always scaled by MAX_RECIPE_SCALE and rounded: the base game's amount
-- is found again by undoing the scale (the rounding moves it by at most 0.1) and both levels rounded
-- from it. An amount that does not fit (built under other settings) gets the nominal change.
function core.efficiencyRatio(rule, index, level, toLevel)
    local nominal = core.effect("efficiency", toLevel) / core.effect("efficiency", level)
    local amount = rule.input and rule.input[1] and rule.input[1][index] or 0
    if core.wholeEfficiencySteps() or amount <= 0 then return nominal end
    local scale = core.MAX_RECIPE_SCALE
    local function perCycle(original, at) -- per cycle of the base game's recipe
        if at <= 0 then return original end
        return core.efficientAmount(original, core.effect("efficiency", at), scale) / scale
    end
    local original = amount
    if level > 0 then
        local consumption = core.effect("efficiency", level)
        original = math.floor(amount / (scale * consumption) + 0.5)
        if original < 1 or core.efficientAmount(original, consumption, scale) ~= amount then return nominal end
    end
    return perCycle(original, toLevel) / perCycle(original, level)
end

-- Preview of an efficiency level: only the inputs shrink, each by its real change, so each recipe
-- shows its inputs.
function core.efficiencyPreview(rules, stocks, boost, level, isInputStock, cargoName, toLevel)
    toLevel = toLevel or level + 1
    local function ratio(rule, index) return core.efficiencyRatio(rule, index, level, toLevel) end
    local rows = {}
    for _index, row in ipairs(core.preview(rules, stocks, boost, isInputStock, cargoName, {output = 1, input = ratio})) do
        if #row.inputs > 0 then rows[#rows + 1] = {inputs = row.inputs, outputs = {}} end
    end
    return rows
end

-- The cargo per cycle a booster input built at one demand level has at another, rounded like
-- raiseBoosterDemand: the base game's amount is found again from the built one (13 at x1.1 -> 12), so the
-- preview shows what the rebuild will make (12 x 1.2 = 14.4 -> 14, not 13 x 1.2 / 1.1). An amount that
-- does not fit (built under other settings) gets the plain share.
function core.boosterAmount(amount, level, toLevel)
    local from, to = core.boosterDemand(level), core.boosterDemand(toLevel)
    local original = math.floor(amount / from + 0.5)
    if original < 1 or math.max(1, math.floor(original * from + 0.5)) ~= amount then return amount * to / from end
    return math.max(1, math.floor(original * to + 0.5))
end

-- Preview of a booster strength level while the booster demand rises with it: the yearly cargo of each
-- of the industry's own boosters (capacity x consumptionFactor cycles x amount, as the base game's
-- booster card counts it; a booster's rate is not boosted) at the next level's rounded amount
-- (core.boosterAmount), one row per booster.
function core.boosterPreview(rules, stocks, level, isInputStock, cargoName, toLevel)
    toLevel = toLevel or level + 1
    local inputStocks = {}
    for _index, stock in ipairs(stocks or {}) do
        if isInputStock(stock.type) then inputStocks[#inputStocks + 1] = stock end
    end
    local rows = {}
    for _index, rule in ipairs(rules or {}) do
        if core.isRealBooster(rule) then
            local cycles = (tonumber(rule.capacity) or 0) * (tonumber(rule.consumptionFactor) or 1)
            local inputs = {}
            for index, amount in ipairs(rule.input and rule.input[1] or {}) do
                local stock = inputStocks[index]
                if stock and amount > 0 then
                    inputs[#inputs + 1] = {cargo = stock.cargoType, name = cargoName(stock.cargoType),
                        now = math.floor(cycles * amount + 0.5), next = math.floor(cycles * core.boosterAmount(amount, level, toLevel) + 0.5)}
                end
            end
            if #inputs > 0 then rows[#rows + 1] = {inputs = inputs, outputs = {}} end
        end
    end
    return rows
end

-- The cargo the production rules of a stock list make (cargo -> true), without boosters and the rules
-- of a delivery order.
function core.outputCargo(rules)
    local result = {}
    for _index, rule in ipairs(rules or {}) do
        if core.isProductionRule(rule) then
            for cargo, amount in pairs(rule.output or {}) do
                if amount > 0 then result[cargo] = true end
            end
        end
    end
    return result
end

-- EXP for one game month: +1 for every condition met. A condition that does not apply is nil in the
-- details, so the UI leaves it out: production for primary industries (productionRating nil: no
-- inputs, always at full production), the booster for industries without boosters (boosterActive
-- nil), and every condition switched off in the settings.
-- Shipping (setting "Shipping EXP counts", SHIPPED_MODE): 0 = all products together (shipped share of
-- everything produced, `shipped`), 1 = the best product (at least one product reaches the threshold,
-- `shippedBest`), 2 = both, +1 EXP each. An industry with one product meets both or neither. bestShare
-- (nil: the total share) and bestCargo come from the product shipped best.
-- With EXP_ALL_CONDITIONS the month gives 1 EXP only if every condition that applies is met.
function core.monthlyExp(productionRating, shippedPerYear, producedPerYear, workersBoosted, boosterActive, bestShare, bestCargo)
    local production = nil
    if productionRating ~= nil and config.PRODUCTION_THRESHOLD > 0 then
        production = (tonumber(productionRating) or 0) >= config.PRODUCTION_THRESHOLD
    end
    local produced = tonumber(producedPerYear) or 0
    local shippedShare = produced > 0 and math.min(1, (tonumber(shippedPerYear) or 0) / produced) or 0
    local best = math.max(shippedShare, math.min(1, tonumber(bestShare) or shippedShare))
    local shipped, shippedBest = nil, nil
    if config.SHIPPED_THRESHOLD > 0 then
        if config.SHIPPED_MODE ~= 1 then shipped = shippedShare >= config.SHIPPED_THRESHOLD end
        if config.SHIPPED_MODE ~= 0 then shippedBest = best >= config.SHIPPED_THRESHOLD end
    end
    local workers = nil
    if config.WORKERS_CONDITION ~= 0 then workers = workersBoosted == true end
    local booster = nil
    if boosterActive ~= nil and config.BOOSTER_CONDITION ~= 0 then booster = boosterActive == true end
    local exp, applies = 0, 0
    for _index, met in pairs({production = production, shipped = shipped, shippedBest = shippedBest, workers = workers, booster = booster}) do
        applies = applies + 1
        if met then exp = exp + 1 end
    end
    if config.EXP_ALL_CONDITIONS ~= 0 then exp = (applies > 0 and exp == applies) and 1 or 0 end
    return exp, {
        production = production, shipped = shipped, shippedBest = shippedBest, workers = workers, booster = booster,
        productionRating = productionRating ~= nil and (tonumber(productionRating) or 0) or nil, shippedShare = shippedShare,
        bestShare = best, bestCargo = bestCargo,
    }
end

-- The engine's production rating covers the last 12 months, and a rebuild that changes the stock list
-- (a delivery order adding or dropping its stocks) starts it again from about 0 (0.0007), after which
-- it grows by about 1/12 per month. A rating below RATING_RESET right after such a rebuild is taken as
-- that reset; reset = {before, at} keeps the rating from before it and the game time.
core.RATING_RESET = 0.01

-- The rating the EXP condition and the window count: until a year has passed since a reset, the months
-- before it still count with the rating from before: live + before x (share of the year since the
-- reset still to come), at most 1. A real drop after the rebuild still shows. year = game time of a year.
function core.countedRating(live, reset, now, year)
    live = tonumber(live) or 0
    local before, at = tonumber(reset and reset.before), tonumber(reset and reset.at)
    if not before or not at or not now or now < at or not year or year <= 0 then return live end
    local left = 1 - (now - at) / year
    if left <= 0 then return live end
    return math.min(1, live + before * left)
end

-- Whether a reset no longer counts (a year has passed).
function core.resetOver(reset, now, year)
    local at = tonumber(reset and reset.at)
    return not at or not now or now < at or now - at >= year
end

-- Whether an industry processes inputs (any production rule with an input). Primary industries
-- (farms, mines, forests, ...) have none, so they always run at full production. The rules of a
-- delivery order do not count.
function core.processesInputs(rules)
    for _index, rule in ipairs(rules or {}) do
        if core.isProductionRule(rule) and hasInput(rule) then return true end
    end
    return false
end

-- Adds EXP to a record and turns every full EXP_PER_POINT into an upgrade point.
-- Returns the number of new points.
function core.addExp(record, exp)
    record.exp = (tonumber(record.exp) or 0) + exp
    record.points = tonumber(record.points) or 0
    local gained = 0
    while record.exp >= config.EXP_PER_POINT do
        record.exp = record.exp - config.EXP_PER_POINT
        record.points = record.points + 1
        gained = gained + 1
    end
    return gained
end

-- Version 1 gave up to 3 points per month; 3 old points equal one perfect month = 1 EXP.
function core.migrateRecord(record)
    local oldPoints = math.max(0, tonumber(record.points) or 0)
    record.points = 0
    record.exp = 0
    core.addExp(record, math.floor(oldPoints / 3))
end

-- "steel_mill.script@updateFn" owned by "::/industries/steel_mill/steel_mill.con"
-- becomes "::/industries/steel_mill/steel_mill.script@updateFn".
function core.absoluteRef(reference, ownerFile)
    if reference:find("::", 1, true) then return reference end
    local namespace, path = ownerFile:match("^(.-)::(.*)$")
    if not namespace then namespace, path = "", ownerFile end
    if reference:sub(1, 1) == "/" then return namespace .. "::" .. reference end
    local directory = (path:gsub("\\", "/"):match("^(.*)/") or ""):gsub("^/+", "")
    if directory == "" then return namespace .. "::/" .. reference end
    return namespace .. "::/" .. directory .. "/" .. reference
end

-- Our entry in a construction resource's updateScript.params, nil for industries we did not wrap.
-- Another mod may wrap an industry after us (Industry Tram Access does), so the outer script need not
-- be ours; such wrappers keep the params at the top level, where the base game's cargo filtering reads
-- stockListConfig, and hand them on to our script. The mark tells our entry from that of another copy
-- of the mod, which uses the same key.
function core.ownEntry(resource)
    local ok, own = pcall(function()
        local entry = resource.updateScript.params[core.KEY]
        if entry and entry.mod == core.MOD_ID then return entry end
        return nil
    end)
    return ok and own or nil
end

return core
