-- A stub of the game for the tests: module loading, the log, and the parts of the game api that the
-- game script and core.lua use. Run every test from the dev folder; the mod is its sibling folder
-- (support.CONTENT).
--
-- The calendar: a day lasts game.millisPerDay ms of game time, a month 30 days, a year 12 months.
-- DEFAULT_MILLIS_PER_DAY is the default calendar speed, so api.util.getDefaultYearDuration() is a year
-- at that speed. One industry (game.INDUSTRY) belongs to the construction game.MILL.

local support = {}

support.CONTENT = "../kacsa_industry_upgrades_continued/content/"
local MOD_PREFIX = "kacsa_industry_upgrades_continued::/"
local modules = {}
require = function(name)
    local file = support.CONTENT .. name:sub(#MOD_PREFIX + 1)
    modules[file] = modules[file] or dofile(file)
    return modules[file]
end
ug_require = function() return {} end

support.DEFAULT_MILLIS_PER_DAY = 2000
support.DAYS_PER_MONTH = 30
support.MONTH = support.DEFAULT_MILLIS_PER_DAY * support.DAYS_PER_MONTH -- a month at the default speed
support.START_YEAR = 1900

local game = {
    MILL = 7,
    INDUSTRY = 8,
    STOCK_LIST = 9,
    gameTime = {gameTime = 0, updateCount = 0},
    gameSpeed = {speedup = 1, millisPerDay = support.DEFAULT_MILLIS_PER_DAY},
    constructions = {},
    settings = nil, -- the mod settings that the construction resource carries
    sent = {},      -- build proposals sent
    journal = {},   -- upkeep amounts booked
    logged = {},
}
support.game = game

log = {
    message = function(line) game.logged[#game.logged + 1] = line end,
    warning = function(line) game.logged[#game.logged + 1] = "WARNING " .. line end,
    error = function(line) game.logged[#game.logged + 1] = "ERROR " .. line end,
}

function support.calendarDate(time)
    local day = math.floor(time / game.gameSpeed.millisPerDay)
    local month = math.floor(day / support.DAYS_PER_MONTH)
    return {year = support.START_YEAR + math.floor(month / 12), month = month % 12 + 1, day = day % support.DAYS_PER_MONTH + 1}
end

-- The calendar month as the game script keeps it: year * 12 + month.
function support.calendarMonth(time)
    local date = support.calendarDate(time)
    return date.year * 12 + date.month
end

local industry = {construction = game.MILL, stockList = game.STOCK_LIST, closureTimeStamp = 0}
local stockList = {rules = {}, stocks = {}, modifiers = {productivity = 1}}

api = {
    type = {
        ComponentType = {GAME_TIME = "GAME_TIME", GAME_SPEED = "GAME_SPEED", CONSTRUCTION = "CONSTRUCTION",
            INDUSTRY = "INDUSTRY", STOCK_LIST = "STOCK_LIST"},
        JournalEntry = {new = function() return {category = {}} end, Type = {MAINTENANCE = 1}, Maintenance = {OTHER = 1}},
        Vec3f = {new = function() return {} end},
    },
    engine = {
        util = {
            getWorld = function() return 0 end,
            getPlayer = function() return 1 end,
            getCalendarDate = support.calendarDate,
            proposal = {createProposalReplaceConstruction = function(id, params) return {id = id, params = params} end},
            stock = {
                getCargoShippedPerYear = function() return 0 end,
                getCargoOutputPerYear = function() return 0 end,
                getProductionRating = function() return 1 end,
            },
            industry = {getIndustryProductivityInfo = function() return nil end},
        },
        getComponent = function(entity, componentType)
            if componentType == "GAME_TIME" then return game.gameTime end
            if componentType == "GAME_SPEED" then return game.gameSpeed end
            if componentType == "CONSTRUCTION" then return game.constructions[entity] end
            if componentType == "INDUSTRY" and entity == game.INDUSTRY and game.constructions[game.MILL] then return industry end
            if componentType == "STOCK_LIST" then return stockList end
            return nil
        end,
        entityExists = function(entity) return game.constructions[entity] ~= nil end,
        forEachEntityWithComponent = function(fn, componentType)
            if componentType == "INDUSTRY" and game.constructions[game.MILL] then fn(game.INDUSTRY) end
        end,
    },
    res = {constructionRep = {
        find = function() return 1 end,
        get = function()
            return {updateScript = {params = {industryUpgrades = {mod = "kacsa_industry_upgrades_continued", settings = game.settings}}}}
        end,
    }},
    cmd = {
        makeWorldBuildProposalCmd = function(proposal) return {proposal = proposal} end,
        makeJournalBookAssetCmd = function(_player, entry) return {journal = entry} end,
        sendCommand = function(command)
            if command.journal then game.journal[#game.journal + 1] = -command.journal.amount end
            if command.proposal then game.sent[#game.sent + 1] = command.proposal end
        end,
    },
    util = {getDefaultYearDuration = function() return 12 * support.MONTH end},
}

support.core = require(MOD_PREFIX .. "industry_upgrades/core.lua")

-- A fresh game script with an empty saved state, as after loading a savegame.
function support.loadScript(saved)
    dofile(support.CONTENT .. "industry_upgrades/upgrades.script.lua")
    local script = data()
    local stateHolder = {saved = saved}
    local state = {
        get = function() return stateHolder.saved end,
        set = function(_self, root) stateHolder.saved = root end,
        subscribeToEvent = function() end,
    }
    return script, state, stateHolder
end

function support.tick(script, state, ms)
    game.gameTime.gameTime = game.gameTime.gameTime + ms
    script.update(nil, state, 1)
end

function support.count(pattern)
    local count = 0
    for _index, line in ipairs(game.logged) do
        if line:find(pattern) then count = count + 1 end
    end
    return count
end

local failures = 0
function support.check(name, got, want)
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
    end
end

function support.finish(testName)
    if failures > 0 then
        print(testName .. ": " .. failures .. " check(s) failed")
        os.exit(1)
    end
    print(testName .. ": all checks passed")
end

return support
