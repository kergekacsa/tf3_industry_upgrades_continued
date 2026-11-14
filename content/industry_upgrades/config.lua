-- Balancing defaults. Most of them can be changed in the mod settings (see settings.lua); the chosen
-- values replace these through core.configure in every part of the mod.
return {
    -- Throughput upgrade: every level adds this fraction of the base throughput (0.125 = +12.5 %).
    THROUGHPUT_STEP = 0.125,
    MAX_LEVEL = 10,

    -- The other upgrades: levels and effect per level.
    OTHER_MAX_LEVEL = 5,
    STORAGE_STEP = 0.5,       -- stocks x (1 + 0.5 * level)
    EFFICIENCY_STEP = 0.1,    -- input consumption x (1 - 0.1 * level), rounded to the recipe (core.recipeScale)
    EFFICIENCY_LEVELS = 5,    -- efficiency levels that can be bought, as far as EFFICIENCY_MIN allows
    EFFICIENCY_MIN = 0.5,     -- input never drops below half (5 x 10 %, the most before the setting)
    BOOSTER_STEP = 0.25,      -- booster effect x (1 + 0.25 * level)
    BOOSTER_DEMAND = 0,       -- booster cargo per cycle x (1 + BOOSTER_DEMAND * booster strength level); 0 = off
    EMISSION_STEP = 0.15,     -- noise and pollution x (1 - 0.15 * level)
    WORKER_BOOST_STEP = 0.25, -- worker boost factor + 0.25 * level
    WORKERS_NEEDED = 0,       -- workplaces x (1 + WORKERS_NEEDED * worker boost level); 0 = off

    -- Buying level n costs COST_BASE + COST_STEP * (n - 1) points (default: 1 point per level).
    COST_BASE = 1,
    COST_STEP = 0,

    -- Upkeep (setting "Upkeep per level", both modes): every built level costs UPKEEP_BASE money a month,
    -- x the base game's inflation (x1 up to 1900, x4 from 2000, like its subsidies). With UPKEEP_RISING
    -- level n of an upgrade costs n x UPKEEP_BASE, so 3 levels cost 1 + 2 + 3 = 6 x. Charged once a
    -- calendar month, in the finances under General, Upkeep Other. 0 = no upkeep.
    UPKEEP_BASE = 0,
    UPKEEP_RISING = 0,

    -- Experience: every calendar month, each condition met gives +1 EXP: production rating (industries
    -- that process inputs, unless PRIMARY_PRODUCTION) and shipped share at or above the thresholds
    -- below, worker boost active, booster active (industries with boosters). A threshold or switch of
    -- 0 turns the condition off. EXP_PER_POINT EXP turn into 1 upgrade point.
    EXP_PER_POINT = 12,
    -- 1: only 1 EXP a month, and only when every condition switched on is met.
    EXP_ALL_CONDITIONS = 0,
    PRODUCTION_THRESHOLD = 0.75, -- production rating
    PRIMARY_PRODUCTION = 0,      -- 1: raw material producers (no inputs) get production EXP as well
    SHIPPED_THRESHOLD = 0.75,    -- shipped share of the output
    -- How the shipped share counts at industries with several products (farm: grain and vegetables):
    -- 0 = all products together, 1 = the best product, 2 = both, +1 EXP each.
    SHIPPED_MODE = 1,
    WORKERS_CONDITION = 1,       -- worker boost active
    BOOSTER_CONDITION = 1,       -- booster active

    -- What the upgrades cost (setting "Upgrade costs", chosen per game): 0 = EXP points, 1 = deliveries
    -- (below). EXP points by default, so savegames from before the deliveries keep their points system.
    DELIVERY_MODE = 0,

    -- Delivery mode: every upgrade costs a delivery to the industry instead of points. Levels are
    -- planned first; starting the plan opens one delivery order for all of them, the industry gets an
    -- extra input stock per cargo and uses the cargo up bit by bit (ORDER_RULE); once all of it is used,
    -- the levels are built.
    -- One level of an upgrade costs every tier whose levels hold it, x RESOURCE_SHARE (setting
    -- "Delivery amounts") x the upgrade's RESOURCE_WEIGHTS. The tiers form a ladder of LADDER_LEVELS
    -- steps; an upgrade's levels are spread over it by their share of its maximum (core.ladderLevel:
    -- throughput 1..10 is the ladder itself, the five levels of the others are steps 2, 4, 6, 8, 10),
    -- so the last level of every upgrade needs the top cargo. At most three cargos on every step; with
    -- higher steps cargos are swapped for more advanced ones, so the world's progress paces the
    -- upgrades: a step needs its cargo produced somewhere on the map.
    --   step 1-2   planks
    --   step 3-4   planks, the economy's material
    --   step 5-6   planks, the economy's material, tools
    --   step 7-8   steel (instead of planks), the economy's material, tools
    --   step 9-10  steel, glass (instead of the material), machines (instead of tools)
    -- Planks, bricks and cement come from industries of tier 0, on the map from the start; tools,
    -- steel, glass and machines from tier 1 industries that come later (glass works only with the
    -- towns' furniture demand, machines need steel and plastic). Every amount is a multiple of 100, so
    -- with the weights (1, 0.8, 0.6) every amount an order sums is a multiple of 20: its lots stay
    -- small and its cycles many (core.orderLots divides by the greatest common divisor), so the minimum
    -- duration holds. Amounts by what a plant makes a year: planks 300 (saw mill 730), tools 200 (tool
    -- factory 608), steel 200 (steel mill 365), glass 100 (glass works 365), machines 100 (machine
    -- factory 319).
    LADDER_LEVELS = 10,
    RESOURCE_TIERS = {
        {level = 1, untilLevel = 6, cargo = "::/cargos/planks/planks.cargo", amount = 300},
        {level = 3, untilLevel = 8, material = true}, -- the economy's material, see ECONOMY_MATERIAL
        {level = 5, untilLevel = 8, cargo = "::/cargos/tools/tools.cargo", amount = 200},
        {level = 7, cargo = "::/cargos/steel/steel.cargo", amount = 200},
        {level = 9, cargo = "::/cargos/glass/glass.cargo", amount = 100},
        {level = 9, cargo = "::/cargos/machines/machines.cargo", amount = 100},
    },
    -- The game's economy (its file name: "temperate", "dry", "subarctic", "tropic", "all"; "" unknown),
    -- read from the game settings when the game is loaded. Economies with a building material of their
    -- own that towns ask for from the start ask for it as their material: brickworks 730 bricks a year
    -- (temperate, dry), cement plant 365 cement (subarctic); both are tier 0 industries, placed from the
    -- start. Any other economy (tropic, all with a tropical climate, those of other mods) asks for
    -- MATERIAL: plastic (chemical plant 608 a year), in every economy, and three town demands need
    -- chemical plants (tools, machines, clothes through dyes). Tropic has no tier 0 building material
    -- besides planks (no quarries either).
    ECONOMY = "",
    MATERIAL = {cargo = "::/cargos/plastic/plastic.cargo", amount = 200},
    ECONOMY_MATERIAL = {
        temperate = {cargo = "::/cargos/bricks/bricks.cargo", amount = 200},
        dry = {cargo = "::/cargos/bricks/bricks.cargo", amount = 200},
        subarctic = {cargo = "::/cargos/cement/cement.cargo", amount = 100},
    },
    -- Upgrades that raise production cost the full amounts, the others less.
    RESOURCE_WEIGHTS = {throughput = 1, efficiency = 1, booster = 0.8, workers = 0.8, storage = 0.6, emission = 0.6},
    -- Replaces a pool cargo the industry already uses or produces: the first free one of its list (not
    -- one of the pool, nor one another cargo of the industry got). All of them exist in every economy.
    -- factor scales the amounts by what a base game plant makes of the replacement per year against
    -- the original (saw mill 730 planks, chemical plant 608 plastic, brickworks 730 bricks, cement
    -- plant 365 cement, tool factory 608 tools, steel mill 365 steel and 487 sheet metal, glass works
    -- 365 glass, machine factory 319 machines, refinery 365 fuel, forest 243 logs), at most 1: a
    -- replacement never costs more than the original. Rounded so the replaced amounts stay multiples
    -- of 50 or 100.
    RESOURCE_FALLBACK = {
        ["::/cargos/planks/planks.cargo"] = { -- saw mill, furniture factory, tool factory
            {cargo = "::/cargos/fuel/fuel.cargo", factor = 0.5},
            {cargo = "::/cargos/sheet_metal/sheet_metal.cargo", factor = 2 / 3},
            {cargo = "::/cargos/logs/logs.cargo", factor = 1 / 3},
        },
        ["::/cargos/plastic/plastic.cargo"] = { -- chemical plant, tool factory, machine factory
            {cargo = "::/cargos/fuel/fuel.cargo", factor = 0.5},
            {cargo = "::/cargos/sheet_metal/sheet_metal.cargo", factor = 1},
            {cargo = "::/cargos/logs/logs.cargo", factor = 0.5},
        },
        ["::/cargos/bricks/bricks.cargo"] = { -- brickworks
            {cargo = "::/cargos/fuel/fuel.cargo", factor = 0.5},
            {cargo = "::/cargos/sheet_metal/sheet_metal.cargo", factor = 0.5},
        },
        ["::/cargos/cement/cement.cargo"] = { -- cement plant
            {cargo = "::/cargos/fuel/fuel.cargo", factor = 1},
            {cargo = "::/cargos/sheet_metal/sheet_metal.cargo", factor = 1},
        },
        ["::/cargos/tools/tools.cargo"] = { -- tool factory, mines, quarry, clay and sand pits, fishing
            {cargo = "::/cargos/fuel/fuel.cargo", factor = 0.5},
            {cargo = "::/cargos/sheet_metal/sheet_metal.cargo", factor = 1},
            {cargo = "::/cargos/logs/logs.cargo", factor = 0.5},
        },
        ["::/cargos/steel/steel.cargo"] = { -- steel mill, machine factory
            {cargo = "::/cargos/sheet_metal/sheet_metal.cargo", factor = 1},
            {cargo = "::/cargos/fuel/fuel.cargo", factor = 1},
            {cargo = "::/cargos/logs/logs.cargo", factor = 0.5},
        },
        ["::/cargos/glass/glass.cargo"] = { -- glass works, furniture factory, brewery
            {cargo = "::/cargos/fuel/fuel.cargo", factor = 1},
            {cargo = "::/cargos/sheet_metal/sheet_metal.cargo", factor = 1},
            {cargo = "::/cargos/logs/logs.cargo", factor = 0.5},
        },
        ["::/cargos/machines/machines.cargo"] = { -- machine factory, vehicle factory, forest, iron ore mine, oil, sand excavator
            {cargo = "::/cargos/sheet_metal/sheet_metal.cargo", factor = 1},
            {cargo = "::/cargos/fuel/fuel.cargo", factor = 1},
            {cargo = "::/cargos/logs/logs.cargo", factor = 1},
        },
    },
    RESOURCE_SHARE = 1,
    -- Shortest time a level takes in years (setting "Minimum duration per level"): an order's rule
    -- consumes the whole amount at this pace however fast the cargo arrives (the order's stocks hold
    -- the whole amount).
    RESOURCE_YEARS = 1,
    -- Every further level of the same order adds only this share of RESOURCE_YEARS (3 levels: 2 years).
    BUNDLE_SHARE = 0.5,
    -- Production of the industry while an order is open: x (1 - ORDER_MALUS) (setting "Production
    -- malus during a delivery").
    ORDER_MALUS = 0.25,
    -- The rule that consumes an order's cargo (core.addOrder). "booster": a booster without effect worth
    -- mentioning; it runs alongside the production and holds the minimum duration by its rate, but the
    -- engine starts its cycles only while the industry produces (verified 2026-10-11), so a processing
    -- industry without its own inputs pauses its order. "plain": a rule without output like a landmark's
    -- construction site, tried 2026-10-11 and set aside (Phillip: the booster's behaviour can at least
    -- be explained): it runs without production, but an industry runs one plain rule at a time, so it
    -- takes turns with the production (short cycles, steps fitted to the production, minimum duration
    -- in the game script; see the README). Changing it rebuilds open orders in the other shape
    -- (core.ORDER_FORMAT).
    ORDER_RULE = "booster",
}
