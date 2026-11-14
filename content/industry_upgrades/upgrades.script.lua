-- Awards EXP once per game month (EXP_PER_POINT EXP = 1 upgrade point), handles purchases, plans and
-- delivery orders from the industry window and rebuilds industries with their new level.
--
-- State: version, records[constructionId] = {points, exp, targets?, lastPurchase?, last?, plan?, order?,
-- closed?, ratingReset?},
-- queue? = {{construction}} industries waiting for their rebuild. targets: the bought level per
-- upgrade. A rebuild waits until no purchase came for core.BUNDLE_WAIT, then builds all bought levels
-- at once. The levels live in the construction parameters, so they survive rebuilds even if the
-- construction entity changes; the remaining points and EXP are carried over through the parameters
-- as well.
--
-- Delivery mode (setting "Upgrade costs"): every upgrade costs a delivery instead of points. Levels
-- are planned first (plan = {id -> level}); starting the plan opens one order for all of them,
-- order = {from = {id -> level}, targets = {id -> level}, cargo = {{cargo, amount, delivered}},
-- ratingBefore, years, malus (the settings it is built with), at (game time it was opened), steps (its
-- most cycles, core.orderSteps), built, refit?}. The next rebuild adds the order's stocks and rule (core.addOrder), the base game's
-- consumption event counts what the rule consumes, and once everything has arrived and the minimum
-- duration is over the levels become targets like bought ones: their rebuild builds them and drops
-- the order's stocks.
local core = require "stardorn_industry_upgrades::/industry_upgrades/core.lua"
local config = require "stardorn_industry_upgrades::/industry_upgrades/config.lua"
local productivity = ug_require "::/industries/industry_productivity_util.tl"

local LOG_PREFIX = core.LOG_PREFIX
-- The script only works every few simulation ticks: reading the saved state costs simulation
-- time, and one rebuild every few ticks keeps the game smooth.
local WORK_INTERVAL_TICKS = 5
local errorLogged, upkeepErrorLogged = false, false
-- Constructions whose open order checkOrders found built in the current shape this session. Their
-- parameters are not read again until a new order; the monthly check still catches anything else.
local current = {}

-- Counting the consumption runs in handleEvent. The event covers every industry that consumes
-- anything, so it may come on every simulation step, and handleEvent need not share this file's
-- locals with update. It keeps its own list of watched stock lists and its own counts, and syncs both
-- with the saved state at most every SYNC_INTERVAL of game time, and right away once an order has
-- everything.
local SYNC_INTERVAL = 2000 -- ms game time
-- stock list entity -> {key = construction key, cargo = {cargo type id -> index in order.cargo},
-- missing = {index -> amount still missing at the last sync}}
local watch = {}
local unsaved = {}    -- construction key -> {index in order.cargo -> count}
local syncedAt = nil  -- game time of the last sync; nil: sync at the next event
local countErrorLogged = false

local function copyParams(construction)
    local source = construction.params_native and construction.params_native:asTable() or construction.params or {}
    local params = {}
    for key, value in pairs(source) do params[key] = value end
    return params
end

-- Whether this Lua state has applied the game's settings, and fitted the open orders to them
-- (fitOrders). The settings only change when a savegame is loaded, which starts every Lua state afresh.
local configured, fitted = false, false

-- Only industries whose construction script we wrapped can be upgraded (and not those of another copy
-- of the mod, should one run as well). The wrapper also carries the mod settings, which are applied
-- here for everything that follows.
local function supported(construction)
    local resId = api.res.constructionRep.find(construction.fileName)
    if resId < 0 then return false end
    local own = core.ownEntry(api.res.constructionRep.get(resId))
    if own == nil then return false end
    local okSettings, settings = pcall(function() return own.settings end)
    core.configure(okSettings and settings or nil)
    configured = true
    return true
end

-- After a load, update may build a queued rebuild or check an order before the monthly check or an
-- event from the window has applied the settings, and with the default maximum levels core.level
-- would cut the built levels. So update applies them first, from the first construction of the queue
-- or the records that still exists. Records only come from our industries; while that one is not ours
-- (another copy of the mod wraps the industries) the settings stay unknown.
local function applySettings(root)
    if configured then return end
    local function tried(id)
        local construction = id and api.engine.entityExists(id) and api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
        if construction then supported(construction) end
        return construction
    end
    for _index, job in ipairs(root.queue or {}) do
        if tried(tonumber(job.construction)) then return end
    end
    for key in pairs(root.records) do
        if tried(tonumber(key)) then return end
    end
end

local function workersBoosted(stockList)
    local ok, productivity = pcall(function() return stockList.modifiers.productivity end)
    return ok and (tonumber(productivity) or 0) > 1.0
end

-- Primary industries (no production inputs) always run at full production, so the production
-- condition only counts for industries that process inputs. Unreadable rules keep the condition.
local function processesInputs(stockList)
    local ok, result = pcall(function() return core.processesInputs(stockList.rules) end)
    return not ok or result
end

-- The shipped share of the product shipped best (shipped / produced per year of each product) and
-- that product's cargo type. nil when unreadable or nothing was produced.
local function bestShipped(industry, stockList)
    local ok, share, cargo = pcall(function()
        local best, bestCargo = nil, nil
        for cargoType in pairs(core.outputCargo(stockList and stockList.rules)) do
            local produced = tonumber(api.engine.util.stock.getCargoProducedPerYear(industry.stockList, cargoType)) or 0
            if produced > 0 then
                local share = math.min(1, (tonumber(api.engine.util.stock.getCargoTypeShippedPerYear(industry.stockList, cargoType)) or 0) / produced)
                -- the lower cargo id on a tie, so the product shown does not change from month to month
                if not best or share > best or (share == best and cargoType < bestCargo) then best, bestCargo = share, cargoType end
            end
        end
        return best, bestCargo
    end)
    if not ok then return nil end
    return share, cargo
