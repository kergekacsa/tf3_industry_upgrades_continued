-- Report 4: an efficiency level must not make a production cycle (its lot) more than MAX_RECIPE_SCALE
-- times the base game's, a higher level never needs more input, and the preview of the next level
-- matches what its rebuild builds.
-- Run from the mod folder: lua55 tests/efficiency_test.lua

local support = dofile("tests/support.lua")
local core, check = support.core, support.check

local STEPS = {0.01, 0.02, 0.05, 0.1}
local MAX_INPUT = 10
local RECIPES = {{4}, {7, 4}, {6, 6}, {1}, {3, 2, 1}}

-- A rule built at an efficiency level from base inputs: the built rule, its recipe scale, and the scale
-- the construction's metadata records for it (nil without a saving).
local function build(inputs, level)
    local rule = {input = {inputs}, output = {product = 2}, consumptionFactor = 1}
    local result = {subconstructions = {{industry = true, rules = {rule}, stocks = {}}}}
    local params = {}
    core.setLevel(params, "efficiency", level)
    core.applyUpgrades(result, params)
    local built = result.subconstructions[1].rules[1]
    local recorded = result.metadata and result.metadata[core.RECIPE_SCALE_META .. 1]
    return built, math.floor(1 / built.consumptionFactor + 0.5), recorded
end

for _index, step in ipairs(STEPS) do
    core.configure({EFFICIENCY_STEP = step, EFFICIENCY_LEVELS = 50})
    local maxLevel = core.UPGRADE_BY_ID.efficiency.max
    local name = math.floor(step * 100 + 0.5) .. " %"

    -- every input alone: lot cap and no level needs more than the one before
    for amount = 1, MAX_INPUT do
        local previous = amount
        for level = 1, maxLevel do
            local built, scale = build({amount}, level)
            local input = built.input[1][1]
            check(name .. ", input " .. amount .. ", level " .. level .. ": scale at most " .. core.MAX_RECIPE_SCALE,
                scale <= core.MAX_RECIPE_SCALE, true)
            check(name .. ", input " .. amount .. ", level " .. level .. ": input per base cycle not above the level before",
                input / scale <= previous + 1e-9, true)
            previous = input / scale
        end
    end

    -- recipes: the recorded scale is the one built, and the preview's ratio is the change the rebuild makes
    for _recipe, inputs in ipairs(RECIPES) do
        for level = 0, maxLevel - 1 do
            local built, scale, recorded = build(inputs, level)
            check(string.format("%s, recipe %s, level %d: recorded scale", name, table.concat(inputs, "+"), level),
                recorded or 1, scale)
            local next, nextScale = build(inputs, level + 1)
            for index = 1, #inputs do
                local want = (next.input[1][index] / nextScale) / (built.input[1][index] / scale)
                local got = core.efficiencyRatio(built, index, level, level + 1, recorded)
                check(string.format("%s, recipe %s, input %d, level %d -> %d: preview ratio", name, table.concat(inputs, "+"),
                    index, level, level + 1), math.abs(got - want) < 1e-9, true)
            end
        end
    end
end

-- the reported case: a saw mill with 4 per cycle at -2 % x 2 built 77 per cycle
core.configure({EFFICIENCY_STEP = 0.02, EFFICIENCY_LEVELS = 25})
local sawMill = build({4}, 2)
check("saw mill 4 at -2 % x 2: input per cycle", sawMill.input[1][1], 19)

support.finish("efficiency_test")
