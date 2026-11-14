-- Compact "Upgrades" card inside the industry tab. Only shown when the industry window has no own
-- "Upgrades" tab (setting "Card in the Industry tab", or another mod owns the window script).
local ui = require "stardorn_industry_upgrades::/industry_upgrades/ui.lua"
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engineReact = ug_require "::/gui/main/engine_react_util.tl"
local contentCard = ug_require "::/gui/main/content_card.tl"
local industryEow = ug_require "::/gui/entity_window/industry/industry_eow.script.tl"

local CARD_KEY = "industryUpgrades"

local function heading(value)
    return builtin.TextView{meta = {class = "font-scale-body"}, text = value}
end

local function body(s)
    local children = {}
    if s.refused then
        children[#children + 1] = heading(ui.tr("Rebuild refused"))
        for _node, node in ipairs(ui.refusedSection(s)) do children[#children + 1] = node end
    end
    -- points when upgrades cost points, the plan when they cost deliveries; the open
    -- order in both (one opened before a switch to EXP points runs on and can be cancelled)
    if ui.anyPointUpgrades() then children[#children + 1] = ui.pointsSummary(s) end
    if s.order then
        children[#children + 1] = heading(ui.orderTitle(s))
        for _node, node in ipairs(ui.orderSection(s)) do children[#children + 1] = node end
    end
    if not ui.anyPointUpgrades() then
        children[#children + 1] = heading(ui.tr("Upgrade plan"))
        for _node, node in ipairs(ui.planSection(s)) do children[#children + 1] = node end
    end
    children[#children + 1] = ui.upkeepRow(s)
    for _index, id in ipairs(ui.availableUpgrades(s)) do
        children[#children + 1] = builtin.TextView{meta = {class = "font-scale-body"}, text = ui.upgradeName(id)}
        for _node, node in ipairs(ui.upgradeSection(s, id)) do children[#children + 1] = node end
    end
    return ui.vertical(children)
end

-- a recipe must return a layout, never a widget ("Recipe child must be a layout"); conditionRow is one
local PointDetails = react.RegisterRecipe("IndustryUpgradesPointDetails", function(params)
    return ui.vertical({ui.conditionRow(params.snapshot.last, params.snapshot.workers)})
end)

local UpgradesPlugin = react.RegisterPluginRecipe(industryEow.IndustryEowExtensionPoint, "IndustryUpgradesPlugin", function(params)
    local state = engineReact.useStepState(function() return ui.snapshot(params.entityId) end, nil, ui.sameSnapshot)
    local s = state:old()
    local cardNode = contentCard.ContentCard{
        meta = {localKey = CARD_KEY},
        title = ui.title(s),
        initialCalloutTextPermanent = "",
        extraChildrenPermanent = {
            builtin.Component{layout = s and body(s) or builtin.TextView{text = ui.tr("This industry cannot be upgraded.")}},
        },
        initialCalloutTextCollapsible = "",
        recipeAndParamCollapsible = (s and s.last and ui.anyPointUpgrades()) and contentCard.makeRecipeAndParam(PointDetails, {snapshot = s}) or nil,
        setCollapsibleExpanded = function(value) if params.setCollapsibleExpanded then params.setCollapsibleExpanded(CARD_KEY, value) end end,
        collapsibleExpanded = params.getCollapsibleExpanded and params.getCollapsibleExpanded(CARD_KEY) or false,
        gameCtx = params.gameCtx,
        showOnRightSide = params.showCalloutOnRightSide,
    }
    -- the "?" at the end of the card's heading
    return builtin.BoxLayout{child = s and ui.withHelp(cardNode, params.gameCtx) or cardNode}
end)

local function condition(params)
    if params.ownershipState == "Foreign" then return false end
    local _constructionId, construction = ui.constructionOf(params.entityId)
    return construction ~= nil and ui.supported(construction) and not ui.usesTab(construction)
end

function data()
    return {UpgradesPlugin = UpgradesPlugin, condition = condition, body = body}
end