end

-- nil for industries without booster rules, otherwise whether a booster is active right now: the
-- engine's own flag, which the base game also uses for the emissions. A delivery order's booster sets
-- that flag as well, so while an order is open the industry's own booster rules are asked instead.
local function boosterActive(entity, stockList)
    local ok, hasBooster, hasOrder = pcall(function()
        local real, order = false, false
        for _index, rule in ipairs(stockList.rules) do
            if core.isRealBooster(rule) then
                real = true
            elseif rule.booster and core.isOrderRule(rule) then
                order = true
            end
        end
        return real, order
    end)
    if not ok or not hasBooster then return nil end
    if hasOrder then
        local okRunning, running = pcall(function()
            local now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
            return core.realBoosterRunning(stockList.rules, stockList.ruleDatas, now)
        end)
        if okRunning then return running end
    end
    local okInfo, info = pcall(api.engine.util.industry.getIndustryProductivityInfo, entity)
    return okInfo and info ~= nil and info.boostFromRule == true
end

local function orderTargets(record)
    return record and record.order and record.order.targets or nil
end

-- Whether the construction's order stocks match the record's open order (none on both sides counts).
local function orderBuilt(params, record)
    return core.sameTargets(core.orderTargets(params), orderTargets(record)) and not core.orderOutdated(params)
end

-- The industry subconstruction of a construction: its entity and INDUSTRY component.
local function industryOf(construction)
    for _index, sub in ipairs(construction.subconstructions or {}) do
        if api.engine.entityExists(sub) then
            local industry = api.engine.getComponent(sub, api.type.ComponentType.INDUSTRY)
            if industry then return sub, industry end
        end
    end
    return nil
end

-- Whether the industry's workplaces differ from what "Workers needed per level" builds now
-- (core.workplacesOutdated), by what its last build recorded. Constructions built before that (revision
-- 7) are compared by their workplaces against the base game's: the construction's industrialCapacity,
-- else the one its resource hands the original script (stockListConfig, kept at the top level of our
-- updateScript params).
local function workplacesOutdated(construction, params)
    local ok, outdated = pcall(function()
        local level = core.level(params, "workers")
        if level == 0 then return false end
        local metadata = construction.persistentMetadata
        local built = metadata and tonumber(metadata[core.WORKPLACES_META])
        local base = metadata and tonumber(metadata[core.WORKPLACES_BASE_META])
        if not built or not base then
            local entity = industryOf(construction)
            local persons = entity and api.engine.getComponent(entity, api.type.ComponentType.PERSON_CAPACITY)
            built = persons and tonumber(persons.capacity)
            base = tonumber(params.industrialCapacity)
            if not base then
                local resource = api.res.constructionRep.get(api.res.constructionRep.find(construction.fileName))
                local stockListConfig = resource.updateScript.params.stockListConfig
                base = stockListConfig and tonumber(stockListConfig.industrialCapacity)
            end
        end
        return core.workplacesOutdated(level, built, base)
    end)
    return ok and outdated
end

