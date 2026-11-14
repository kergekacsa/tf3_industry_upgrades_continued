local ssu = require "::/gui/main/stylesheetutil.lua"

-- The delivery bar (ui.orderBar) in the look of the base game's production bar.
-- The base game scopes these rules to its own recipes (gui/entity_window/industry_react_util.css.lua
-- and entity_window.css.lua: R::ProductionRuleWidget, R::RuleProgressBar), so they are repeated here
-- for our classes.
function data()
    local result = {}
    local a = ssu.makeAdder(result)

    local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data

    a("!industry-upgrades-order FloatingLayout", {
        gravity = { -1, -1 },
    })

    a("!industry-upgrades-order FloatingLayout BoxLayout", {
        gravity = { 0.5, 0 },
    })

    a([[!industry-upgrades-order-background,
        !industry-upgrades-order-foreground]], {
        margin = { 13, 0, 0, 0 },
        minSize = { -1, 20 }, -- either 0 or at least 20 wide and 20 tall
    })

    a("!industry-upgrades-order-background", {
        gravity = { -1, 0 },
        borderImage = {
            fileName = "::/gui/entity_window/design/production_rule_background_surface.tga",
            horizontal = { 0, 8, 12, 20 },
            vertical = { 0, 10, 10, 20 }
        },
        borderColor = colorDefault.BaseVeryDark,
    })

    a("!industry-upgrades-order-foreground", {
        gravity = { 0, 0 },
        backgroundImage1 = { fileName = "::/gui/entity_window/design/gradient_black_white.tga" },
        backgroundColor1 = colorDefault.AccentDark,
        backgroundColor = colorDefault.AccentVeryLight,
        mask = {
            fileName = "::/gui/entity_window/design/production_rule_foreground_mask.tga",
            horizontal = { 0, 9, 11, 20 },
            vertical = { 0, 10, 10, 20 }
        },
    })

    a("!industry-upgrades-order-item BoxLayout", {
        innerSpacing = { 0, 0 },
    })

    -- what the stock holds, centred under the cargo icon
    a("!industry-upgrades-order-item BoxLayout > TextView", {
        gravity = { 0.5, 0 },
    })

    -- the cycle of the order's rule (the base game's RuleProgressBar), a line like the one under a
    -- landmark's bar
    a("!industry-upgrades-order-cycle", {
        gravity = { -1, 0 },
        size = { -1, 6 },
    })

    a("!industry-upgrades-order-cycle R::RuleProgressBar", {
        gravity = { -1, 0 },
    })

    a("!industry-upgrades-order-cycle R::ProgressDisplay", {
        size = { -1, 20 },
    })

    a("!industry-upgrades-order-cycle R::ProgressDisplay ProgressBar", {
        gravity = { -1, 0 },
        size = { -1, -1 },
        color = colorDefault.NeutralLightest,
        backgroundColor1 = colorDefault.BaseLight,
    })

    -- a cycle that takes longer because cargo arrives late (RuleProgressBar sets the class)
    a("!industry-upgrades-order-cycle !slowdown R::ProgressDisplay ProgressBar", {
        color = colorDefault.Warning,
    })

    -- the whole order like the bar of a landmark's notification
    -- (game_mechanics/notifications/gui/notifications.css.lua: R::NotificationWidgetEntry ProgressBar),
    -- icons and amounts laid over it
    a("!industry-upgrades-order-total", {
        gravity = { -1, 0 },
        margin = { 4, 0, 0, 0 },
    })

    a("!industry-upgrades-order-total ProgressBar", {
        gravity = { -1, 0 },
        size = { -1, 22 },
        color = colorDefault.AccentMedium,
        backgroundColor1 = colorDefault.BaseVeryDark,
    })

    a("!industry-upgrades-order-total-content", {
        gravity = { 0.5, 0.5 },
    })

    a("!industry-upgrades-order-total-content BoxLayout", {
        gravity = { 0.5, 0.5 },
        innerSpacing = { 4, 0 },
    })

    a("!industry-upgrades-order-total-content ImageView", {
        size = { 16, 16 },
        gravity = { 0, 0.5 },
    })

    a("!industry-upgrades-order-total-content TextView", {
        gravity = { 0, 0.5 },
        color = colorDefault.NeutralLightest,
    })

    -- "Production −25% until complete" with its icon as small as the annotation
    a("!industry-upgrades-order-malus BoxLayout", {
        innerSpacing = { 4, 0 },
    })

    a("!industry-upgrades-order-malus ImageView", {
        size = { 16, 16 },
        gravity = { 0, 0.5 },
    })

    a("!industry-upgrades-order-malus TextView", {
        gravity = { 0, 0.5 },
    })

    a("!font-small !industry-upgrades-order-total ProgressBar", {
        size = { -1, 18 },
    })

    a("!font-medium !industry-upgrades-order-total ProgressBar", {
        size = { -1, 22 },
    })

    a("!font-large !industry-upgrades-order-total ProgressBar", {
        size = { -1, 26 },
    })

    return result
end
