-- Shared pieces of the upgrade UI, used by the "Upgrades" tab (window.script) and by the card in the
-- industry tab (card.script). Plain functions, and one recipe of its own that needs state
-- (ui.CancelDelivery); the windows' recipes are registered by those script files.
-- Icons and styles come from the base game (booster card ticks, "primary, costs" buy button);
-- explanations live in tooltips to keep the window short.
local core = require "stardorn_industry_upgrades::/industry_upgrades/core.lua"
local config = require "stardorn_industry_upgrades::/industry_upgrades/config.lua"
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local guiReactUtil = ug_require "::/gui/main/gui_react_util.tl"
local cargoUtil = ug_require "::/gui/main/cargo_util.tl"
local industryUtil = ug_require "::/gui/main/industry_util.tl"
local industryReactUtil = ug_require "::/gui/entity_window/industry_react_util.tl"
local styleutil = ug_require "::/gui/main/styleutil.tl"
local productivity = ug_require "::/industries/industry_productivity_util.tl"
local langUtil = ug_require "::/scripts/lang_util.tl"

local ui = {}

ui.ICONS = {
    points = "::/gui/menu/icons/symbol_star.tga",
    exp = "::/gui/entity_window/icons/symbol_stop_watch.tga",
    production = "::/gui/entity_window/icons/production_iteration.tga",
    shipped = "::/gui/entity_window/icons/symbol_cargo_supplied.tga",
    workers = "::/gui/entity_window/icons/symbol_person.tga",
    tick = "::/gui/entity_window/icons/circle_check.tga",
    throughput = "::/gui/entity_window/icons/symbol_speed.tga",
    storage = "::/gui/entity_window/icons/symbol_cargo.tga",
    efficiency = "::/gui/entity_window/icons/production_rule.tga",
    booster = "::/gui/entity_window/icons/production_booster.tga",
    emission = "::/gui/entity_window/icons/symbol_pollution.tga",
    workerBoost = "::/gui/entity_window/icons/symbol_person_multiple.tga",
    flow = "::/gui/entity_window/icons/arrow_head_right.tga",
    upgrade = "::/gui/entity_window/icons/symbol_arrow_up.tga",
    months = "::/gui/menu/icons/calendar.tga",
    cancel = "::/gui/builtin/window/icons/symbol_close.tga",
    help = "::/gui/game_bar/icons/help.tga", -- the game bar's context help
    upkeep = "::/gui/entity_window/icons/symbol_dollar_gear.tga", -- the base game's upkeep bar (stations, vehicles)
}

-- Whole numbers without ".0" (saved state may hand them back as floats).
function ui.numberText(value)
    if type(value) == "number" and value == math.floor(value) then return string.format("%d", value) end
    return tostring(value)
end

-- Localise and fill in {placeholders}.
function ui.tr(text, values)
    local strings = {}
    for key, value in pairs(values or {}) do strings[key] = ui.numberText(value) end
    return langUtil.format(_(text), strings)
end

-- Money as the base game writes it ("$40,000").
function ui.money(value)
    local ok, text = pcall(api.util.formatMoney, math.floor((tonumber(value) or 0) + 0.5))
    return ok and text or ("$" .. ui.numberText(math.floor((tonumber(value) or 0) + 0.5)))
end

-- A change in percent, to a tenth, signed like the base game's booster card: 0.125 -> "+12.5%",
-- -0.1 -> "−10%", 0 -> "0%".
function ui.percentText(share)
    local tenths = math.floor((tonumber(share) or 0) * 1000 + 0.5)
    if tenths == 0 then return "0%" end
    local value = math.abs(tenths) / 10
    local digits = value == math.floor(value) and string.format("%d", value) or string.format("%.1f", value)
    return (tenths > 0 and "+" or "−") .. digits .. "%"
end

local NAMES = {
    throughput = "Throughput", storage = "Storage", efficiency = "Efficiency",
    booster = "Booster strength", emission = "Environmental filter", workers = "Worker boost",
}
local DESCRIPTIONS = {
    throughput = "More production cycles per year. Input demand grows along with the output, booster demand stays the same.",
    storage = "Larger input and output stocks.",
    efficiency = "Less input for the same output.",
    booster = "Boosters such as fertilizer, tools or machines work more strongly.",
    boosterDemand = "Boosters such as fertilizer, tools or machines work more strongly and need more of their cargo.",
    workersNeeded = "Higher production boost while enough workers arrive; every level adds workplaces, so more workers are needed.",
    emission = "Less noise and pollution for nearby towns.",
    workers = "Higher production boost while enough workers arrive.",
}

function ui.upgradeName(id) return ui.tr(NAMES[id]) end
-- What an upgrade does; booster strength says that boosters need more cargo when their demand rises with it.
function ui.upgradeDescription(id)
    if id == "booster" and config.BOOSTER_DEMAND ~= 0 then return ui.tr(DESCRIPTIONS.boosterDemand) end
    if id == "workers" and config.WORKERS_NEEDED ~= 0 then return ui.tr(DESCRIPTIONS.workersNeeded) end
    return ui.tr(DESCRIPTIONS[id])
end
function ui.upgradeIcon(id) return id == "workers" and ui.ICONS.workerBoost or ui.ICONS[id] end


local function boxes(filled, total)
    return string.rep("■", filled) .. string.rep("□", math.max(0, total - filled))
end

-- One box per EXP up to 12 EXP per point; above that the 12 boxes share the EXP, so the row keeps
-- its width (the exact count is shown next to it).
local MAX_EXP_BOXES = 12
local function expBoxes(exp)
    local total = math.min(config.EXP_PER_POINT, MAX_EXP_BOXES)
    return boxes(math.floor(exp * total / config.EXP_PER_POINT), total)
end

-- ■■□□□ for up to 10 levels; with more (see the setting "Number of throughput levels") "2/20", so the row keeps its width.
local MAX_LEVEL_BOXES = 10
function ui.levelBoxes(level, max)
    if max > MAX_LEVEL_BOXES then return ui.numberText(level) .. "/" .. ui.numberText(max) end
    return boxes(level, max)
end

-- getComponent throws "Invalid entity" once an entity is gone, and the window's cards update every
-- step while an upgrade rebuilds the industry (new entity ids) or it is bulldozed.
local function component(entity, componentType)
    if not entity or not api.engine.entityExists(entity) then return nil end
    return api.engine.getComponent(entity, componentType)
end

function ui.constructionOf(industryEntity)
    local industry = component(industryEntity, api.type.ComponentType.INDUSTRY)
    if not industry then return nil end
    return industry.construction, component(industry.construction, api.type.ComponentType.CONSTRUCTION)
end

-- The tab gets the construction entity; points and levels belong to its industry subconstruction.
function ui.industryOf(constructionEntity)
    local construction = component(constructionEntity, api.type.ComponentType.CONSTRUCTION)
    if not construction then return nil end
    for _index, sub in ipairs(construction.subconstructions or {}) do
        if component(sub, api.type.ComponentType.INDUSTRY) then return sub end
    end
    return nil
end

local function resource(construction)
    local resId = api.res.constructionRep.find(construction.fileName)
    return resId >= 0 and api.res.constructionRep.get(resId) or nil
end

-- The wrapper also carries the mod settings, which are applied here for everything that follows.
-- Only our own wrapper counts (not that of another copy of the mod, should one run as well).
function ui.supported(construction)
    local own = core.ownEntry(resource(construction))
    if own == nil then return false end
    local okSettings, settings = pcall(function() return own.settings end)
    core.configure(okSettings and settings or nil)
    return true
end

-- True when the industry window shows our own "Upgrades" tab.
function ui.usesTab(construction)
    local res = resource(construction)
    local ok, fileName = pcall(function() return res.entityWindowScript.fileName end)
    return ok and fileName == core.WINDOW_SCRIPT
end

local function savedRecord(constructionId)
    local scriptEntity = api.engine.system.gameScriptSystem.getEntityForGameScript(core.GAME_SCRIPT)
    if not scriptEntity or scriptEntity < 0 then return nil end
    local script = api.engine.getComponent(scriptEntity, api.type.ComponentType.GAME_SCRIPT)
    if not script then return nil end
    if script.state_native then
        local record = script.state_native:findPath({"records", tostring(constructionId)})
        return record and record:asTable() or nil
    end
    local records = script.state and script.state.records
    return records and records[tostring(constructionId)] or nil
end

local function currentBoost(industryEntity)
    local ok, boost = pcall(function() return industryUtil.getIndustryBoost(industryEntity, true, nil).boost end)
    return ok and tonumber(boost) or 1
end

-- The difficulty setting "industry productivity", which the base game's production card applies to
-- every production rule of an industry.
local function industryProductivity()
    local ok, value = pcall(function() return api.res.getBaseConfig().locations.industry.industryProductivity end)
    return ok and tonumber(value) or 1