-- Builds every bought level of the industry at once, and adds or drops the stocks of a delivery
-- order. Commands sent from a game script update must not take a callback ("Callbacks are currently
-- disallowed"), just like the base game's own industry expansion. A failed rebuild keeps the targets
-- above the built levels (and the order apart from the built one), so the next monthly check queues
-- it again. force: rebuild even if nothing seems to be missing (an order fitted to a lower maximum).
-- Workplaces that differ from what "Workers needed per level" builds now are rebuilt as well.
local function rebuild(job, record, now, force)
    if not api.engine.entityExists(job.construction) then return end -- bulldozed since the purchase
    local construction = api.engine.getComponent(job.construction, api.type.ComponentType.CONSTRUCTION)
    if not construction then return end
    local params = copyParams(construction)
    local pending = core.pendingTargets(record, params)
    if not force and not pending and orderBuilt(params, record) and not workplacesOutdated(construction, params) then return end
    for id, level in pairs(pending or {}) do core.setLevel(params, id, level) end
    core.setOrderTargets(params, orderTargets(record))
    params[core.ORDER_FORMAT_PARAM] = core.ORDER_FORMAT
    params[core.CARRY_POINTS_PARAM] = record and record.points or 0
    params[core.CARRY_EXP_PARAM] = record and record.exp or 0
    params[core.CARRY_TIME_PARAM] = now
    local proposal = api.engine.util.proposal.createProposalReplaceConstruction(job.construction, params)
    if not proposal then
        log.warning(LOG_PREFIX .. "no rebuild proposal for construction " .. tostring(job.construction))
        return
    end
    -- ignoreErrors = false: a rebuild that would collide with anything is skipped, never forced.
    api.cmd.sendCommand(api.cmd.makeWorldBuildProposalCmd(proposal, nil, false, false, false))
end

local function newRecord(params, now, month)
    local record = {points = 0, exp = 0}
    local carryTime = tonumber(params[core.CARRY_TIME_PARAM])
    if carryTime and carryTime <= now and now - carryTime <= 2 * month then
        record.points = tonumber(params[core.CARRY_POINTS_PARAM]) or 0
        record.exp = tonumber(params[core.CARRY_EXP_PARAM]) or 0
    end
    return record
end

-- After a worker boost upgrade the base game keeps the old boost until the boost state changes;
-- bring a boosted industry to its new factor right away.
local function syncWorkerBoost(entity, params)
    if core.level(params, "workers") == 0 then return end
    local stockList = api.engine.getComponent(entity, api.type.ComponentType.STOCK_LIST)
    local current = stockList and stockList.modifiers and tonumber(stockList.modifiers.productivity) or 1
    if current <= 1.0 then return end
    local expected = productivity.getPersonCapacityPotentialBoost(entity)
    if not expected or math.abs(current - expected) < 0.001 then return end
    local modifiers = api.type.StockList.Modifiers.new()
    modifiers.productivity = expected
    api.cmd.sendCommand(api.cmd.makeStockListSetModifiersCmd(entity, modifiers))
end

local function ensureRecord(root, key, params, now, month)
    local record = root.records[key]
    if not record then
        record = newRecord(params, now, month)
        root.records[key] = record
    end
    return record
end

-- One rebuild per industry: it builds every bought level at once. True when newly queued.
local function enqueue(root, construction)
    root.queue = root.queue or {}
    for _index, job in ipairs(root.queue) do
        if job.construction == construction then return false end
    end
    root.queue[#root.queue + 1] = {construction = construction}
    return true
end

-- The saved state, converted to the current version (purchases may arrive before the first update).
local function loadRoot(state)
    local root = state:get() or {}
    root.records = root.records or {}
    local version = root.version or 1
    root.version = core.STATE_VERSION
    if version >= core.STATE_VERSION or (next(root.records) == nil and root.queue == nil) then return root, false end
    for _key, record in pairs(root.records) do
        if version < 2 then core.migrateRecord(record) end
        core.migrateTargets(record)
    end
    -- version 2 kept the queue with a progress index; the waiting jobs only need their construction
    if root.queue then
        local waiting = {}
        for index = root.queueIndex or 1, #root.queue do
            local construction = root.queue[index].construction
            if construction then waiting[#waiting + 1] = {construction = construction} end
        end
        root.queue = #waiting > 0 and waiting or nil
        root.queueIndex = nil
    end
    if version < 2 then log.message(LOG_PREFIX .. "converted points of the old system into EXP") end
    return root, true
end

local function stockListOf(entity, industry)
    return api.engine.getComponent(entity, api.type.ComponentType.STOCK_LIST)
        or api.engine.getComponent(industry.stockList, api.type.ComponentType.STOCK_LIST)
end

local cargoShortName = core.cargoShortName

local function cargoId(cargo)
    local ok, id = pcall(api.res.cargoTypeRep.find, cargo)
    return ok and tonumber(id) or -1
end

-- The production rating of an industry, nil when unreadable.
local function ratingOf(industry)
    local ok, rating = pcall(api.engine.util.stock.getProductionRating, industry.stockList)
    return ok and rating or nil
end

-- The rating counted for a record's industry right now, with a recent reset made up for (see
-- core.countedRating). nil when unreadable.
local function countedRating(record, industry, now)
    local live = industry and ratingOf(industry)
    if live == nil then return nil end
    return core.countedRating(live, record.ratingReset, now, api.util.getDefaultYearDuration())
end

-- Right after a rebuild that added or dropped an order's stocks: a rating near 0 means the engine
-- started it again, so the counted rating makes up for it for a year (record.ratingReset).
local function noteReset(record, industry, before, now)
    local live = industry and ratingOf(industry)
    if live ~= nil and live < core.RATING_RESET and tonumber(before) then
        record.ratingReset = {before = tonumber(before), at = now}
    end
end

-- Diagnostics of an order, right after the order's stocks were built (force) and then in the monthly
-- check whenever it moved on: what the engine made of the extra stocks and rules, what they hold and
-- are expected to consume, and the production rating (the engine's and the counted one) next to the
-- one before the order. order.logged keeps what the last line showed of the order's progress (cargo
-- used and in stock, cycles left), so an order that waits for its cargo is logged once, not every
-- month (about 800 characters a line); the yearly figures and the rating move every month and do not
-- count.
-- "390", "33.33": an order's cycles per year (a plain rule's rate is any fraction).
local function rateText(rate)
    if rate == math.floor(rate) then return string.format("%d", rate) end
    return string.format("%.2f", rate)
end

local function logOrder(key, record, entity, industry, params, now, force)
    local ok, err = pcall(function()
        local order = record.order
        local stockList = stockListOf(entity, industry)
        local stocks = stockList and stockList.stocks or {}
        local progress = core.orderProgress(order, now, api.util.getDefaultYearDuration())
        local parts, seen = {}, {}
        for index, need in ipairs(order.cargo or {}) do
            local id = cargoId(need.cargo)
            local position
            for stockIndex, stock in ipairs(stocks) do
                if stock.cargoType == id then position = stockIndex end
            end
            local stored = position and api.engine.system.simEntityAtStockSystem.getStockCountForCargoType(entity, position - 1, id) or "-"
            seen[#seen + 1] = math.floor(tonumber(need.delivered) or 0) .. ":" .. tostring(stored)
            parts[#parts + 1] = string.format("%s %d/%d (lot %s, stock %s holds %s, delivered %s/year, max consumption %s/year)",
                cargoShortName(need.cargo), math.floor(tonumber(need.delivered) or 0), math.floor(tonumber(need.amount) or 0),
                tostring(progress.lots[index]), tostring(position), tostring(stored),
                tostring(api.engine.util.stock.getCargoTypeDeliveredPerYear(industry.stockList, id)),
                tostring(api.engine.util.stock.getCargoMaxConsumptionPerYear(industry.stockList, id)))
        end
        local signature = table.concat(seen, ",") .. "|" .. tostring(progress.left) .. "|" .. tostring(order.built)
        if not force and order.logged == signature then return end
        order.logged = signature
        log.message(string.format("%sconstruction %s order %s (%d levels): %s; %d of %d cycles left at %s per year; %d stocks, %d rules, order stocks built: %s, production rating %s (counted %s, before the order %s)",
            LOG_PREFIX, key, core.orderText(order), core.orderLevelCount(order), table.concat(parts, "; "),
            progress.left, progress.cycles, rateText(progress.rate), #stocks, stockList and #stockList.rules or 0,
            tostring(core.sameTargets(core.orderTargets(params), order.targets)),
            tostring(ratingOf(industry)), tostring(countedRating(record, industry, now)), tostring(order.ratingBefore)))
    end)
    if not ok then log.warning(LOG_PREFIX .. "order diagnostics for construction " .. key .. " failed: " .. tostring(err)) end
end

-- The construction of an order (by record key) with its industry subconstruction, nil when gone.
local function orderIndustry(key)
    local id = tonumber(key)
    local construction = id and api.engine.entityExists(id) and api.engine.getComponent(id, api.type.ComponentType.CONSTRUCTION)
    if not construction then return nil end
    local entity, industry = industryOf(construction)
    if not entity then return nil end
    return construction, entity, industry
end

-- A closed order (complete or cancelled) is noted in record.closed = {text, how, rating} with the
-- counted rating before its rebuild. Once the rebuild has dropped the order's stocks, the reset is
-- noted (noteReset) and the stock list and ratings are logged.
local function closeOrder(record, order, how, industry, now)
    record.closed = {text = core.orderText(order), how = how, rating = countedRating(record, industry, now)}
end

-- "throughput 2, storage 1": the built levels.
local function levelsText(params)
    local parts = {}
    for _index, upgrade in ipairs(core.UPGRADES) do
        local level = core.level(params, upgrade.id)
        if level > 0 then parts[#parts + 1] = upgrade.id .. " " .. level end
    end
    return #parts > 0 and table.concat(parts, ", ") or "no levels"
end

local function logClosed(key, record, entity, industry, params, now)
    local ok, err = pcall(function()
        local closed = record.closed
        local stockList = stockListOf(entity, industry)
        local what = tostring(closed.text)
        log.message(string.format("%sconstruction %s rebuilt after the delivery for %s was %s: %s, %d stocks, %d rules, production rating %s (counted %s, before the rebuild %s)",
            LOG_PREFIX, key, what, tostring(closed.how), levelsText(params),
            stockList and #stockList.stocks or 0, stockList and #stockList.rules or 0, tostring(ratingOf(industry)),
            tostring(countedRating(record, industry, now)), tostring(closed.rating)))
    end)
    if not ok then log.warning(LOG_PREFIX .. "diagnostics after the order for construction " .. key .. " failed: " .. tostring(err)) end
end

-- Stores the consumption counted since the last sync. True when anything changed.
local function storeCounts(root)
    local changed = false
    for key, counts in pairs(unsaved) do
        local order = root.records[key] and root.records[key].order
        for index, count in pairs(counts) do
            local need = order and order.cargo and order.cargo[index]
            if need then
                need.delivered = (tonumber(need.delivered) or 0) + count
                changed = true
            end
        end
    end
    unsaved = {}
    return changed
end

-- "planks 120/300, plastic 0/200"
local function deliveredText(order)
    local parts = {}
    for _index, need in ipairs(order.cargo or {}) do
        parts[#parts + 1] = cargoShortName(need.cargo) .. " " .. tostring(need.delivered) .. "/" .. tostring(need.amount)
    end
    return table.concat(parts, ", ")
end

-- Orders with everything delivered and their minimum duration over (core.orderTimeOver; year = game
-- time of a year): their levels become targets like bought ones; the rebuild that builds them drops the
-- order's stocks. True when anything changed.
local function completeOrders(root, now, year)
    local changed = false
    for key, record in pairs(root.records) do
        local order = record.order
        local ready = order and core.orderComplete(order) and core.orderTimeOver(order, now, year)
        if ready and not order.lastLot then
            -- the last lot is counted when its cycle starts: the levels come once that cycle has run
            order.lastLot = now
            changed = true
            log.message(LOG_PREFIX .. "construction " .. key .. " delivery for " .. core.orderText(order)
                .. " has all its cargo (" .. deliveredText(order) .. "), complete after the last cycle")
        elseif order and order.lastLot and not ready then
            order.lastLot = nil -- fitted to larger amounts on loading
            changed = true
        end
        if ready and core.orderLastCycleOver(order, now, year) then
            record.targets = record.targets or {}
            for id, level in pairs(order.targets or {}) do
                record.targets[id] = math.max(tonumber(record.targets[id]) or 0, tonumber(level) or 0)
            end
            record.order = nil
            local _construction, _entity, industry = orderIndustry(key)
            closeOrder(record, order, "complete", industry, now)
            enqueue(root, tonumber(key))
            log.message(LOG_PREFIX .. "construction " .. key .. " delivery for " .. core.orderText(order)
                .. " complete (" .. deliveredText(order) .. "), rebuild queued")
            changed = true
        end
    end
    return changed
end

-- Once an order's stocks have been built and once a closed order's stocks are gone: notes a reset of
-- the production rating (noteReset) and logs (logOrder, logClosed). Queues a rebuild for orders built
-- in an older shape (see core.ORDER_FORMAT), which may crash the industry window. True when anything
-- changed.
local function checkOrders(root, now)
    local changed = false
    for key, record in pairs(root.records) do
        if not record.order and record.closed then
            local construction, entity, industry = orderIndustry(key)
            local params = construction and copyParams(construction)
            if not params or not core.hasOrderStocks(params) then
                if params then
                    noteReset(record, industry, record.closed.rating, now)
                    logClosed(key, record, entity, industry, params, now)
                end
                record.closed = nil
                changed = true
            end
        end
        if record.order and not (record.order.built and current[key]) then
            local construction, entity, industry = orderIndustry(key)
            local params = construction and copyParams(construction)
            if params and core.orderOutdated(params) then
                if enqueue(root, tonumber(key)) then
                    record.order.built = nil
                    changed = true
                    log.message(LOG_PREFIX .. "construction " .. key .. " has the order's stocks in an older shape, rebuild queued")
                end
            elseif params and not record.order.built and not record.order.refit
                and core.sameTargets(core.orderTargets(params), record.order.targets) then
                record.order.built = true
                changed = true
                noteReset(record, industry, record.order.ratingBefore, now)
                logOrder(key, record, entity, industry, params, now, true)
            end
            if params and record.order.built and not core.orderOutdated(params) then current[key] = true end
        end
    end
    return changed
end

-- The stock lists of the open orders, see `watch`.
local function buildWatch(root)
    local result = {}
    for key, record in pairs(root.records) do
        local construction, entity, industry
        if record.order then construction, entity, industry = orderIndustry(key) end
        if construction then
            local entry = {key = key, cargo = {}, missing = {}}
            for index, need in ipairs(record.order.cargo or {}) do
                local id = cargoId(need.cargo)
                if id >= 0 then entry.cargo[id] = index end
                entry.missing[index] = (tonumber(need.amount) or 0) - (tonumber(need.delivered) or 0)
            end
            result[entity] = entry
            if industry.stockList then result[industry.stockList] = entry end
        end
    end
    return result
end

local function syncCounts(state, now)
    local root, changed = loadRoot(state)
    if storeCounts(root) then changed = true end
    if changed then state:set(root) end
    watch = buildWatch(root)
    syncedAt = now
end

-- Whether the counts since the last sync complete the watched order.
local function countsComplete(watched)
    local counts = unsaved[watched.key] or {}
    for index, missing in pairs(watched.missing) do
        if (counts[index] or 0) < missing then return false end
    end
    return true
end

-- handleEvent for StockListSystem/ItemsAboutToBeConsumed: param.items = {{stock list, {cargo items}}}.
-- Counts the order's cargo at the watched stock lists. Order cargo never shares a stock list with
-- production (core.orderRequirements), so whatever of it is consumed there went through the order.
local function countConsumed(state, param)
    local now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
    if syncedAt == nil or now < syncedAt or now - syncedAt >= SYNC_INTERVAL then syncCounts(state, now) end
    if next(watch) == nil then return end
    local complete = false
    local ok, err = pcall(function()
        for _index, entry in ipairs(param.items) do
            local watched = watch[entry[1]]
            if watched then
                local counted = false
                for _item, simEntity in ipairs(entry[2]) do
                    local cargo = api.engine.getComponent(simEntity, api.type.ComponentType.SIM_CARGO)
                    local index = cargo and watched.cargo[cargo.cargoType]
                    if index then
                        local counts = unsaved[watched.key] or {}
                        unsaved[watched.key] = counts
                        counts[index] = (counts[index] or 0) + 1
                        counted = true
                    end
                end
                if counted and countsComplete(watched) then complete = true end
            end
        end
    end)
    if not ok and not countErrorLogged then
        countErrorLogged = true
        log.error(LOG_PREFIX .. "counting the consumption event failed: " .. tostring(err))
    end
    -- the order is done: store now, the game script's update builds the level
    if complete then syncCounts(state, now) end
end

-- The calendar year of a game time (for the upkeep's inflation); nil if the engine cannot tell.
local function yearOf(now)
    local ok, date = pcall(api.engine.util.getCalendarDate, now)
    return ok and date and tonumber(date.year) or nil
end

-- Charges the month's upkeep of all upgraded industries on the player's account, the way the base game
-- books its marketing campaign: a journal entry, shown in the finances under General, Upkeep Other
-- (verified with stardorn_upkeep_probe on 2026-10-14). Without a callback: a game script may not pass
-- one to sendCommand.
local function chargeUpkeep(amount)
    local entry = api.type.JournalEntry.new()
    entry.amount = -amount
    entry.time = -1
    entry.category.type = api.type.JournalEntry.Type.MAINTENANCE
    entry.category.maintenance = api.type.JournalEntry.Maintenance.OTHER
    api.cmd.sendCommand(api.cmd.makeJournalBookAssetCmd(api.engine.util.getPlayer(), entry, api.type.Vec3f.new(0, 0, 0)))
end

local function monthlyPass(root, now, month)
    local seen, queue, visited = {}, {}, {}
    local stats = {industries = 0, unsupported = 0, exp = 0, points = 0, production = 0, shipped = 0, shippedBest = 0, workers = 0, booster = 0,
        upkeep = 0}
    local year
    api.engine.forEachEntityWithComponent(function(entity)
        local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
        if not industry or visited[industry.construction] then return end
        visited[industry.construction] = true
        stats.industries = stats.industries + 1
        local construction = api.engine.getComponent(industry.construction, api.type.ComponentType.CONSTRUCTION)
        if not construction or not supported(construction) then
            stats.unsupported = stats.unsupported + 1
            return
        end

        local key = tostring(industry.construction)
        seen[key] = true
        local params = copyParams(construction)
        local record = ensureRecord(root, key, params, now, month)
        pcall(syncWorkerBoost, entity, params)

        if record.ratingReset and core.resetOver(record.ratingReset, now, 12 * month) then record.ratingReset = nil end
        -- EXP only while upgrades cost points: the points and EXP of an earlier EXP phase stay as they are
        -- while upgrades cost deliveries, and come back with a switch to EXP points (setting "Upgrade
        -- costs", changeable when a savegame is loaded). last is cleared so the conditions shown after a
        -- switch back are never stale.
        if core.deliveryMode() then
            record.last = nil
        elseif (industry.closureTimeStamp or 0) <= 0 then
            local stockList = stockListOf(entity, industry)
            local bestShare, bestCargo = bestShipped(industry, stockList)
            local exp, detail = core.monthlyExp(
                (config.PRIMARY_PRODUCTION ~= 0 or processesInputs(stockList))
                    and core.countedRating(api.engine.util.stock.getProductionRating(industry.stockList), record.ratingReset, now, 12 * month) or nil,
                api.engine.util.stock.getCargoShippedPerYear(industry.stockList),
                api.engine.util.stock.getCargoOutputPerYear(industry.stockList),
                workersBoosted(stockList),
                boosterActive(entity, stockList),
                bestShare, bestCargo)
            detail.exp = exp
            record.last = detail
            stats.points = stats.points + core.addExp(record, exp)
            stats.exp = stats.exp + exp
            for _index, condition in ipairs({"production", "shipped", "shippedBest", "workers", "booster"}) do
                if detail[condition] then stats[condition] = stats[condition] + 1 end
            end
        end
        -- upkeep of the built levels, in both modes; not for industries that are closing
        if config.UPKEEP_BASE > 0 and (industry.closureTimeStamp or 0) <= 0 then
            year = year or yearOf(now)
            local levels = {}
            for _index, upgrade in ipairs(core.UPGRADES) do levels[upgrade.id] = core.level(params, upgrade.id) end
            stats.upkeep = stats.upkeep + core.upkeep(levels, year)
        end

        if record.order then logOrder(key, record, entity, industry, params, now) end
        -- built levels are done; levels still missing (a failed rebuild) are tried again, and so are
        -- order stocks that are missing or left over
        record.targets = core.pendingTargets(record, params)
        if record.targets or not orderBuilt(params, record) then
            queue[#queue + 1] = industry.construction
        end
    end, api.type.ComponentType.INDUSTRY)

    for key in pairs(root.records) do
        -- only once the construction is gone: while another copy of the mod wraps the industries none is
        -- ours, and a record with an open order must survive that
        if not seen[key] and not api.engine.entityExists(tonumber(key) or -1) then root.records[key] = nil end
    end
    if stats.upkeep > 0 then
        local ok, err = pcall(chargeUpkeep, stats.upkeep)
        if not ok then
            stats.upkeep = 0
            if not upkeepErrorLogged then
                upkeepErrorLogged = true
                log.error(LOG_PREFIX .. "charging the upkeep failed: " .. tostring(err))
            end
        end
    end
    return queue, stats
end

-- The first industry in the queue whose last purchase is BUNDLE_WAIT ago (or unknown).
local function nextRebuild(root, now)
    for index, job in ipairs(root.queue or {}) do
        local record = root.records[tostring(job.construction)]
        local last = record and tonumber(record.lastPurchase)
        if not last or now < last or now - last >= core.BUNDLE_WAIT then return index, job end
    end
    return nil
end

-- The construction an event from the industry window is about, with its record. nil when it is gone
-- (bulldozed, or rebuilt with a new id) or not supported.
local function eventTarget(state, param)
    local constructionId = tonumber(param.construction)
    local construction = constructionId and api.engine.entityExists(constructionId)
        and api.engine.getComponent(constructionId, api.type.ComponentType.CONSTRUCTION)
    if not construction or not supported(construction) then return nil end
    local root = loadRoot(state)
    local now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
    local params = copyParams(construction)
    local key = tostring(constructionId)
    local record = ensureRecord(root, key, params, now, api.util.getDefaultYearDuration() / 12)
    record.targets = core.pendingTargets(record, params) -- built levels are done
    return {root = root, record = record, construction = construction, params = params, id = constructionId, key = key, now = now}
end

-- Upgrades bought with points (EXP mode): the next level after those still waiting for the rebuild.
-- The mode is only known once eventTarget has applied the construction's settings. An order opened
-- before a switch to EXP points keeps running; its upgrades wait for it, because a level built in
-- between would change which levels the order's stocks are built for (core.addOrder starts above the
-- built level) while the record still expects the cargo of all of them.
local function buy(state, param)
    local upgrade = core.UPGRADE_BY_ID[param.upgrade]
    if not upgrade then return end
    local target = eventTarget(state, param)
    if not target or core.deliveryMode() then return end
    local record = target.record
    if record.order and record.order.targets and record.order.targets[upgrade.id] then return end
    local nextLevel = core.pendingLevel(record, target.params, upgrade.id) + 1
    if nextLevel > upgrade.max then return end
    local cost = core.cost(nextLevel)
    if record.points < cost then return end
    record.points = record.points - cost
    record.targets = record.targets or {}
    record.targets[upgrade.id] = nextLevel
    log.message(LOG_PREFIX .. "construction " .. target.key .. " bought " .. upgrade.id .. " level " .. nextLevel .. " for " .. cost .. " points")
    record.lastPurchase = target.now
    enqueue(target.root, target.id)
    state:set(target.root)
end

-- Adds (change = 1) or removes (change = -1) the highest planned level of an upgrade.
-- Planning starts above the built, bought and ordered levels (core.planBase) and changes nothing at
-- the industry; it also works while an order is open.
local function plan(state, param)
    local upgrade = core.UPGRADE_BY_ID[param.upgrade]
    local change = tonumber(param.change)
    if not upgrade or (change ~= 1 and change ~= -1) then return end
    local target = eventTarget(state, param)
    if not target or not core.deliveryMode() then return end
    local record = target.record
    local base = core.planBase(record, target.params, upgrade.id)
    local planned = math.max(base, math.min(upgrade.max, core.plannedLevel(record, target.params, upgrade.id) + change))
    record.plan = record.plan or {}
    record.plan[upgrade.id] = planned > base and planned or nil
    if next(record.plan) == nil then record.plan = nil end
    state:set(target.root)
end

local function discard(state, param)
    local target = eventTarget(state, param)
    if not target or not target.record.plan then return end
    target.record.plan = nil
    state:set(target.root)
end

-- What an order for the levels from[id] + 1 up to targets[id] needs at an industry, its cargo chosen
-- from the industry's own stocks: needs and the number of levels (core.orderRequirements).
local function orderNeeds(entity, industry, targets, from)
    local stockList = stockListOf(entity, industry)
    local own = core.ownCargo(stockList and stockList.stocks, stockList and stockList.rules)
    return core.orderRequirements(targets, function(id) return from[id] end, function(name)
        local id = cargoId(name)
        return id < 0 or own[id] == true
    end)
end

-- Opens one delivery order for every planned level. One order per industry at a time.
local function start(state, param)
    local target = eventTarget(state, param)
    if not target or not core.deliveryMode() then return end
    local record = target.record
    if record.order or not record.plan then return end
    local entity, industry = industryOf(target.construction)
    if not entity then return end
    local from, targets = core.planTargets(record, target.params)
    record.plan = nil
    if not targets then -- everything planned is built by now
        state:set(target.root)
        return
    end
    local needs, count = orderNeeds(entity, industry, targets, from)
    if #needs == 0 then
        log.warning(LOG_PREFIX .. "construction " .. target.key .. " found no cargo it could ask for, the plan is dropped")
        state:set(target.root)
        return
    end
    local cargo, parts = {}, {}
    for _index, need in ipairs(needs) do
        cargo[#cargo + 1] = {cargo = need.cargo, amount = need.amount, delivered = 0}
        parts[#parts + 1] = need.amount .. " " .. cargoShortName(need.cargo)
    end
    local stockList = stockListOf(entity, industry)
    record.order = {from = from, targets = targets, cargo = cargo, ratingBefore = countedRating(record, industry, target.now),
        years = config.RESOURCE_YEARS, malus = config.ORDER_MALUS, at = target.now,
        steps = core.orderSteps(stockList and stockList.rules, count)}
    record.closed = nil
    unsaved[target.key] = nil -- counts of a closed order never belong to the new one
    record.lastPurchase = target.now
    enqueue(target.root, target.id)
    state:set(target.root)
    syncedAt = nil -- a new order: watch it from the next consumption event on
    log.message(string.format("%sconstruction %s opened a delivery for %s: %s; %d levels, at least %d months; production rating %s",
        LOG_PREFIX, target.key, core.orderText(record.order), table.concat(parts, ", "), count, core.orderMonths(needs, count),
        tostring(record.order.ratingBefore)))
end

-- Closes the open order; what was delivered is lost, the next rebuild drops its stocks. The plan keeps
-- its number of levels (core.shiftPlan). An order cancelled before its stocks were built leaves
-- nothing to rebuild or to log afterwards.
local function cancel(state, param)
    local target = eventTarget(state, param)
    if not target or not target.record.order then return end
    local order = target.record.order
    log.message(LOG_PREFIX .. "construction " .. target.key .. " cancelled the delivery for " .. core.orderText(order)
        .. " (" .. deliveredText(order) .. ")")
    target.record.order = nil
    target.record.plan = core.shiftPlan(target.record.plan, order)
    if core.hasOrderStocks(target.params) then
        local _entity, industry = industryOf(target.construction)
        closeOrder(target.record, order, "cancelled", industry, target.now)
    end
    unsaved[target.key] = nil
    target.record.lastPurchase = target.now
    enqueue(target.root, target.id)
    state:set(target.root)
    syncedAt = nil
end

-- Whether an order asks for exactly these needs ({{cargo, amount}}), in this order.
local function sameNeeds(order, needs)
    local cargo = order.cargo or {}
    if #cargo ~= #needs then return false end
    for index, need in ipairs(needs) do
        if cargo[index].cargo ~= need.cargo or tonumber(cargo[index].amount) ~= need.amount then return false end
    end
    return true
end

-- Open orders that no longer fit the settings (they can be changed when a savegame is loaded): levels
-- above a lowered maximum, which the construction parameters cannot hold, so such an order would never
-- count as built nor complete; other delivery amounts, which the next rebuild would build stocks for;
-- another minimum duration or production malus, which the order's rule and the production rules were
-- built with (order.years, order.malus; an order opened before those settings existed had 1 year and
-- 25 %). Such an order is worked out again for the levels left, its cargo chosen as start() does and
-- the delivered cargo kept up to the new amounts; an order without any level left is dropped like a
-- cancelled one. Either way the next rebuild brings the order's stocks and rules in line. True when
-- anything changed.
local function fitOrders(root, now)
    local changed = storeCounts(root) -- counts in memory belong to the order as it was
    for key, record in pairs(root.records) do
        local order = record.order
        local construction, entity, industry
        if order then construction, entity, industry = orderIndustry(key) end
        if entity then -- a construction that is gone drops its record in the monthly check
            -- opened before orders kept their start: the minimum duration counts from now, never less
            if core.plainOrderRule() and order.at == nil then
                order.at = now
                changed = true
                log.message(string.format("%sconstruction %s: the delivery for %s waits its minimum duration from now on",
                    LOG_PREFIX, key, core.orderText(order)))
            end
            local targets, from = {}, {}
            for id, target in pairs(order.targets or {}) do
                local upgrade = core.UPGRADE_BY_ID[id]
                if upgrade then
                    local to = math.min(tonumber(target) or 0, upgrade.max)
                    local base = math.min(tonumber(order.from and order.from[id]) or 0, upgrade.max)
                    if to > base then targets[id], from[id] = to, base end
                end
            end
            local needs = next(targets) and orderNeeds(entity, industry, targets, from) or {}
            local text = core.orderText(order)
            local paced = (tonumber(order.years) or 1) == config.RESOURCE_YEARS and (tonumber(order.malus) or 0.25) == config.ORDER_MALUS
            if #needs == 0 then
                record.order = nil
                -- an order whose stocks were never built leaves nothing to rebuild or to log afterwards
                if core.hasOrderStocks(copyParams(construction)) then
                    closeOrder(record, order, "dropped (settings changed)", industry, now)
                end
                log.message(string.format("%sconstruction %s dropped the delivery for %s, no level of it fits the settings (%s)",
                    LOG_PREFIX, key, text, deliveredText(order)))
            elseif not core.sameTargets(targets, order.targets) or not sameNeeds(order, needs) or not paced then
                local delivered = {}
                for _index, need in ipairs(order.cargo or {}) do
                    delivered[need.cargo] = (delivered[need.cargo] or 0) + (tonumber(need.delivered) or 0)
                end
                local cargo = {}
                for _index, need in ipairs(needs) do
                    cargo[#cargo + 1] = {cargo = need.cargo, amount = need.amount, delivered = math.min(need.amount, delivered[need.cargo] or 0)}
                end
                -- refit: rebuilt even if the parameters already name the levels (the engine may cut a
                -- saved value to the shorter list, other amounts change nothing there), and not taken
                -- as built before that
                order.targets, order.from, order.cargo, order.built, order.refit = targets, from, cargo, nil, true
                order.years, order.malus = config.RESOURCE_YEARS, config.ORDER_MALUS
                log.message(string.format("%sconstruction %s fitted the delivery for %s to the settings: %s (%s), at least %d months, production -%d%%",
                    LOG_PREFIX, key, text, core.orderText(order), deliveredText(order),
                    core.orderMonths(cargo, core.orderLevelCount(order)), math.floor(config.ORDER_MALUS * 100 + 0.5)))
            end
            if record.order ~= order or order.refit then
                current[key] = nil
                enqueue(root, tonumber(key))
                changed = true
            end
        end
    end
    syncedAt = nil -- watch the orders as they are now
    return changed
end

-- Industries whose workplaces no longer fit "Workers needed per level" (changeable when a savegame is
-- loaded; limited to 40 since revision 8): their workplaces only change with a rebuild, so each of them
-- is queued once per load; the rebuild builds the workplaces of the current setting (core.applyUpgrades).
-- True when anything changed.
local function fitWorkplaces(root)
    local visited, queued = {}, 0
    api.engine.forEachEntityWithComponent(function(entity)
        local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
        if not industry or visited[industry.construction] then return end
        visited[industry.construction] = true
        local construction = api.engine.getComponent(industry.construction, api.type.ComponentType.CONSTRUCTION)
        if not construction or not supported(construction) then return end
        if workplacesOutdated(construction, copyParams(construction)) and enqueue(root, industry.construction) then
            queued = queued + 1
        end
    end, api.type.ComponentType.INDUSTRY)
    if queued > 0 then
        log.message(string.format("%s%d industries with workplaces that do not fit \"Workers needed per level\", rebuild queued", LOG_PREFIX, queued))
    end
    return queued > 0
end

function data()
    return {
        update = function(_userParams, state, dt)
            -- On every update, not only without any subscription: a savegame whose script subscribed to
            -- fewer events (an older version) gets the missing ones. Subscribing again is harmless; the
            -- base game's town_growth.script.tl does it on every update as well.
            state:subscribeToEvent(core.EVENT_BUY)
            state:subscribeToEvent(core.EVENT_CANCEL)
            state:subscribeToEvent(core.EVENT_PLAN)
            state:subscribeToEvent(core.EVENT_START)
            state:subscribeToEvent(core.EVENT_DISCARD)
            state:subscribeToEvent(core.CONSUMED_EVENT)
            if not dt or dt <= 0 then return end
            local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
            if (gameTime.updateCount or 0) % WORK_INTERVAL_TICKS ~= 0 then return end
            local root, changed = loadRoot(state)
            local now = gameTime.gameTime
            local month = api.util.getDefaultYearDuration() / 12
            applySettings(root)
            if configured and not fitted then
                fitted = true
                if fitOrders(root, now) then changed = true end
                if fitWorkplaces(root) then changed = true end
            end
            -- complete orders become targets; log the orders whose stocks were just built
            if completeOrders(root, now, 12 * month) then changed = true end
            if checkOrders(root, now) then changed = true end
            if changed then state:set(root) end

            local index, job = nextRebuild(root, now)
            if job then
                table.remove(root.queue, index)
                if #root.queue == 0 then root.queue = nil end
                local record = root.records[tostring(job.construction)]
                local refit = record and record.order and record.order.refit
                if refit then record.order.refit = nil end
                -- Progress is stored before asking the engine, so an error can never repeat the same rebuild.
                state:set(root)
                local ok, err = pcall(rebuild, job, record, now, refit)
                if not ok and not errorLogged then
                    errorLogged = true
                    log.error(LOG_PREFIX .. "rebuilding construction " .. tostring(job.construction) .. " failed: " .. tostring(err))
                end
                return
            end

            if root.lastCheck and root.lastCheck <= now and now - root.lastCheck < month then return end
            root.lastCheck = now
            local queue, stats = monthlyPass(root, now, month)
            -- retries of failed rebuilds; a purchase still waiting for its rebuild is queued already
            local retries = 0
            for _, construction in ipairs(queue) do
                if enqueue(root, construction) then retries = retries + 1 end
            end
            local summary = string.format("%smonthly check: %d industries, %d EXP (production %d, shipped %d, best product shipped %d, workers %d, booster %d), %d new points, %d not supported, %d rebuilds queued, upkeep %d",
                LOG_PREFIX, stats.industries, stats.exp, stats.production, stats.shipped, stats.shippedBest, stats.workers, stats.booster,
                stats.points, stats.unsupported, retries, stats.upkeep)
            log.message(summary)
            state:set(root)
        end,

        handleEvent = function(_userParams, state, _src, id, name, param)
            if id == core.CONSUMED_SOURCE and name == core.CONSUMED_EVENT then
                countConsumed(state, param)
                return
            end
            if id ~= core.EVENT_ID or type(param) ~= "table" then return end
            if name == core.EVENT_BUY then
                buy(state, param)
            elseif name == core.EVENT_PLAN then
                plan(state, param)
            elseif name == core.EVENT_START then
                start(state, param)
            elseif name == core.EVENT_DISCARD then
                discard(state, param)
            elseif name == core.EVENT_CANCEL then
                cancel(state, param)
            end
        end,
    }
end
