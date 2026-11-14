-- Report 3: booster inputs built under another "Booster demand per level" are recognised, so the booster
-- card can say that the next upgrade rebuilds them with the current setting.
-- Run from the mod folder: lua55 tests/booster_test.lua

local support = dofile("tests/support.lua")
local core, check = support.core, support.check

local BOOSTER_LEVEL = 3
local function booster(amount) return {booster = true, boostFactor = 0.5, input = {{0, amount}}} end
local production = {input = {{4, 0}}, output = {product = 2}}

-- built while the demand was off: the base game's 10 per cycle, then the demand is switched to +25 %
core.configure({BOOSTER_DEMAND = 0.25})
check("built with demand off, now +25 %", core.boosterOutdated({production, booster(10)}, BOOSTER_LEVEL), true)

-- built with the current demand: 10 x 1.75 = 17.5 -> 18
check("built with the current demand", core.boosterOutdated({production, booster(18)}, BOOSTER_LEVEL), false)

-- no booster level, or the demand off: nothing to tell
check("level 0", core.boosterOutdated({booster(10)}, 0), false)
core.configure({BOOSTER_DEMAND = 0})
check("demand off", core.boosterOutdated({booster(18)}, BOOSTER_LEVEL), false)

-- a delivery order's booster is not the industry's own
core.configure({BOOSTER_DEMAND = 0.25})
check("order booster ignored", core.boosterOutdated({{booster = true, boostFactor = core.ORDER_BOOST, input = {{10}}}}, BOOSTER_LEVEL), false)

support.finish("booster_test")
