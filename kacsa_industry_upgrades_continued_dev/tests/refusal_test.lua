-- Tests of the refused rebuild in upgrades.script.lua against the stub of the game: the check after a
-- rebuild, the refund event, and core.refundPoints.
-- Run from the mod folder: lua55 tests/refusal_test.lua

local support = dofile("tests/support.lua")
local core, game, check = support.core, support.game, support.check
local MILL = game.MILL

local script, state, holder

local function warnings() return support.count("^WARNING .*refused the rebuild") end

-- A mill at level 0 with bought levels waiting in the queue; the monthly check is not due.
local function setUp(targets)
    game.constructions[MILL] = {fileName = "mill.con", params = {[core.THROUGHPUT_PARAM] = 1, industryUpgradesStorage = 1}}
    game.gameTime.gameTime = 100000
    script, state, holder = support.loadScript({version = core.STATE_VERSION, lastCheck = game.gameTime.gameTime,
        lastMonth = support.calendarMonth(game.gameTime.gameTime),
        records = {[tostring(MILL)] = {points = 0, exp = 0, targets = targets, lastPurchase = 0}},
        queue = {{construction = MILL}}})
    game.sent, game.logged = {}, {}
end

local function tick(ms) support.tick(script, state, ms) end
local function record() return holder.saved.records[tostring(MILL)] end
local function event(name) script.handleEvent(nil, state, nil, core.EVENT_ID, name, {construction = MILL, upgrade = "throughput"}) end

-- refundPoints: every level above the built one, at the current cost
check("refundPoints 0->2 and 0->1", core.refundPoints({throughput = 2, storage = 1}, {[core.THROUGHPUT_PARAM] = 1}), 3)
check("refundPoints from a built level", core.refundPoints({throughput = 3}, {[core.THROUGHPUT_PARAM] = 2}), 2)
check("refundPoints nothing pending", core.refundPoints(nil, {}), 0)

-- a rebuild that the game refuses: the levels are still missing after the wait
setUp({throughput = 2})
tick(0)
check("rebuild sent", #game.sent, 1)
check("sentAt noted", record().sentAt, game.gameTime.gameTime)
tick(core.REBUILD_CHECK_WAIT - 1)
check("not checked before the wait", record().refused, nil)
tick(1)
check("refused after the wait", record().refused, true)
check("sentAt cleared", record().sentAt, nil)
check("refusal logged once", warnings(), 1)

-- the monthly retry is refused again: no second warning
holder.saved.queue = {{construction = MILL}}
tick(0)
tick(core.REBUILD_CHECK_WAIT)
check("still refused", record().refused, true)
check("no repeated warning", warnings(), 1)

-- refund: the points of both levels come back, the levels and the queued retry are gone
holder.saved.queue = {{construction = MILL}}
event(core.EVENT_REFUND)
check("points refunded", record().points, 2)
check("targets dropped", record().targets, nil)
check("refused cleared", record().refused, nil)
check("queue emptied", holder.saved.queue, nil)

-- refund is ignored while the rebuild is not refused
setUp({throughput = 1})
event(core.EVENT_REFUND)
check("no refund without a refusal", record().points, 0)
check("targets kept without a refusal", record().targets.throughput, 1)

-- a rebuild that works: the construction has the levels
setUp({storage = 1})
tick(0)
game.constructions[MILL].params.industryUpgradesStorage = 2
tick(core.REBUILD_CHECK_WAIT)
check("built: not refused", record().refused, nil)
check("built: no warning", warnings(), 0)

-- a rebuild that works with a new construction entity: the old one is gone
setUp({storage = 1})
tick(0)
game.constructions[MILL] = nil
tick(core.REBUILD_CHECK_WAIT)
check("new entity: not refused", record().refused, nil)

-- a purchase after the rebuild was sent: that rebuild is not checked
setUp({throughput = 1})
tick(0)
record().points = 1
event(core.EVENT_BUY)
check("purchase clears sentAt", record().sentAt, nil)
check("purchase bought the next level", record().targets.throughput, 2)

support.finish("refusal_test")
