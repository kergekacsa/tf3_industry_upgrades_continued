-- The worker limit: 40 workers while "Workers needed per level" is on, the workplaces and workers it
-- allows, "Number of worker boost levels", the worker script that counts the workers, and the redirect
-- of the base game's worker script, which gives way to another mod's.
-- Run from the mod folder: lua55 tests/workers_test.lua

local support = dofile("tests/support.lua")
local core, check, game = support.core, support.check, support.game

local FRACTION = 0.5 -- the base game's RequiredWorkersFractionForBoost
local WORKERS_PARAM = core.UPGRADE_BY_ID.workers.param
local NEEDED_OFF, NEEDED_FULL = 1, 5 -- choices of "Workers needed per level": Off, +100 %

-- the limits
core.configure(nil)
check("default limit", core.workerLimit(), 20)
check("default: base script", core.ownWorkerScript(), false)
check("default workplace limit", core.workplaceLimit(0), 40)
check("default keeps 20 when boosted", core.arrivalsKept(100, FRACTION, true), 20)
check("default worker levels", core.UPGRADE_BY_ID.workers.max, 5)

core.configure({WORKER_LEVELS = 10})
check("10 worker levels", core.UPGRADE_BY_ID.workers.max, 10)
check("other upgrades keep 5", core.UPGRADE_BY_ID.storage.max, 5)

core.configure({WORKERS_NEEDED = 1})
check("workers needed on: limit 40", core.workerLimit(), 40)
check("workers needed on: own script", core.ownWorkerScript(), true)
check("workplace limit 80", core.workplaceLimit(0), 80)
check("own workplaces above 80 stay", core.workplaceLimit(100), 100)
check("built workplaces capped at 80", core.builtWorkplaces(20, 5), 80)
check("boosted, needs 30", core.arrivalsKept(60, FRACTION, true), 30)
check("boosted, capped at 40", core.arrivalsKept(100, FRACTION, true), 40)
check("boosted, never below 20", core.arrivalsKept(30, FRACTION, true), 20)
check("not boosted keeps 20", core.arrivalsKept(100, FRACTION, false), 20)

-- the boost: in proportion to the workers with partial, else all or nothing
local function permille(value) return math.floor(value * 1000 + 0.5) end
check("needed for 45 workplaces", core.workersNeeded(45, FRACTION), 23)
check("partial 15 of 40", permille(core.workerProductivity(1.8, 15, 40, true)), 1300)
check("base game 15 of 40", core.workerProductivity(1.8, 15, 40, false), 1)
check("base game 40 of 40", core.workerProductivity(1.8, 40, 40, false), 1.8)
check("partial above needed", core.workerProductivity(1.8, 50, 40, true), 1.8)
check("no workers", core.workerProductivity(1.8, 0, 40, true), 1)

-- the worker script at one industry with 80 workplaces
local CAPACITY = 80
local sentProductivity
ug_require = function(name)
    if name:find("entity_util") then
        return {
            entityEquals = function(a, b) return a.id == b.id end,
            makeEntityAndRevision = function(entity) return {id = entity} end,
        }
    end
    return {
        workersTimeIntervalMax = 1e12,
        RequiredWorkersFractionForBoost = FRACTION,
        isIndustryWorkersBoosted = function(_entity, count) return count >= CAPACITY * FRACTION end,
        getIndustryProductivity = function() return 1 end,
        getPersonCapacityPotentialBoost = function() return 2 end,
    }
end
api.type.ComponentType.PERSON_CAPACITY = "PERSON_CAPACITY"
api.type.ComponentType.TOWN_BUILDING = "TOWN_BUILDING"
api.type.StockList = {Modifiers = {new = function() return {} end}}
api.cmd.makeStockListSetModifiersCmd = function(_entity, modifiers) sentProductivity = modifiers.productivity; return {} end
game.constructions[game.INDUSTRY] = {} -- the industry entity exists
local getComponent = api.engine.getComponent
api.engine.getComponent = function(entity, componentType)
    if componentType == "PERSON_CAPACITY" and entity == game.INDUSTRY then return {capacity = CAPACITY} end
    if componentType == "TOWN_BUILDING" then return nil end
    return getComponent(entity, componentType)
