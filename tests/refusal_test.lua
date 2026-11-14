-- Tests of the refused rebuild in upgrades.script.lua against a stub of the game: the check after a
-- rebuild, the refund event, and core.refundPoints.
-- Run from the mod folder: lua55 tests/refusal_test.lua

local MOD_PREFIX = "stardorn_industry_upgrades::/"
local modules = {}
require = function(name)
    local file = "content/" .. name:sub(#MOD_PREFIX + 1)
    modules[file] = modules[file] or dofile(file)
    return modules[file]
end
ug_require = function() return {} end

local logged = {}
log = {
    message = function(line) logged[#logged + 1] = line end,
    warning = function(line) logged[#logged + 1] = "WARNING " .. line end,
    error = function(line) logged[#logged + 1] = "ERROR " .. line end,
}

local MILL = 7
local MONTH = 60000
local gameTime = {gameTime = 100000, updateCount = 0}
local constructions = {}
local sent = {}
api = {
    type = {ComponentType = {GAME_TIME = "GAME_TIME", CONSTRUCTION = "CONSTRUCTION", INDUSTRY = "INDUSTRY"}},
    engine = {
        util = {
            getWorld = function() return 0 end,
            proposal = {createProposalReplaceConstruction = function(id, params) return {id = id, params = params} end},
        },
        getComponent = function(entity, componentType)
            if componentType == "GAME_TIME" then return gameTime end
            if componentType == "CONSTRUCTION" then return constructions[entity] end
            return nil
        end,
        entityExists = function(entity) return constructions[entity] ~= nil end,
        forEachEntityWithComponent = function() end,
    },
    res = {constructionRep = {
        find = function() return 1 end,
        get = function() return {updateScript = {params = {industryUpgrades = {mod = "stardorn_industry_upgrades"}}}} end,
    }},
    cmd = {
        makeWorldBuildProposalCmd = function(proposal) return proposal end,
        sendCommand = function(command) sent[#sent + 1] = command end,
    },
    util = {getDefaultYearDuration = function() return 12 * MONTH end},
}

local core = require(MOD_PREFIX .. "industry_upgrades/core.lua")
dofile("content/industry_upgrades/upgrades.script.lua")
local script = data()

local saved
local state = {
    get = function() return saved end,
    set = function(_self, root) saved = root end,
    subscribeToEvent = function() end,
}

local failures = 0
local function check(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
    end
end

local function warnings()
    local count = 0
    for _index, line in ipairs(logged) do
        if line:find("^WARNING .*refused the rebuild") then count = count + 1 end
    end
    return count
end

-- A mill at level 0 with bought levels waiting in the queue; the monthly check is not due.
local function setUp(targets)
    constructions[MILL] = {fileName = "mill.con", params = {[core.THROUGHPUT_PARAM] = 1, industryUpgradesStorage = 1}}
    saved = {version = core.STATE_VERSION, lastCheck = gameTime.gameTime,
        records = {[tostring(MILL)] = {points = 0, exp = 0, targets = targets, lastPurchase = 0}},
        queue = {{construction = MILL}}}
    sent, logged = {}, {}
end

local function tick(ms)
    gameTime.gameTime = gameTime.gameTime + ms
    script.update(nil, state, 1)
end

local function record() return saved.records[tostring(MILL)] end
local function event(name) script.handleEvent(nil, state, nil, core.EVENT_ID, name, {construction = MILL, upgrade = "throughput"}) end

-- refundPoints: every level above the built one, at the current cost
check("refundPoints 0->2 and 0->1", core.refundPoints({throughput = 2, storage = 1}, {[core.THROUGHPUT_PARAM] = 1}), 3)
check("refundPoints from a built level", core.refundPoints({throughput = 3}, {[core.THROUGHPUT_PARAM] = 2}), 2)
check("refundPoints nothing pending", core.refundPoints(nil, {}), 0)

-- a rebuild that the game refuses: the levels are still missing after the wait
setUp({throughput = 2})
tick(0)
check("rebuild sent", #sent, 1)
check("sentAt noted", record().sentAt, gameTime.gameTime)
tick(core.REBUILD_CHECK_WAIT - 1)
check("not checked before the wait", record().refused, nil)
tick(1)
check("refused after the wait", record().refused, true)
check("sentAt cleared", record().sentAt, nil)
check("refusal logged once", warnings(), 1)

-- the monthly retry is refused again: no second warning
saved.queue = {{construction = MILL}}
tick(0)
tick(core.REBUILD_CHECK_WAIT)
check("still refused", record().refused, true)
check("no repeated warning", warnings(), 1)

-- refund: the points of both levels come back, the levels and the queued retry are gone
saved.queue = {{construction = MILL}}
event(core.EVENT_REFUND)
check("points refunded", record().points, 2)
check("targets dropped", record().targets, nil)
check("refused cleared", record().refused, nil)
check("queue emptied", saved.queue, nil)

-- refund is ignored while the rebuild is not refused
setUp({throughput = 1})
event(core.EVENT_REFUND)
check("no refund without a refusal", record().points, 0)
check("targets kept without a refusal", record().targets.throughput, 1)

-- a rebuild that works: the construction has the levels
setUp({storage = 1})
tick(0)
constructions[MILL].params.industryUpgradesStorage = 2
tick(core.REBUILD_CHECK_WAIT)
check("built: not refused", record().refused, nil)
check("built: no warning", warnings(), 0)

-- a rebuild that works with a new construction entity: the old one is gone
setUp({storage = 1})
tick(0)
constructions[MILL] = nil
tick(core.REBUILD_CHECK_WAIT)
check("new entity: not refused", record().refused, nil)

-- a purchase after the rebuild was sent: that rebuild is not checked
setUp({throughput = 1})
tick(0)
record().points = 1
event(core.EVENT_BUY)
check("purchase clears sentAt", record().sentAt, nil)
check("purchase bought the next level", record().targets.throughput, 2)

if failures > 0 then
    print(failures .. " check(s) failed")
    os.exit(1)
end
print("refusal_test: all checks passed")