end

-- Yearly previews of the upgrades that have one, and which kinds of rules the industry has. The
-- stock list holds the built levels; a preview reaches to toLevels[id] (nil: none). While an order's
-- stocks are built the production runs at 1 - ORDER_MALUS; the preview shows it without that.
local function previews(industryEntity, levels, toLevels, orderBuilt)
    local stockList = api.engine.getComponent(industryEntity, api.type.ComponentType.STOCK_LIST)
    if not stockList then return {}, false, false end
    local hasInput, hasBooster = false, false
    for _index, rule in ipairs(stockList.rules or {}) do
        if core.isRealBooster(rule) then -- not the rules of a delivery order
            hasBooster = true
        elseif core.isProductionRule(rule) then
            for _input, amount in ipairs(rule.input and rule.input[1] or {}) do
                if amount > 0 then hasInput = true end
            end
        end
    end
    local inputType = api.type["enum"].StockListType.InputStock
    local function isInput(stockType) return stockType == inputType end
    local function cargoName(cargo)
        local cargoType = api.res.cargoTypeRep.get(cargo)
        return cargoType and cargoType.name or tostring(cargo)
    end
    local boost = currentBoost(industryEntity) * industryProductivity()
    if orderBuilt and config.ORDER_MALUS < 1 then boost = boost / (1 - config.ORDER_MALUS) end
    local result = {}
    if toLevels.throughput then
        local ok, items = pcall(core.throughputPreview, stockList.rules, stockList.stocks, boost, levels.throughput, isInput, cargoName,
            toLevels.throughput)
        result.throughput = ok and items or nil
    end
    if hasInput and toLevels.efficiency then
        local ok, items = pcall(core.efficiencyPreview, stockList.rules, stockList.stocks, boost, levels.efficiency, isInput, cargoName,
            toLevels.efficiency)
        result.efficiency = ok and items or nil
    end
    if hasBooster and toLevels.booster and config.BOOSTER_DEMAND ~= 0 then
        local ok, items = pcall(core.boosterPreview, stockList.rules, stockList.stocks, levels.booster, isInput, cargoName, toLevels.booster)
        result.booster = ok and items or nil
    end
    return result, hasInput, hasBooster
end

-- Residents assigned to the workplaces, and those who arrived by line in the last two years
-- (what the base game counts for the worker boost).
local function workerCounts(industryEntity)
    local capacity = api.engine.getComponent(industryEntity, api.type.ComponentType.PERSON_CAPACITY)
    if not capacity or (capacity.capacity or 0) <= 0 then return nil end
    local ok, persons = pcall(function() return api.engine.system.simPersonSystem.getSimPersonsForDestination(industryEntity) end)
    local okVisitors, visitors = pcall(productivity.getVisitors, industryEntity)
    local fraction = tonumber(productivity.RequiredWorkersFractionForBoost) or 0.5
    return {
        capacity = capacity.capacity,
        assigned = ok and persons and #persons or 0,
        arrived = okVisitors and visitors and #visitors or 0,
        needed = math.ceil(capacity.capacity * fraction),
    }
end

-- Id, display name and icon of a cargo resource name. They never change during a game,
-- and the window asks for them on every step, so cargo that was found is kept.
local cargoInfos = {}
local function cargoInfo(cargo)
    if cargoInfos[cargo] then return cargoInfos[cargo] end
    local okId, id = pcall(api.res.cargoTypeRep.find, cargo)
    id = okId and tonumber(id) or -1
    local okType, cargoType = pcall(api.res.cargoTypeRep.get, id)
    local okIcon, icon = pcall(cargoUtil.getCargoIconById, id)
    local info = {
        id = id,
        name = (id >= 0 and okType and cargoType and cargoType.name) or core.cargoShortName(cargo),
        icon = id >= 0 and okIcon and icon or ui.ICONS.shipped,
    }
    if id >= 0 then cargoInfos[cargo] = info end
    return info
end

