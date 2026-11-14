-- Reports 1 and 2: EXP and upkeep must come once per calendar month, at every calendar speed.
-- Run from the mod folder: lua55 tests/calendar_test.lua

local support = dofile("tests/support.lua")
local core, game, check = support.core, support.game, support.check

local UPKEEP = 1000
local MONTHS = 3
local TICKS_PER_DEFAULT_MONTH = 20
local STEP = math.floor(support.MONTH / TICKS_PER_DEFAULT_MONTH)

local function setUp(millisPerDay)
    game.gameSpeed.millisPerDay = millisPerDay
    game.gameTime.gameTime = 0
    game.settings = {UPKEEP_BASE = UPKEEP}
    game.constructions[game.MILL] = {fileName = "mill.con", params = {[core.THROUGHPUT_PARAM] = 2}}
    game.logged, game.journal = {}, {}
end

local function checks() return support.count("monthly check") end

-- Ticks through a span of game time: the monthly checks and upkeep bookings in it.
local function run(script, state, span)
    local checksBefore, bookingsBefore = checks(), #game.journal
    for _tick = 1, math.ceil(span / STEP) do support.tick(script, state, STEP) end
    return checks() - checksBefore, #game.journal - bookingsBefore
end

-- One calendar month after another at a calendar speed (factor 1 = default, 0.125 = 1/8).
for _index, factor in ipairs({1, 0.25, 0.125}) do
    setUp(math.floor(support.DEFAULT_MILLIS_PER_DAY / factor))
    local script, state = support.loadScript(nil)
    support.tick(script, state, 0) -- the first check after loading
    local calendarMonth = support.DAYS_PER_MONTH * game.gameSpeed.millisPerDay
    local monthly, bookings = run(script, state, MONTHS * calendarMonth)
    check("monthly checks in " .. MONTHS .. " calendar months at calendar speed x" .. factor, monthly, MONTHS)
    check("upkeep bookings in " .. MONTHS .. " calendar months at calendar speed x" .. factor, bookings, MONTHS)
end

-- A state saved before lastMonth, whose last check was in the current calendar month: no second check
-- in that month after loading, the next one at the next month.
setUp(support.DEFAULT_MILLIS_PER_DAY * 8)
game.gameTime.gameTime = 5 * STEP
local script, state = support.loadScript({version = core.STATE_VERSION, lastCheck = 0, records = {}})
support.tick(script, state, 0)
check("old state: no extra check in the month of its last check", checks(), 0)
local calendarMonth = support.DAYS_PER_MONTH * game.gameSpeed.millisPerDay
run(script, state, calendarMonth - 5 * STEP)
check("old state: the check at the next calendar month", checks(), 1)

-- A calendar that stands still: once per month of game time at the default speed
setUp(0)
script, state = support.loadScript(nil)
support.tick(script, state, 0)
local monthly = run(script, state, MONTHS * support.MONTH)
check("still calendar: monthly checks in " .. MONTHS .. " default months", monthly, MONTHS)

support.finish("calendar_test")
