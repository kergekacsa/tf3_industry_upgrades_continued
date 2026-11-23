-- The base game's worker boost script (industries/industry_workers.script.tl), run in its place while
-- "Workers needed per level" is on (mod.script.lua redirects industry_workers.gs here). It is the
-- same script with two changes. The base game keeps the last 20 arrivals by line of an industry
-- (KeepHistoryCount), so a boost that needs more than 20 (over 40 workplaces) never comes. At an
-- industry with worker boost levels this copy keeps as many as its boost needs, up to the worker limit;
-- at every other industry 20 (core.arrivalsKept). And every industry gets the boost in proportion to
-- its workers, not only once all of them arrive (updateIndustryProductivity). The game script entity, its state and its event stay
-- the base game's, so industry_productivity_util, the industry window and savegames read the arrivals
-- as before; without the redirect the base game cuts them to 20 again.
local core = require "kacsa_industry_upgrades_continued::/industry_upgrades/core.lua"
local entity_util = ug_require "::/scripts/entity_util.tl"
local productivity = ug_require "::/industries/industry_productivity_util.tl"

local LOG_PREFIX = core.LOG_PREFIX
local started = false
local configured = false -- whether this Lua state has applied the mod settings an industry carries
local logged = {} -- industries logged keeping more arrivals than the base game, this session

-- Whether the industry (entity) has worker boost levels. Only industries whose construction script we
-- wrapped have them; the first one also brings the mod settings into this Lua state.
local function boosted(entity)
    local industry = api.engine.getComponent(entity, api.type.ComponentType.INDUSTRY)
    local construction = industry and api.engine.getComponent(industry.construction, api.type.ComponentType.CONSTRUCTION)
    if not construction then return false end
    local resId = api.res.constructionRep.find(construction.fileName)
    local own = resId and resId >= 0 and core.ownEntry(api.res.constructionRep.get(resId))
    if not own then return false end
    if not configured then
        local okSettings, settings = pcall(function() return own.settings end)
        core.configure(okSettings and settings or nil)
        configured = true
    end
    local params = construction.params_native and construction.params_native:asTable() or construction.params
    return core.level(params, "workers") > 0
end

-- The base game sets the full boost or none; this copy sets the partial boost (core.workerProductivity)
-- at every industry, and sends it only when it moves by PRODUCTIVITY_STEP or more.
local PRODUCTIVITY_STEP = 0.001
local function updateIndustryProductivity(entity, numVisitors, capacity)
    local needed = core.workersNeeded(capacity, productivity.RequiredWorkersFractionForBoost)
    local factor = numVisitors > 0 and productivity.getPersonCapacityPotentialBoost(entity) or 1
    local newProductivity = core.workerProductivity(factor, numVisitors, needed, true)
    if math.abs(newProductivity - productivity.getIndustryProductivity(entity)) >= PRODUCTIVITY_STEP then
        local newModifiers = api.type.StockList.Modifiers.new()
        newModifiers.productivity = newProductivity
        api.cmd.sendCommand(api.cmd.makeStockListSetModifiersCmd(entity, newModifiers))
    end
end

function data()
    return {
        update = function(_userParams, state, dt)
            if not state:hasEventSubscriptions() then
                state:subscribeToEvent("OnToArriveAtDestination")
            end
            if dt == 0 then return end
            if not started then
                started = true
                log.message(LOG_PREFIX .. "worker boost: industries with worker boost levels keep the arrivals by line their boost needs, up to the worker limit (base game: 20)")
            end

            local state2 = state:get()
            if not state2 or not state2.industriesState then return end

            local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
            local cutoffTime = gameTime.gameTime - productivity.workersTimeIntervalMax
            local stateChanged = false
            for entity, industryState in pairs(state2.industriesState) do
                local persons = api.engine.entityExists(entity) and api.engine.getComponent(entity, api.type.ComponentType.PERSON_CAPACITY)
                if persons and not api.engine.getComponent(entity, api.type.ComponentType.TOWN_BUILDING) then
                    local hasPendingVisitors = industryState.pendingVisitors and #industryState.pendingVisitors > 0
                    local lastVisitorValid = industryState.lastVisitors == nil or #industryState.lastVisitors == 0
                        or industryState.lastVisitors[#industryState.lastVisitors].time >= cutoffTime
                    if hasPendingVisitors or not lastVisitorValid then
                        local pendingVisitors = industryState.pendingVisitors or {}
                        table.sort(pendingVisitors, function(a, b) return a.time > b.time end)
                        if industryState.lastVisitors == nil then industryState.lastVisitors = {} end
                        if industryState.pendingVisitors == nil then industryState.pendingVisitors = {} end
                        local keep = core.arrivalsKept(persons.capacity, productivity.RequiredWorkersFractionForBoost, boosted(entity))
                        local newLastVisitors = pendingVisitors
                        industryState.pendingVisitors = {}
                        for i = 1, #industryState.lastVisitors do
                            local currentVisitor = industryState.lastVisitors[i]
                            if currentVisitor.time < cutoffTime or #newLastVisitors >= keep then break end
                            local foundPendingVisitor = false
                            for _index, pendingVisitor in ipairs(pendingVisitors) do
                                if entity_util.entityEquals(pendingVisitor.entity, currentVisitor.entity) then
                                    foundPendingVisitor = true
                                end
                            end
                            if not foundPendingVisitor then
                                table.insert(newLastVisitors, industryState.lastVisitors[i])
                            end
                        end
                        industryState.lastVisitors = newLastVisitors
                        if #newLastVisitors > core.ARRIVALS_KEPT and not logged[entity] then
                            logged[entity] = true
                            log.message(string.format("%sworker boost: industry %s keeps %d arrivals by line (%s workplaces, the boost needs %d)",
                                LOG_PREFIX, tostring(entity), #newLastVisitors, tostring(persons.capacity), keep))
                        end
                        updateIndustryProductivity(entity, #newLastVisitors, persons.capacity)
                        stateChanged = true
                    end
                else
                    state2.industriesState[entity] = nil
                    stateChanged = true
                end
            end
            if stateChanged then state:set(state2) end
        end,

        handleEvent = function(_userParams, state, _src, id, name, param)
            if id ~= "SimPersonSystem" or name ~= "OnToArriveAtDestination" then return end
            local state2 = nil
            for _index, entity in ipairs(param.entities) do
                local simPerson = api.engine.getComponent(entity, api.type.ComponentType.SIM_PERSON)
                local traveledByLines = simPerson.lastMoveMode == api.type["enum"].MoveMode.LINES
                if simPerson.targetOrAtEntity >= 0 and traveledByLines
                    and not api.engine.getComponent(simPerson.targetOrAtEntity, api.type.ComponentType.TOWN_BUILDING)
                    and api.engine.getComponent(simPerson.targetOrAtEntity, api.type.ComponentType.PERSON_CAPACITY) then
                    local gameTime = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
                    if state2 == nil then state2 = state:get() or {} end
                    if not state2.industriesState then state2.industriesState = {} end
                    local industryState = state2.industriesState[simPerson.targetOrAtEntity]
                    if not industryState then
                        industryState = {lastVisitors = {}, pendingVisitors = {}}
                        state2.industriesState[simPerson.targetOrAtEntity] = industryState
                    end
                    local pendingVisitors = industryState.pendingVisitors or {}
                    pendingVisitors[#pendingVisitors + 1] = {
                        time = gameTime.gameTime,
                        entity = entity_util.makeEntityAndRevision(entity),
                    }
                    industryState.pendingVisitors = pendingVisitors
                end
            end
            if state2 then state:set(state2) end
        end,
    }
end