-- Whether the industry already uses or produces a cargo (resource name), so a delivery order asks for
-- another one. Same choice as the game script (core.orderRequirements on the industry's own stocks).
local function cargoInUse(industryEntity)
    local stockList = api.engine.getComponent(industryEntity, api.type.ComponentType.STOCK_LIST)
    local own = core.ownCargo(stockList and stockList.stocks, stockList and stockList.rules)
    return function(name)
        local info = cargoInfo(name)
        return info.id < 0 or own[info.id] == true
    end
end

-- {{cargo, amount}} with the cargo's id, name and icon for the window.
local function withInfo(needs)
    local result = {}
    for _index, need in ipairs(needs or {}) do
        local info = cargoInfo(need.cargo)
        result[#result + 1] = {cargo = need.cargo, amount = need.amount, id = info.id, name = info.name, icon = info.icon}
    end
    return result
end

-- The cargo some industry on the map produces (cargo type id -> true), nil when the industries could
-- not be read. Industries rarely come and go, and the window asks on every step, so the answer (a
-- failure as well) is kept for PRODUCERS_KEPT of game time (no industry spawns while paused).
local PRODUCERS_KEPT = 10000
local produced = {at = nil, cargo = nil}
local function producedCargo()
    local okTime, now = pcall(function()
        return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
    end)
    now = okTime and tonumber(now) or 0
    if produced.at and now >= produced.at and now - produced.at < PRODUCERS_KEPT then return produced.cargo end
    local cargo = {}
    local ok = pcall(function()
        local outputType = api.type["enum"].StockListType.OutputStock
        api.engine.forEachEntityWithComponent(function(entity)
            local stockList = api.engine.getComponent(entity, api.type.ComponentType.STOCK_LIST)
            for _index, stock in ipairs(stockList and stockList.stocks or {}) do
                if stock.type == outputType then cargo[stock.cargoType] = true end
            end
        end, api.type.ComponentType.INDUSTRY)
    end)
    produced = {at = now, cargo = ok and cargo or nil}
    return produced.cargo
end

-- Names of the cargo in a list of needs ({{id, name}}) that no industry on the map produces yet. None
-- when the industries could not be read: better no hint than a wrong one.
local function missingProducers(needs)
    local made, result = producedCargo(), {}
    if not made then return result end
    for _index, need in ipairs(needs or {}) do
        if need.id and need.id >= 0 and not made[need.id] then result[#result + 1] = need.name end
    end
    return result
end

-- Position of the delivery order's rule among the industry's rules (as the engine's ruleDatas are
-- numbered), nil while its stocks are not built.
local function orderRuleNumber(industryEntity)
    local stockList = api.engine.getComponent(industryEntity, api.type.ComponentType.STOCK_LIST)
    for index, rule in ipairs(stockList and stockList.rules or {}) do
        if core.isOrderRule(rule) then return index end
    end
    return nil
end

-- What each cargo of the order holds in its stock right now (need.stock): delivered but not consumed
-- yet. The order's stock is the industry's only one of that cargo (an order never asks for the
-- industry's own cargo), read like the base game's window does (simEntityAtStockSystem.getStockCount).
-- 0 while the order's stocks are not built.
local function addOrderStocks(industryEntity, order)
    for _index, need in ipairs(order.cargo) do need.stock = 0 end
    if not order.built then return end
    pcall(function()
        local stockList = api.engine.getComponent(industryEntity, api.type.ComponentType.STOCK_LIST)
        for position, stock in ipairs(stockList and stockList.stocks or {}) do
            for _index, need in ipairs(order.cargo) do
                if need.id >= 0 and stock.cargoType == need.id then
                    need.stock = tonumber(api.engine.system.simEntityAtStockSystem.getStockCount(industryEntity, position - 1)) or 0
                end
            end
        end
    end)
end

-- The open delivery order of the saved record, with cargo names, icons and lot sizes for the window.
-- rows: {{id, from, to}} per upgrade in the order. nil without an order (or a broken one without
-- targets).
local function openOrder(record, params)
    local order = record and record.order
    if not order or not order.targets then return nil end
    local okTime, now = pcall(function()
        return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
    end)
    local progress = core.orderProgress(order, okTime and tonumber(now) or nil, api.util.getDefaultYearDuration())
    local cargo = {}
    for index, need in ipairs(order.cargo or {}) do
        local info = cargoInfo(need.cargo)
        cargo[#cargo + 1] = {cargo = need.cargo, amount = tonumber(need.amount) or 0, lot = progress.lots[index] or 0,
            delivered = math.min(tonumber(need.delivered) or 0, tonumber(need.amount) or 0), id = info.id, name = info.name, icon = info.icon}
    end
    local rows = {}
    for _index, upgrade in ipairs(core.UPGRADES) do
        local target = tonumber(order.targets[upgrade.id])
        if target then rows[#rows + 1] = {id = upgrade.id, from = tonumber(order.from and order.from[upgrade.id]) or 0, to = target} end
    end
    return {targets = order.targets, rows = rows, cargo = cargo, progress = progress,
        built = not order.refit and core.sameTargets(core.orderTargets(params), order.targets)}
end

-- The plan of the saved record: rows {{id, from, to}}, the cargo all planned levels need together and
-- the months they take at least.
local function plannedOrder(record, params, isUsed)
    local from, targets = core.planTargets(record, params)
    if not targets then return nil end
    local rows = {}
    for _index, upgrade in ipairs(core.UPGRADES) do
        if targets[upgrade.id] then rows[#rows + 1] = {id = upgrade.id, from = from[upgrade.id], to = targets[upgrade.id]} end
    end
    local needs, count = core.orderRequirements(targets, function(id) return from[id] end, isUsed)
    return {rows = rows, targets = targets, needs = withInfo(needs), months = core.orderMonths(needs, count)}
end

-- What the next level of each upgrade after the plan costs at this industry: id -> {{cargo, amount,
-- id, name, icon}}, nothing for upgrades at their maximum.
local function nextCosts(record, params, isUsed)
    local result = {}
    for _index, upgrade in ipairs(core.UPGRADES) do
        local planned = core.plannedLevel(record, params, upgrade.id)
        if core.deliveryMode() and planned < upgrade.max then
            result[upgrade.id] = withInfo(core.orderRequirements({[upgrade.id] = planned + 1}, function() return planned end, isUsed))
        end
    end
    return result
end

function ui.snapshot(industryEntity)
    local constructionId, construction = ui.constructionOf(industryEntity)
    if not construction or not ui.supported(construction) then return nil end
    local params = construction.params_native and construction.params_native:asTable() or construction.params or {}
    local levels = {}
    for _index, upgrade in ipairs(core.UPGRADES) do levels[upgrade.id] = core.level(params, upgrade.id) end
    local record = savedRecord(constructionId)
    if record then core.migrateTargets(record) end -- a version 2 state until the game script's next update
    -- bought levels still waiting for their rebuild, and those just built (shown as active)
    local pending, done = core.pendingTargets(record, params) or {}, {}
    for id, level in pairs(record and record.targets or {}) do
        if core.UPGRADE_BY_ID[id] and tonumber(level) == levels[id] and levels[id] > 0 then done[id] = true end
    end
    -- the level each upgrade has once the plan is built, and the level a preview reaches to: the
    -- planned one, else the next one
    local planned, toLevels = {}, {}
    for _index, upgrade in ipairs(core.UPGRADES) do
        local id = upgrade.id
        planned[id] = core.deliveryMode() and core.plannedLevel(record, params, id) or (pending[id] or levels[id])
        local to = (core.deliveryMode() and planned[id] > levels[id]) and planned[id] or planned[id] + 1
        if to <= upgrade.max then toLevels[id] = to end
    end
    local order = openOrder(record, params)
    -- the cycle line only for a booster: a plain rule's cycles take a few game hours (core.ORDER_FAST_RATE)
    if order and order.built and not core.plainOrderRule() then order.ruleNumber = orderRuleNumber(industryEntity) end
    if order then addOrderStocks(industryEntity, order) end
    local preview, hasInput, hasBooster = previews(industryEntity, levels, toLevels, order ~= nil and order.built)
    local workers = workerCounts(industryEntity)
    local okBoost, workerBoost = pcall(productivity.getPersonCapacityPotentialBoost, industryEntity)
    -- the workers the boost needs now and after the next worker boost level (setting "Workers needed per level")
    local workersNeeded
    if workers and toLevels.workers and config.WORKERS_NEEDED ~= 0 then
        local fraction = tonumber(productivity.RequiredWorkersFractionForBoost) or 0.5
        workersNeeded = {now = workers.needed,
            next = math.ceil(core.workplaces(workers.capacity, levels.workers, toLevels.workers) * fraction - 1e-9)}
    end
    local isUsed = cargoInUse(industryEntity)
    -- a plan only while upgrades cost deliveries; one kept from before a switch to EXP points stays hidden
    local plan = core.deliveryMode() and plannedOrder(record, params, isUsed) or nil
    local okYear, year = pcall(api.engine.util.getYear)
    year = okYear and tonumber(year) or nil
    local s = {
        constructionId = constructionId,
        industryEntity = industryEntity,
        levels = levels,
        level = levels.throughput,
        points = record and record.points or nil,
        exp = record and record.exp or 0,
        pending = pending,
        -- the game refused the last rebuild for the pending levels, and the points they cost
        refused = record ~= nil and record.refused == true and next(pending) ~= nil,
        refund = core.refundPoints(pending, params),
        done = done,
        planned = planned,
        last = record and record.last or nil,
        previews = preview,
        workers = workers,
        workerBoost = okBoost and tonumber(workerBoost) or nil,
        workersNeeded = workersNeeded,
        -- upgrades that change anything at this industry
        available = {throughput = true, storage = true, emission = true, efficiency = hasInput, booster = hasBooster,
            workers = workers ~= nil},
        order = order,
        plan = plan,
        toLevels = toLevels,
        nextCosts = nextCosts(record, params, isUsed),
        -- cargo of the plan and of the open order no industry on the map produces yet
        missing = {plan = plan and missingProducers(plan.needs) or {}, order = order and missingProducers(order.cargo) or {}},
        -- the year (inflation) and the money the built levels cost a month
        year = year,
        upkeep = core.upkeep(levels, year),
    }
    local parts = {tostring(constructionId), tostring(s.points), tostring(s.exp),
        tostring(s.last and s.last.exp), tostring(s.workerBoost), tostring(year), tostring(s.refused)}
    for _index, upgrade in ipairs(core.UPGRADES) do
        parts[#parts + 1] = tostring(pending[upgrade.id]) .. tostring(done[upgrade.id]) .. tostring(planned[upgrade.id])
    end
    for _index, field in ipairs({"production", "shipped", "shippedBest", "workers", "booster", "productionRating", "shippedShare",
        "bestShare", "bestCargo"}) do
        parts[#parts + 1] = tostring(s.last and s.last[field])
    end
    for _index, upgrade in ipairs(core.UPGRADES) do parts[#parts + 1] = levels[upgrade.id] end
    for _index, upgrade in ipairs(core.UPGRADES) do
        for _row, row in ipairs(preview[upgrade.id] or {}) do
            for _input, item in ipairs(row.inputs) do parts[#parts + 1] = item.now .. ">" .. item.next end
            for _output, item in ipairs(row.outputs) do parts[#parts + 1] = item.now .. ">" .. item.next end
        end
    end
    if workers then parts[#parts + 1] = workers.assigned .. "/" .. workers.arrived .. "/" .. workers.capacity end
    if workersNeeded then parts[#parts + 1] = "needed" .. workersNeeded.now .. ">" .. workersNeeded.next end
    if order then
        parts[#parts + 1] = "order" .. tostring(order.built) .. tostring(order.ruleNumber)
        for _index, row in ipairs(order.rows) do parts[#parts + 1] = row.id .. row.from .. ">" .. row.to end
        for _index, need in ipairs(order.cargo) do parts[#parts + 1] = need.cargo .. need.delivered .. "/" .. need.amount .. ":" .. need.stock end
    end
    if plan then
        parts[#parts + 1] = "plan" .. plan.months
        for _index, need in ipairs(plan.needs) do parts[#parts + 1] = need.cargo .. need.amount end
    end
    for _index, upgrade in ipairs(core.UPGRADES) do -- fixed order, so equal snapshots get equal keys
        for _need, need in ipairs(s.nextCosts[upgrade.id] or {}) do parts[#parts + 1] = upgrade.id .. need.cargo .. need.amount end
    end
    for _index, name in ipairs(s.missing.plan) do parts[#parts + 1] = "missing plan " .. name end
    for _index, name in ipairs(s.missing.order) do parts[#parts + 1] = "missing order " .. name end
    s.key = table.concat(parts, "|")
    return s
end

function ui.sameSnapshot(a, b)
    if a == nil or b == nil then return a == b end
    return a.key == b.key
end

-- The level an upgrade has once the pending rebuild is done; the next purchase buys the one after.
function ui.pendingLevel(s, id) return s.pending[id] or s.levels[id] end
-- The level an upgrade has once the plan is built (for upgrades bought with points: the pending one).
function ui.plannedLevel(s, id) return s.planned[id] end
function ui.done(s, id) return s.done[id] == true end
function ui.cost(s, id) return core.cost(ui.pendingLevel(s, id) + 1) end
-- Whether the open order builds levels of an upgrade (an order may outlast a switch to EXP points).
function ui.inOrder(s, id) return s.order ~= nil and s.order.targets[id] ~= nil end
-- In delivery mode upgrades cost no points: their levels are planned and delivered together. Bought
-- with points, an upgrade in the open order waits for it (see the game script's buy).
function ui.affordable(s, id)
    if core.deliveryMode() then return #(s.nextCosts[id] or {}) > 0 end
    return s.points ~= nil and s.points >= ui.cost(s, id) and not ui.inOrder(s, id)
end

-- Whether the upgrades cost points (EXP mode): the points card is only shown then, the plan card only
-- otherwise. Ask after ui.snapshot, which applies the construction's settings.
function ui.anyPointUpgrades()
    return not core.deliveryMode()
end

-- "300 Planks, 200 Plastic"
local function needsText(needs)
    local parts = {}
    for _index, need in ipairs(needs or {}) do parts[#parts + 1] = ui.numberText(need.amount) .. " " .. need.name end
    return table.concat(parts, ", ")
end

function ui.title(s)
    return (s and s.points and ui.anyPointUpgrades()) and ui.tr("Upgrades · Points: {points}", {points = s.points}) or ui.tr("Upgrades")
end

function ui.vertical(children)
    return builtin.BoxLayout{orientation = builtin.type.Orientation.Vertical, children = children}
end

function ui.icon(path, tooltip)
    return builtin.ImageView{meta = {tooltip = tooltip}, path = path, scaling = builtin.type.ImageViewScaling.AutoFit}
end

local function text(value, class, tooltip, unicode)
    return builtin.TextView{meta = {class = class, tooltip = tooltip}, text = value, useUnicodeCompatibilityFont = unicode}
end

-- The booster card's tick: the base game styles it white when the parent has the class "boosted".
function ui.tick(met, tooltip)
    return builtin.Component{
        meta = {class = met and "boosted" or ""},
        layout = builtin.BoxLayout{orientation = builtin.type.Orientation.Horizontal, children = {
            builtin.ImageView{meta = {class = "boost-tick-icon", tooltip = tooltip}, path = ui.ICONS.tick},
        }},
    }
end

function ui.lastMonthText(s)
    if not s.last then return text(ui.tr("First check pending"), "font-scale-annotation") end
    return text(ui.tr("+{exp} EXP last month", {exp = s.last.exp or 0}), "font-scale-annotation")
end

-- ★ 1  +1 EXP last month    ⏱ ■■■□□□□□□□□□ 3/12
function ui.pointsSummary(s)
    local pointsTip = ui.tr("Upgrade points available.")
    local expTip = ui.tr(config.EXP_ALL_CONDITIONS ~= 0
        and "Experience: +1 in a month that meets all conditions. {exp} EXP = 1 upgrade point."
        or "Experience: +1 for every condition met in a month. {exp} EXP = 1 upgrade point.", {exp = config.EXP_PER_POINT})
    local exp = math.floor(tonumber(s.exp) or 0)
    return guiReactUtil.makeHorizontalBox({
        ui.icon(ui.ICONS.points, pointsTip),
        text(s.points and ui.numberText(s.points) or "-", "font-scale-body", pointsTip),
        ui.lastMonthText(s),
        guiReactUtil.makeHorizontalSpacer(),
        ui.icon(ui.ICONS.exp, expTip),
        text(expBoxes(exp), nil, expTip, true),
        text(ui.numberText(exp) .. "/" .. ui.numberText(config.EXP_PER_POINT), "font-scale-body", expTip),
    })
end

-- The upkeep of the industry's built levels like the base game's upkeep bar of stations and vehicles:
-- 💲 $40,000/Month. nil (no node) without upkeep, so nothing is created that the card leaves out.
function ui.upkeepRow(s)
    if config.UPKEEP_BASE <= 0 or (tonumber(s.upkeep) or 0) <= 0 then return nil end
    local tip = ui.tr("Upkeep of this industry's upgrade levels, charged every month and rising with inflation. In the finances under {general}, {upkeepOther}.",
        {general = _("General"), upkeepOther = _("Upkeep Other")})
    return guiReactUtil.makeHorizontalBox({
        builtin.ImageView{meta = {tooltip = ui.tr("Upkeep")}, path = ui.ICONS.upkeep, scaling = builtin.type.ImageViewScaling.AutoFit},
        text(ui.tr("{maintenanceCost}/{maintenancePeriod}", {maintenanceCost = ui.money(s.upkeep), maintenancePeriod = _("Month")}),
            "font-scale-body", tip),
    })
end

-- Last month's conditions side by side, each like a booster card entry: icon, value, tick; each met
-- condition gave +1 EXP (with EXP_ALL_CONDITIONS all of them together 1). workers (optional): live counts, shown as arrivals/needed like the booster
-- card. Production only appears for industries that process inputs, the booster only for industries
-- with boosters. Shipping shows all products together (📦), the best product (its cargo icon) or
-- both, see core.monthlyExp; more than three conditions wrap into a second row.
-- 🔁 100% ✓    🌾 100% ✓    👤 2/10 ✓
local CONDITIONS_PER_ROW = 3

function ui.conditionRow(last, workers)
    local function percent(value) return ui.numberText(math.floor((value or 0) * 100 + 0.5)) .. "%" end
    local conditions = {}
    if last.production ~= nil then
        conditions[#conditions + 1] = {ui.ICONS.production, percent(last.productionRating), last.production,
            ui.tr("Production rating, needs {value}% or more", {value = math.floor(config.PRODUCTION_THRESHOLD * 100 + 0.5)})}
    end
    local shippedThreshold = math.floor(config.SHIPPED_THRESHOLD * 100 + 0.5)
    if last.shipped ~= nil then
        conditions[#conditions + 1] = {ui.ICONS.shipped, percent(last.shippedShare), last.shipped,
            ui.tr("Shipped share of all products together, needs {value}% or more", {value = shippedThreshold})}
    end
    if last.shippedBest ~= nil then
        -- the product shipped best, with its icon (a state of an older version: the shipped icon)
        local cargoType = tonumber(last.bestCargo)
        local okType, info = pcall(api.res.cargoTypeRep.get, cargoType)
        local okIcon, icon = pcall(cargoUtil.getCargoIconById, cargoType)
        local name = cargoType and okType and info and info.name or ui.tr("Best product")
        conditions[#conditions + 1] = {cargoType and okIcon and icon or ui.ICONS.shipped, percent(last.bestShare), last.shippedBest,
            ui.tr("Best shipped product: {cargo}, needs {value}% or more", {cargo = name, value = shippedThreshold})}
    end
    if last.workers ~= nil then
        local value, tooltip = "", ui.tr("Worker boost active")
        if workers then
            value = ui.numberText(workers.arrived) .. "/" .. ui.numberText(workers.needed)
            tooltip = table.concat({
                tooltip,
                ui.tr("Assigned workers: {assigned}/{capacity}", {assigned = workers.assigned, capacity = workers.capacity}),
                ui.tr("Arrived by line in the last two years: {arrived}/{needed}", {arrived = workers.arrived, needed = workers.needed}),
            }, "\n")
        end
        conditions[#conditions + 1] = {ui.ICONS.workers, value, last.workers, tooltip}
    end
    if last.booster ~= nil then
        conditions[#conditions + 1] = {ui.ICONS.booster, nil, last.booster, ui.tr("Booster active")}
    end
    -- A table like the booster card's: icon, value, tick and a stretching gap per condition, at most
    -- CONDITIONS_PER_ROW per row. A row of boxes could not shrink and ran over the card's edge with four
    -- conditions; the table wraps the rest into the next row instead.
    local rows, weights = {}, {}
    for _column = 1, CONDITIONS_PER_ROW do
        for _index, weight in ipairs({-1, -1, -1, 1}) do weights[#weights + 1] = weight end
    end
    for first = 1, #conditions, CONDITIONS_PER_ROW do
        local cells = {}
        for index = first, first + CONDITIONS_PER_ROW - 1 do
            local condition = conditions[index]
            if condition then
                local icon, conditionValue, met, conditionTip = condition[1], condition[2], condition[3], condition[4]
                cells[#cells + 1] = ui.icon(icon, conditionTip)
                cells[#cells + 1] = text(conditionValue or "", "font-scale-body", conditionTip)
                cells[#cells + 1] = ui.tick(met, conditionTip)
            else
                for _cell = 1, 3 do cells[#cells + 1] = text("", nil, nil) end
            end
            cells[#cells + 1] = text("", nil, nil)
        end
        rows[#rows + 1] = builtin.Row{cells = cells}
    end
    -- Same container class as the booster card, so the ticks get the base game's styling.
    return builtin.Component{meta = {class = "booster-widget"}, layout = builtin.TableLayout{columnWeights = weights, rows = rows}}
end

-- Effect of an upgrade at a level in percent against the base game, the way the base game's booster card
-- writes a boost: throughput "+12.5%", efficiency "−10%". The worker boost shows the resulting boost like
-- that card (industry_react_util, factor - 1 in whole percent): "+81%".
local function effectText(s, id, level)
    if id == "workers" then
        local base = (s.workerBoost or 2) - core.effect("workers", s.levels.workers)
        return "+" .. ui.numberText(math.floor((base + core.effect("workers", level) - 1) * 100 + 0.5)) .. "%"
    end
    return ui.percentText(core.effect(id, level) - 1)
end

-- The next level the button plans (or buys), its effect and its cost.
function ui.upgradeTooltip(s, id)
    local upgrade = core.UPGRADE_BY_ID[id]
    local delivery = core.deliveryMode()
    local level = delivery and ui.plannedLevel(s, id) or ui.pendingLevel(s, id)
    local lines = {ui.upgradeDescription(id)}
    if level < upgrade.max then
        table.insert(lines, 1, ui.tr("Level {level}: {from} -> {to}",
            {level = level + 1, from = effectText(s, id, level), to = effectText(s, id, level + 1)}))
        if config.UPKEEP_BASE > 0 then
            lines[#lines + 1] = ui.tr("Level {level} adds {cost} upkeep per month.",
                {level = level + 1, cost = ui.money(core.upkeepStep(level, s.year))})
        end
        if delivery then
            lines[#lines + 1] = ui.tr("Level {level} costs a delivery to this industry: {cargo}",
                {level = level + 1, cargo = needsText(s.nextCosts[id])})
        elseif ui.inOrder(s, id) then
            lines[#lines + 1] = ui.tr("Finish or cancel the upgrade in progress first.")
        elseif s.points ~= nil and not ui.affordable(s, id) then
            lines[#lines + 1] = ui.tr("Not enough upgrade points ({points}/{cost})", {points = s.points, cost = ui.cost(s, id)})
        end
    end
    return table.concat(lines, "\n")
end

-- One recipe: consumed cargo  ➜  produced cargo, each as icon with "now → after the upgrade" per year.
function ui.previewRow(row)
    local function item(entry)
        local tooltip = ui.tr("{cargo} per year at the current boost: {from} now, {to} after the upgrade",
            {cargo = entry.name, from = entry.now, to = entry.next})
        local ok, icon = pcall(cargoUtil.getCargoIconById, entry.cargo)
        local amount = ui.numberText(entry.now)
        if entry.next ~= entry.now then amount = amount .. " → " .. ui.numberText(entry.next) end
        return guiReactUtil.makeHorizontalBox({
            ui.icon(ok and icon or ui.ICONS.shipped, tooltip),
            text(amount, "font-scale-body", tooltip, true),
        })
    end
    local children = {}
    for _index, entry in ipairs(row.inputs) do children[#children + 1] = item(entry) end
    if #row.inputs > 0 and #row.outputs > 0 then children[#children + 1] = ui.icon(ui.ICONS.flow) end
    for _index, entry in ipairs(row.outputs) do children[#children + 1] = item(entry) end
    -- Wraps onto the next line when a recipe has many cargos (like the base game's cargo icon lists).
    return builtin.Component{layout = builtin.FlowLayout{children = children}}
end

function ui.buy(s, id)
    api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", core.EVENT_ID, core.EVENT_BUY,
        {construction = s.constructionId, upgrade = id}))
end

function ui.refund(s)
    api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", core.EVENT_ID, core.EVENT_REFUND, {construction = s.constructionId}))
end

function ui.cancelDelivery(s)
    api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", core.EVENT_ID, core.EVENT_CANCEL, {construction = s.constructionId}))
end

function ui.changePlan(s, id, change)
    api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", core.EVENT_ID, core.EVENT_PLAN,
        {construction = s.constructionId, upgrade = id, change = change}))
end

function ui.startPlan(s)
    api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", core.EVENT_ID, core.EVENT_START, {construction = s.constructionId}))
end

function ui.discardPlan(s)
    api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", core.EVENT_ID, core.EVENT_DISCARD, {construction = s.constructionId}))
end

-- Amount and icon per cargo: "300 🪵 200 🧴".
local function cargoChildren(needs)
    local children = {}
    for _index, need in ipairs(needs or {}) do
        children[#children + 1] = text(ui.numberText(need.amount), "font-scale-body")
        children[#children + 1] = ui.icon(need.icon, need.name)
    end
    return children
end

-- What the button costs: "1 ★", or in delivery mode the delivery of that level.
local function costChildren(s, id)
    if not core.deliveryMode() then
        return {text(ui.numberText(ui.cost(s, id)), "font-scale-body"), ui.icon(ui.ICONS.points)}
    end
    return cargoChildren(s.nextCosts[id])
end

local function horizontal(children)
    return builtin.Component{layout = builtin.BoxLayout{orientation = builtin.type.Orientation.Horizontal, children = children}}
end

-- Why the bought levels wait, what the player can do, and, while upgrades cost points, the button that
-- returns them. Only while s.refused.
function ui.refusedSection(s)
    local children = {text(ui.tr("The game refused to rebuild this industry, so the bought levels cannot be built. The usual cause is the industry's access road where it meets roads built or changed later. Disconnect those roads at the entrance: the mod tries again at the next monthly check. Then connect them again."),
        "font-scale-body")}
    if not core.deliveryMode() and s.refund > 0 then
        children[#children + 1] = builtin.Button{
            meta = {forceFocusable = true, tooltip = ui.tr("Cancels the levels that wait for the rebuild and returns their points.")},
            content = horizontal({ui.icon(ui.ICONS.points), text(ui.tr("Refund {points} points", {points = s.refund}), "font-scale-body")}),
            onClick = function() ui.refund(s) end,
        }
    end
    return children
end

-- The base game's buy button style: "⬆ Level 2 ........ 1 ★". It stays available while bought levels
-- wait for their rebuild: further purchases end up in the same rebuild. In delivery mode the button
-- adds the level to the plan ("⬆ Plan level 2 ........ 300 🪵"), with a "−" button next to it that
-- takes the highest planned level out again.
function ui.upgradeButton(s, id, hint)
    local delivery = core.deliveryMode()
    local level = delivery and ui.plannedLevel(s, id) or ui.pendingLevel(s, id)
    local planned = delivery and s.plan ~= nil and s.plan.targets[id] ~= nil
    local remove = nil
    if planned then
        remove = builtin.Button{
            meta = {forceFocusable = true, tooltip = ui.tr("Remove level {level} from the plan", {level = level})},
            content = text("−", "font-scale-body", nil, true),
            onClick = function() ui.changePlan(s, id, -1) end,
        }
    end
    local main
    if level >= core.UPGRADE_BY_ID[id].max then
        -- a level in progress or waiting for its rebuild has its own line above
        main = text(planned and ui.tr("Maximum level planned.") or ui.tr("Maximum level reached."), "font-scale-body")
    else
        local children = {
            ui.icon(ui.ICONS.upgrade),
            text(delivery and ui.tr("Plan level {level}", {level = level + 1}) or ui.tr("Level {level}", {level = level + 1}), "font-scale-body"),
            guiReactUtil.makeHorizontalSpacer(),
        }
        for _index, child in ipairs(costChildren(s, id)) do children[#children + 1] = child end
        main = builtin.Button{
            meta = {class = "primary, costs", forceFocusable = true, enabled = ui.affordable(s, id), tooltip = hint},
            content = horizontal(children),
            onClick = function()
                if delivery then ui.changePlan(s, id, 1) else ui.buy(s, id) end
            end,
        }
    end
    if not remove then return main end
    return guiReactUtil.makeHorizontalBox({main, remove})
end

-- The open order like the production bar of a landmark construction site (the base
-- game's industry_react_util.ProductionRuleWidget): per cargo its icon with the lot size as bubble on
-- the arrow-shaped bar, below it what its stock holds ("31 in stock"; the amounts delivered are in the
-- bar of the whole order). Below it the cycle the
-- order's rule is running, as the landmark shows it (the base game's RuleProgressBar, its duration as
-- tooltip; only once the order's stocks are built), and the progress of the whole order like the bar
-- of a landmark's notification, with icons in place of its cargo names: "🪵 59/90 · 📅 8" laid over the
-- bar (as the base game's ProgressDisplay lays its text; a ProgressBar's label takes plain text only).
-- The base game's style rules for these only apply inside its own recipes, so
-- gui/industry_upgrades_order.css.lua repeats them for these classes.
local BAR_WIDTH = 390       -- the base game's productionRuleBackgroundSize
local BAR_INPUT_WIDTH = 275 -- its foreground for a rule with inputs only: 390 - 4 * 60 + 2 * 60 + 20 / 4

local function sized(width) return styleutil.makeStyle{size = {width, -1}} end

function ui.orderBar(s)
    local order = s.order
    local items = {}
    for _index, need in ipairs(order.cargo) do
        local tooltip = ui.tr("{cargo}: {stock} in stock · {used} of {amount} used",
            {cargo = need.name, stock = need.stock, used = need.delivered, amount = need.amount})
        items[#items + 1] = builtin.Component{
            meta = {class = "industry-upgrades-order-item"},
            layout = ui.vertical({
                industryReactUtil.ProductionIconWithBubble{icon = need.icon, iconTooltip = tooltip, count = ui.numberText(need.lot),
                    countTooltip = ui.tr("Consumed per cycle, together with the other cargo")},
                text(ui.numberText(need.stock), "font-scale-headline", tooltip),
                text(ui.tr("in stock"), "font-scale-annotation", tooltip),
            }),
        }
    end
    local background = builtin.Component{layout = builtin.FloatingLayout{children = {
        builtin.FloatingLayoutChild{item = builtin.Component{meta = {class = "industry-upgrades-order-background", styleSheet = sized(BAR_WIDTH)}}},
        builtin.FloatingLayoutChild{item = builtin.Component{meta = {class = "industry-upgrades-order-foreground", styleSheet = sized(BAR_INPUT_WIDTH)}}},
    }}}
    local children = {
        builtin.FloatingLayout{children = {
            background,
            builtin.FloatingLayoutChild{item = builtin.Component{
                meta = {styleSheet = sized(BAR_INPUT_WIDTH)},
                layout = builtin.BoxLayout{orientation = builtin.type.Orientation.Horizontal, children = items},
            }},
        }},
    }
    if order.ruleNumber then
        children[#children + 1] = builtin.Component{
            meta = {class = "industry-upgrades-order-cycle"},
            layout = ui.vertical({
                industryReactUtil.RuleProgressBar{entity = s.industryEntity, ruleNumber = order.ruleNumber, durationAsTooltip = true,
                    invertProgressBar = false},
            }),
        }
    end
    local progress = order.progress
    local progressText = ui.tr("{percent}% used · months left at full supply: {months}",
        {percent = math.floor(progress.fraction * 100), months = progress.months})
    local content = {}
    for _index, need in ipairs(order.cargo) do
        local tooltip = ui.tr("{cargo}: {used} of {amount} used", {cargo = need.name, used = need.delivered, amount = need.amount})
        content[#content + 1] = ui.icon(need.icon, tooltip)
        content[#content + 1] = text(ui.numberText(need.delivered) .. "/" .. ui.numberText(need.amount), "font-scale-annotation", tooltip)
    end
    content[#content + 1] = text("·", "font-scale-annotation")
    content[#content + 1] = ui.icon(ui.ICONS.months, progressText)
    content[#content + 1] = text(ui.numberText(progress.months), "font-scale-annotation", progressText)
    children[#children + 1] = builtin.Component{
        meta = {class = "industry-upgrades-order-total"},
        layout = builtin.FloatingLayout{children = {
            builtin.FloatingLayoutChild{v = -1, h = -1, item = builtin.ProgressBar{meta = {tooltip = progressText}, value = progress.fraction}},
            builtin.FloatingLayoutChild{v = 0.5, h = 0.5, item = builtin.Component{
                meta = {class = "industry-upgrades-order-total-content"},
                layout = builtin.BoxLayout{orientation = builtin.type.Orientation.Horizontal, children = content},
            }},
        }},
    }
    return builtin.Component{meta = {class = "industry-upgrades-order"}, layout = ui.vertical(children)}
end

function ui.orderTitle(_s)
    return ui.tr("Upgrade in progress")
end

-- "⬆ Throughput: level 2 → 4", one line per upgrade of an order or plan.
local function levelRows(rows)
    local result = {}
    for _index, row in ipairs(rows) do
        result[#result + 1] = guiReactUtil.makeHorizontalBox({
            ui.icon(ui.upgradeIcon(row.id)),
            text(ui.tr("{upgrade}: level {from} → {to}", {upgrade = ui.upgradeName(row.id), from = row.from, to = row.to}),
                "font-scale-body", nil, true),
        })
    end
    return result
end

local function addMalusAndMissing(children, missing)
    if config.ORDER_MALUS > 0 then
        local malus = ui.tr("Production −{malus}% until complete", {malus = math.floor(config.ORDER_MALUS * 100 + 0.5)})
        -- the icon as small as the annotation next to it (gui/industry_upgrades_order.css.lua)
        children[#children + 1] = builtin.Component{
            meta = {class = "industry-upgrades-order-malus"},
            layout = builtin.BoxLayout{orientation = builtin.type.Orientation.Horizontal, children = {
                ui.icon(ui.ICONS.production, malus),
                text(malus, "font-scale-annotation", nil, true),
            }},
        }
    end
    for _index, name in ipairs(missing or {}) do
        children[#children + 1] = text(ui.tr("No industry on the map produces {cargo} yet.", {cargo = name}), "font-scale-annotation")
    end
end

-- The open order with its levels, the landmark's bar, a status line until its stocks are built, and the
-- cancel button.
-- "✕ Cancel delivery", asking first: the first click shows the question with the button that cancels
-- and one that keeps the order. The base game's dialog windows need a window container, which an
-- entity window does not hand out. params = {snapshot}.
ui.CancelDelivery = react.RegisterRecipe("IndustryUpgradesCancelDelivery", function(params)
    local confirming = react.useState(false)
    local function cancelButton(onClick, tooltip)
        return builtin.Button{
            meta = {forceFocusable = true, tooltip = tooltip},
            content = horizontal({ui.icon(ui.ICONS.cancel), text(ui.tr("Cancel delivery"), "font-scale-body")}),
            onClick = onClick,
        }
    end
    -- a recipe must return a layout, never a widget ("Recipe child must be a layout")
    if not confirming:old() then
        return builtin.BoxLayout{orientation = builtin.type.Orientation.Horizontal, children = {
            cancelButton(function() confirming:set(true) end, ui.tr("Cargo delivered so far is lost.")),
        }}
    end
    return ui.vertical({
        text(ui.tr("Cancel the delivery? Cargo delivered so far is lost."), "font-scale-body"),
        guiReactUtil.makeHorizontalBox({
            cancelButton(function()
                confirming:set(false)
                ui.cancelDelivery(params.snapshot)
            end),
            builtin.Button{
                meta = {class = "primary", forceFocusable = true},
                content = text(ui.tr("Keep delivering"), "font-scale-body"),
                onClick = function() confirming:set(false) end,
            },
        }),
    })
end)

function ui.orderSection(s)
    local children = levelRows(s.order.rows)
    children[#children + 1] = ui.orderBar(s)
    if not s.order.built then
        children[#children + 1] = text(ui.tr("Setting up the delivery in a few seconds (not while paused)"), "font-scale-body")
    end
    addMalusAndMissing(children, s.missing.order)
    children[#children + 1] = ui.CancelDelivery{snapshot = s}
    return children
end

-- The planned levels, what they cost together and take at least, and the buttons to
-- start or discard the plan. Start waits for the open order.
function ui.planSection(s)
    if not s.plan then
        return {text(ui.tr("Plan levels below. Nothing changes at the industry before you start the upgrade."), "font-scale-body")}
    end
    local children = levelRows(s.plan.rows)
    children[#children + 1] = horizontal(cargoChildren(s.plan.needs))
    children[#children + 1] = text(ui.tr("Takes at least {months} months", {months = s.plan.months}), "font-scale-annotation")
    addMalusAndMissing(children, s.missing.plan)
    local startTip = s.order and ui.tr("Finish or cancel the upgrade in progress first.")
        or ui.tr("One delivery for all planned levels. Every further level adds only {share}% of a level's time.",
            {share = math.floor(config.BUNDLE_SHARE * 100 + 0.5)})
    children[#children + 1] = guiReactUtil.makeHorizontalBox({
        builtin.Button{
            meta = {class = "primary", forceFocusable = true, enabled = s.order == nil and #s.plan.needs > 0, tooltip = startTip},
            content = text(ui.tr("Start upgrade"), "font-scale-body"),
            onClick = function() ui.startPlan(s) end,
        },
        builtin.Button{
            meta = {forceFocusable = true},
            content = text(ui.tr("Discard plan"), "font-scale-body"),
            onClick = function() ui.discardPlan(s) end,
        },
    })
    return children
end

-- (icon) ■■□□□  +50% → +100% / yearly preview, one row per recipe / "Upgrading to level n..." /
-- "In progress: level n" / "Planned: level n" / button / "✓ Level n active". The factor and the
-- preview go from the built level to the planned one, or else to the level the button adds.
function ui.upgradeSection(s, id)
    local upgrade = core.UPGRADE_BY_ID[id]
    local level = s.levels[id]
    local toLevel = s.toLevels[id]
    local hint = ui.upgradeTooltip(s, id)
    local factor = effectText(s, id, level)
    if toLevel then factor = factor .. " → " .. effectText(s, id, toLevel) end
    local children = {guiReactUtil.makeHorizontalBox({
        ui.icon(ui.upgradeIcon(id), hint),
        text(ui.levelBoxes(level, upgrade.max), nil, ui.tr("Level {level}/{max}", {level = level, max = upgrade.max}), true),
        text(factor, "font-scale-body", hint, true),
    })}
    if toLevel then
        for _index, row in ipairs(s.previews[id] or {}) do children[#children + 1] = ui.previewRow(row) end
        if id == "workers" and s.workersNeeded then
            local needed = s.workersNeeded
            local tip = ui.tr("Workers the boost needs arriving by line: {from} now, {to} after the upgrade", {from = needed.now, to = needed.next})
            children[#children + 1] = guiReactUtil.makeHorizontalBox({
                ui.icon(ui.ICONS.workers, tip),
                text(ui.numberText(needed.now) .. " → " .. ui.numberText(needed.next), "font-scale-body", tip, true),
            })
        end
    end
    if s.pending[id] then
        children[#children + 1] = text(ui.tr(s.refused and "Level {level} waits: the game refused to rebuild the industry"
            or "Upgrading to level {level} in a few seconds (not while paused)", {level = s.pending[id]}), "font-scale-body")
    end
    if s.order and s.order.targets[id] then
        children[#children + 1] = text(ui.tr("In progress: level {level}", {level = s.order.targets[id]}), "font-scale-body")
    end
    if s.plan and s.plan.targets[id] then
        children[#children + 1] = text(ui.tr("Planned: level {level}", {level = s.plan.targets[id]}), "font-scale-body")
    end
    children[#children + 1] = ui.upgradeButton(s, id, hint)
    if ui.done(s, id) then
        children[#children + 1] = text("✓ " .. ui.tr("Level {level} active", {level = level}), "font-scale-annotation", nil, true)
    end
    return children
end

-- The upgrades that change anything at this industry, in display order.
function ui.availableUpgrades(s)
    local result = {}
    for _index, upgrade in ipairs(core.UPGRADES) do
        if s.available[upgrade.id] then result[#result + 1] = upgrade.id end
    end
    return result
end

-- Help window -------------------------------------------------------------------------------------
-- The "?" button opens a window that explains the mod: how upgrades are paid in the chosen mode, and
-- what to look out for. A free-floating window in the game's window container (gameCtx.windowContainer),
-- the way the game bar opens its context help (gui/game_bar/game_bar.tl) and the vehicle window the
-- vehicle store. It stays open like the context help until it is closed.
-- One tab per topic (the base game's TabWidget, as in its windows), each with a banner on top in the
-- look of the context help's pictures (800 x 200 TGAs from tools/help_banners.py, no text in them:
-- the help is translated). Widths, wrapping and spacing come from gui/industry_upgrades_help.css.lua
-- and grow with the game's font size like the context help's.

local HELP_CARGO_IMAGES = {plastic = true, bricks = true, cement = true}
local HELP_ICONS = {
    industry = "::/gui/game_bar/icons/building_industry_30.tga",
    rebuild = "::/gui/game_bar/icons/building_industry_gear_30.tga",
    settings = "::/gui/menu/icons/settings.tga",
    info = "::/gui/entity_window/design/symbol_info_outline.tga", -- the base game's info hint
}
local function helpImage(name) return core.MOD_ID .. "::/gui/industry_upgrades/help_" .. name .. ".tga" end
local function cargoName(path) return cargoInfo(path).name end

-- {{id, tab, image, off?, blocks}} for the current game (configured by the industry's settings, see
-- ui.supported). Every page and concept shows in every game, so one can read about all of them; what
-- this game does not use is marked. A page of the other mode gets off (a hint on top, its tab dimmed)
-- and comes after the pages of the game's own mode; a row or hint of something switched off gets
-- off = true (dimmed, "off in this game"). A block is {text = s}, {hint = s, off?} (the info hint) or
-- {rows = {{icon, name?, text, off?}}}.
local SHIPPED_TEXTS = {
    [0] = "At least {value}% of all products together shipped.",
    [1] = "At least {value}% of the best product shipped.",
    [2] = "At least {value}% of the best product shipped; all products together give 1 more.",
}

function ui.helpPages()
    local delivery = core.deliveryMode()
    local costsSetting = {setting = ui.tr("Upgrade costs")}

    local upgrades = {}
    for _index, upgrade in ipairs(core.UPGRADES) do
        upgrades[#upgrades + 1] = {icon = ui.upgradeIcon(upgrade.id), name = ui.upgradeName(upgrade.id), text = ui.upgradeDescription(upgrade.id)}
    end
    local okYear, year = pcall(api.engine.util.getYear)
    local upkeep = {cost = ui.money(core.upkeepStep(0, okYear and year or nil)), general = _("General"), upkeepOther = _("Upkeep Other"),
        setting = ui.tr("Upkeep per level (per month)")}
    local upkeepHint = {hint = ui.tr("Upkeep is off in this game (setting “{setting}”). When it is on, every built level costs upkeep every month, rising with inflation; the finances show it under {general}, {upkeepOther}.", upkeep), off = true}
    if config.UPKEEP_BASE > 0 then
        upkeepHint = {hint = ui.tr(config.UPKEEP_RISING ~= 0
            and "Every built level costs upkeep every month, each level more than the one before: {cost} for a first level now, rising with inflation. The finances show it under {general}, {upkeepOther}."
            or "Every built level costs upkeep every month: {cost} per level now, rising with inflation. The finances show it under {general}, {upkeepOther}.", upkeep)}
    end
    local upgradesPage = {id = "upgrades", tab = ui.tr("Upgrades"), image = helpImage("upgrades"), blocks = {
        {text = ui.tr("Every industry has up to six upgrades. Only those that change anything at this industry show, each with what its next level does. Built levels stay, also when the industry is rebuilt.")},
        {rows = upgrades},
        upkeepHint,
    }}

    -- EXP points: the conditions with this game's thresholds, those switched off marked
    local production = math.floor(config.PRODUCTION_THRESHOLD * 100 + 0.5)
    local shipped = math.floor(config.SHIPPED_THRESHOLD * 100 + 0.5)
    local conditions = {
        {icon = ui.ICONS.production, name = ui.tr("Production rating"), off = production <= 0, text = production > 0
            and ui.tr(config.PRIMARY_PRODUCTION ~= 0 and "At least {value}% over the last year, at every industry."
                or "At least {value}% over the last year, at industries that process inputs.", {value = production})
            or ui.tr("The industry's production rating over the last year.")},
        {icon = ui.ICONS.shipped, name = ui.tr("Shipped share"), off = shipped <= 0, text = shipped > 0
            and ui.tr(SHIPPED_TEXTS[config.SHIPPED_MODE] or SHIPPED_TEXTS[1], {value = shipped})
            or ui.tr("The share of the output that leaves the industry.")},
        {icon = ui.ICONS.workers, name = ui.tr("Worker boost"), off = config.WORKERS_CONDITION == 0,
            text = ui.tr("Active while enough workers arrive by line.")},
        {icon = ui.ICONS.booster, name = ui.tr("Booster"), off = config.BOOSTER_CONDITION == 0,
            text = ui.tr("A booster such as fertilizer, tools or machines active, at industries with boosters.")},
    }
    local expPage = {id = "exp", tab = ui.tr("EXP points"), image = helpImage("exp"),
        off = delivery and ui.tr("Not used in this game: upgrades cost deliveries (setting “{setting}”).", costsSetting) or nil, blocks = {
        {text = ui.tr(config.EXP_ALL_CONDITIONS ~= 0
            and "Once a month the industry gets 1 EXP if it meets all conditions that are on. {exp} EXP make 1 upgrade point. The card at the top shows last month's conditions."
            or "Once a month the industry gets 1 EXP for every condition it meets. {exp} EXP make 1 upgrade point. The card at the top shows last month's conditions.",
            {exp = config.EXP_PER_POINT})},
        {rows = conditions},
        {text = ui.tr("Spend points on the upgrade cards. Levels bought one after another are built together a few seconds later.")},
        {hint = ui.tr("If the game refuses to rebuild an industry, its upgrades say so and can return the points of the waiting levels.")},
    }}

    -- deliveries
    local deliveryOff = (not delivery) and ui.tr("Not used in this game: upgrades cost EXP points (setting “{setting}”).", costsSetting) or nil
    local deliverPage = {id = "deliver", tab = ui.tr("Delivery"), image = helpImage("deliver"), off = deliveryOff, blocks = {{rows = {
        {icon = ui.ICONS.upgrade, text = ui.tr("Plan levels on the upgrade cards, then press “{start}”.", {start = ui.tr("Start upgrade")})},
        {icon = ui.ICONS.shipped, text = ui.tr("The industry gets an input stock for each cargo the plan needs: bring it with your lines like any other cargo.")},
        -- complete once all cargo is used (counted on consumption, not on arrival): a booster rule only
        -- runs while the industry produces, a plain rule also waits for the minimum duration
        {icon = HELP_ICONS.industry, text = core.plainOrderRule()
            and ui.tr("The industry uses the cargo bit by bit. Once all of it is used and the minimum duration is over, all planned levels are built at once.")
            or ui.tr("While the industry produces, it uses the cargo bit by bit. Once all of it is used, all planned levels are built at once.")},
    }}}}
    local material = core.cargoShortName(core.material().cargo)
    local cargoPage = {id = "cargo", tab = ui.tr("Which cargo"), image = HELP_CARGO_IMAGES[material] and helpImage("cargo_" .. material) or nil,
        off = deliveryOff, blocks = {
        {text = ui.tr("Higher levels ask for more advanced cargo: first {planks}, then also {material}, then also {tools}. Later {steel} comes instead of {planks}, and for the last levels {glass} and {machines} instead of {material} and {tools}. Cargo the industry uses or makes itself is replaced by another one.", {
            planks = cargoName("::/cargos/planks/planks.cargo"), material = cargoName(core.material().cargo),
            tools = cargoName("::/cargos/tools/tools.cargo"), steel = cargoName("::/cargos/steel/steel.cargo"),
            glass = cargoName("::/cargos/glass/glass.cargo"), machines = cargoName("::/cargos/machines/machines.cargo")})},
        {hint = ui.tr("If no industry on the map makes a cargo yet, the plan says so.")},
    }}
    local tips = {}
    tips[#tips + 1] = {icon = ui.ICONS.months, text = ui.tr("An upgrade takes at least {months} months; every further level in the same delivery adds only half of that, so plan several levels together.",
        {months = math.floor(config.RESOURCE_YEARS * 12 + 0.5)})}
    if config.ORDER_MALUS > 0 then
        tips[#tips + 1] = {icon = ui.ICONS.production, text = ui.tr("The industry produces {malus}% less until the upgrade is complete.", {malus = math.floor(config.ORDER_MALUS * 100 + 0.5)})}
    else
        tips[#tips + 1] = {icon = ui.ICONS.production, text = ui.tr("The industry can produce less until the upgrade is complete."), off = true}
    end
    if not core.plainOrderRule() then
        tips[#tips + 1] = {icon = ui.ICONS.booster, text = ui.tr("The delivered cargo is only used while the industry produces: an industry without its own supplies pauses its upgrade.")}
    end
    tips[#tips + 1] = {icon = ui.ICONS.cancel, text = ui.tr("Cancelling an upgrade loses the cargo delivered so far.")}
    tips[#tips + 1] = {icon = HELP_ICONS.rebuild, text = ui.tr("Starting and finishing an upgrade rebuild the industry. Its production rating starts again, so it grows more slowly for a while.")}
    local tipsPage = {id = "tips", tab = ui.tr("Tips"), image = helpImage("notes"), off = deliveryOff, blocks = {{rows = tips}}}

    if delivery then return {upgradesPage, deliverPage, cargoPage, tipsPage, expPage} end
    return {upgradesPage, expPage, deliverPage, cargoPage, tipsPage}
end

local function helpText(value, class)
    return builtin.TextView{meta = {class = "font-scale-body, " .. class}, text = value}
end

local function helpImageView(path, class)
    return builtin.ImageView{meta = {class = class}, path = path, scaling = builtin.type.ImageViewScaling.AutoFit}
end

-- A row of something this game switched off is dimmed like the base game's disabled items and says so.
local OFF = ", industry-upgrades-help-off"

local function helpRow(row)
    local off = row.off and OFF or ""
    local lines = {}
    if row.name then
        local name = row.off and ui.tr("{name} · off in this game", {name = row.name}) or row.name
        lines[#lines + 1] = helpText(name, "industry-upgrades-help-row-name" .. off)
    end
    lines[#lines + 1] = helpText(row.text, "industry-upgrades-help-row-text" .. off)
    if row.off and not row.name then lines[#lines + 1] = helpText(ui.tr("Off in this game."), "industry-upgrades-help-row-text" .. off) end
    return builtin.Component{meta = {class = "industry-upgrades-help-row"}, layout = builtin.BoxLayout{
        orientation = builtin.type.Orientation.Horizontal,
        children = {helpImageView(row.icon, "industry-upgrades-help-row-icon" .. off), builtin.Component{layout = ui.vertical(lines)}},
    }}
end

local function helpBlock(block)
    if block.hint then
        return builtin.Component{meta = {class = "industry-upgrades-help-hint"}, layout = builtin.BoxLayout{
            orientation = builtin.type.Orientation.Horizontal,
            children = {helpImageView(HELP_ICONS.info, "industry-upgrades-help-hint-icon"),
                helpText(block.hint, "industry-upgrades-help-hint-text" .. (block.off and OFF or ""))},
        }}
    end
    if block.rows then
        local rows = {}
        for _index, row in ipairs(block.rows) do rows[#rows + 1] = helpRow(row) end
        return builtin.Component{layout = ui.vertical(rows)}
    end
    return helpText(block.text, "industry-upgrades-help-text")
end

local function helpPage(page)
    local children = {}
    if page.image then
        children[#children + 1] = builtin.ImageView{meta = {class = "industry-upgrades-help-banner"}, path = page.image,
            scaling = builtin.type.ImageViewScaling.AutoZoom}
    end
    -- a page of the mode this game does not use says so on top
    if page.off then children[#children + 1] = helpBlock({hint = page.off}) end
    for _index, block in ipairs(page.blocks) do children[#children + 1] = helpBlock(block) end
    return builtin.Component{meta = {class = "industry-upgrades-help-page"}, layout = ui.vertical(children)}
end

ui.HelpWindow = react.RegisterWrapperRecipe("IndustryUpgradesHelpWindow", builtin.Window, function(params)
    local pages = ui.helpPages()
    local tabs = {}
    for _index, page in ipairs(pages) do
        tabs[#tabs + 1] = builtin.TabWidgetChild{
            localKey = "industryUpgradesHelp_" .. page.id,
            value = page.id,
            indicator = builtin.TextView{meta = {class = "font-scale-tab-widget-indicator" .. (page.off and OFF or "")}, text = page.tab},
            item = helpPage(page),
        }
    end
    return builtin.Window{
        meta = {class = "industry-upgrades-help"},
        id = "industryUpgrades.help.window",
        title = ui.tr("How Industry Upgrades works"),
        closable = true,
        movable = true,
        initialX = 0.5,
        initialY = 0.5,
        onClose = params.onClose,
        content = builtin.BoxLayout{orientation = builtin.type.Orientation.Vertical, children = {
            builtin.TabWidget{
                orientation = builtin.type.TabOrientation.North,
                deselectAllowed = false,
                initialValue = pages[1].id,
                tabs = tabs,
            },
            builtin.Component{meta = {class = "industry-upgrades-help-footer"}, layout = builtin.BoxLayout{
                orientation = builtin.type.Orientation.Horizontal,
                children = {
                    helpImageView(HELP_ICONS.settings, "industry-upgrades-help-footer-icon"),
                    helpText(ui.tr("Costs, amounts, durations and the effect of most upgrades are set in the mod settings when a game is started or loaded."), "industry-upgrades-help-footer-text"),
                },
            }},
        }},
    }
end)

-- Opens the help window (once; a second click brings it to the front). Nothing happens without the
-- game's window container.
function ui.openHelp(gameCtx)
    local ok, windows = pcall(function() return gameCtx.windowContainer:get():getApi() end)
    if not ok or not windows then return end
    windows.addSingletonWindow(ui.HelpWindow, {onClose = function() windows.removeAllWindows(ui.HelpWindow) end})
    windows.moveSingletonWindowToFront(ui.HelpWindow)
end

-- The "?" button laid over the end of a card's heading line, so it needs no row of its own: the first
-- card of the Upgrades tab, the compact card in the Industry tab. A ContentCard's title takes text
-- only, hence the overlay.
function ui.withHelp(node, gameCtx)
    return builtin.Component{meta = {class = "industry-upgrades-with-help"}, layout = builtin.FloatingLayout{children = {
        builtin.FloatingLayoutChild{h = -1, v = -1, item = node},
        builtin.FloatingLayoutChild{h = 1, v = 0, item = builtin.Button{
            meta = {class = "industry-upgrades-help-button", forceFocusable = true, tooltip = ui.tr("How Industry Upgrades works")},
            content = ui.icon(ui.ICONS.help),
            onClick = function() ui.openHelp(gameCtx) end,
        }},
    }}}
end

return ui