end

-- The workers kept at an industry with workerLevel worker boost levels when one more arrives on top of
-- a history of arrivals - 1, newest first. Like the base game's, the script keeps every worker who
-- arrived since its last update and cuts only the history.
local function kept(workerLevel, arrivals)
    game.settings = {WORKERS_NEEDED = 1}
    game.constructions[game.MILL] = {fileName = "industry/saw_mill.con", params = {[WORKERS_PARAM] = workerLevel + 1}}
    sentProductivity = nil
    dofile("content/industry_upgrades/workers.script.lua")
    local script = data()
    local history = {}
    for index = 1, arrivals - 1 do history[index] = {time = arrivals - index, entity = {id = 1000 + index}} end
    local pending = {{time = arrivals, entity = {id = 1}}}
    local saved = {industriesState = {[game.INDUSTRY] = {lastVisitors = history, pendingVisitors = pending}}}
    local state = {
        hasEventSubscriptions = function() return true end,
        get = function() return saved end,
        set = function(_self, root) saved = root end,
    }
    script.update(nil, state, 1)
    return #saved.industriesState[game.INDUSTRY].lastVisitors
end

check("boosted industry keeps 35", kept(1, 35), 35)
check("partial boost at 35 of 40", permille(sentProductivity), 1875)
check("boosted industry keeps 40", kept(1, 45), 40)
check("full boost at 40", sentProductivity, 2)
check("industry without levels keeps 20", kept(0, 45), 20)
check("partial boost at 20 of 40", permille(sentProductivity), 1500)
check("logged keeping more than 20", support.count("keeps 40 arrivals") >= 1, true)

-- the redirect of the base game's worker script
local function loadModifiers(choice)
    local modifiers = {}
    addModifier = function(name, fn) modifiers[name] = fn end
    _ = function(text) return text end
    dofile("content/mod.script.lua")
    data().runFn(nil, nil, {[core.MOD_ID] = {workersNeeded = choice}})
    return modifiers
end
local function baseScript()
    return {updateScript = {fileName = "industry_workers.script@update"},
        handleEventScript = {fileName = "industry_workers.script@handleEvent"}}
end

check("workers needed off: nothing replaced", loadModifiers(NEEDED_OFF).loadGameScript, nil)

local modifiers = loadModifiers(NEEDED_FULL)
local script = modifiers.loadGameScript("::/industries/industry_workers.gs.lua", baseScript())
check("on: update redirected", script.updateScript.fileName, core.WORKERS_SCRIPT .. "@update")
check("on: event redirected", script.handleEventScript.fileName, core.WORKERS_SCRIPT .. "@handleEvent")
check("on: other game scripts untouched",
    modifiers.loadGameScript("res/other.gs", baseScript()).updateScript.fileName, "industry_workers.script@update")

modifiers = loadModifiers(NEEDED_FULL)
local foreign = {updateScript = {fileName = "other_mod::/workers.script@update"}}
script = modifiers.loadGameScript("res/industries/industry_workers.gs", foreign)
check("another mod's script stays", script.updateScript.fileName, "other_mod::/workers.script@update")
check("limit back at 20", core.workerLimit(), 20)
check("logged the conflict", support.count("from another mod, so the worker limit stays 20"), 1)

-- the settings the industries carry fall back to 20 as well
local construction = {isIndustry = true, updateScript = {fileName = "industry/saw_mill.script@update", params = {}}}
construction = modifiers.loadConstruction("industry/saw_mill.con", construction)
check("industries carry 20", construction.updateScript.params[core.KEY].settings.WORKER_LIMIT, 20)

support.finish("workers_test")
