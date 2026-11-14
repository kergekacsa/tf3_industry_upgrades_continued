-- Industry window with an own "Upgrades" tab next to "Industry" (and the station tabs), built the
-- same way as the base game's pollution cleanup facility: an entityWindowScript that returns the
-- ConstructionWindow with a custom tab. The other tabs come from the subconstructions as usual.
local ui = require "stardorn_industry_upgrades::/industry_upgrades/ui.lua"
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engineReact = ug_require "::/gui/main/engine_react_util.tl"
local contentCard = ug_require "::/gui/main/content_card.tl"
local entityWindowUtil = ug_require "::/gui/entity_window/entity_window_util.tl"
local makeEntityWindow = ug_require "::/gui/entity_window/make_entity_window.tl"

-- Right after "Industry" (6000), before the stations (11000+).
local TAB_SORT_KEY = 6001

local function card(key, title, children, param)
    return contentCard.ContentCard{
        meta = {localKey = key},
        title = title,
        initialCalloutTextPermanent = "",
        extraChildrenPermanent = {builtin.Component{layout = ui.vertical(children)}},
        gameCtx = param.gameCtx,
        showOnRightSide = false,
    }
end

local function pointsCard(s, param)
    local children = {ui.pointsSummary(s)}
    if s.last then children[#children + 1] = ui.conditionRow(s.last, s.workers) end
    children[#children + 1] = ui.upkeepRow(s)
    return card("industryUpgradesPoints", ui.tr("Upgrade points"), children, param)
end

local function planCard(s, param)
    local children = ui.planSection(s)
    children[#children + 1] = ui.upkeepRow(s)
    return card("industryUpgradesPlan", ui.tr("Upgrade plan"), children, param)
end

-- One card per upgrade that changes anything at this industry.
local function upgradeCards(s, param)
    local cards = {}
    for _index, id in ipairs(ui.availableUpgrades(s)) do
        cards[#cards + 1] = card("industryUpgrades_" .. id, ui.upgradeName(id), ui.upgradeSection(s, id), param)
    end
    return cards
end

local UpgradesTab = react.RegisterRecipe("IndustryUpgradesTab", function(param)
    local industry = ui.industryOf(param.keyEntity)
    local state = engineReact.useStepState(function() return industry and ui.snapshot(industry) or nil end, nil, ui.sameSnapshot)
    local s = state:old()
    -- Only create the nodes that end up in the tree: the game logs a warning on every frame for each
    -- node a render creates but leaves out.
    local widgets
    if s then
        -- points when upgrades cost points, the plan when they cost deliveries. The open
        -- order shows in both: one opened before a switch to EXP points runs on and can be cancelled.
        widgets = {}
        if ui.anyPointUpgrades() then widgets[#widgets + 1] = pointsCard(s, param) end
        if s.order then widgets[#widgets + 1] = card("industryUpgradesOrder", ui.orderTitle(s), ui.orderSection(s), param) end
        if not ui.anyPointUpgrades() then widgets[#widgets + 1] = planCard(s, param) end
        for _index, upgradeCard in ipairs(upgradeCards(s, param)) do widgets[#widgets + 1] = upgradeCard end
        -- the "?" at the end of the first card's heading
        if widgets[1] then widgets[1] = ui.withHelp(widgets[1], param.gameCtx) end
    else
        widgets = {builtin.TextView{text = ui.tr("This industry cannot be upgraded.")}}
    end
    return ui.vertical({entityWindowUtil.ContentWidgetScrollContainer(widgets, false)})
end)

local function entityWindowFn(_captureParams, entity, tag, gameCtx, isMapEditor, isSandboxMode, setActionFnAndProxy, closeConditionAndProxy)
    closeConditionAndProxy = closeConditionAndProxy or {nil, nil}
    local actionFnAndProxy = makeEntityWindow.makeSetActionFnWithCombinedKey(makeEntityWindow.ConstructionWindow, setActionFnAndProxy)
    local customTabs = {{
        entity = entity,
        name = ui.tr("Upgrades"),
        description = ui.tr("Upgrades"),
        subconstructionIndex = -1,
        sortKey = TAB_SORT_KEY,
        customTabData = {
            recipe = UpgradesTab,
            param = {meta = {tag = tag .. "upgrades"}, keyEntity = entity, gameCtx = gameCtx,
                isMapEditor = isMapEditor, isSandboxMode = isSandboxMode},
            autoCloseCondition = closeConditionAndProxy[1],
            autoCloseCondition_compareProxy = closeConditionAndProxy[2],
            fallbackTitle = ui.tr("Upgrades"),
        },
    }}
    return {
        recipe = makeEntityWindow.ConstructionWindow,
        param = {
            meta = {tag = tag .. "con"},
            keyEntity = entity,
            gameCtx = gameCtx,
            isMapEditor = isMapEditor,
            isSandboxMode = isSandboxMode,
            setActionFn = actionFnAndProxy.fn,
            setActionFn_compareProxy = actionFnAndProxy.proxy,
            customTabs = customTabs,
        },
        fallbackTitle = ui.tr("Industry"),
        replacedEntity = entity,
        autoCloseCondition = closeConditionAndProxy[1],
        autoCloseCondition_compareProxy = closeConditionAndProxy[2],
    }
end

function data()
    return {entityWindowFn = entityWindowFn, UpgradesTab = UpgradesTab}
end
