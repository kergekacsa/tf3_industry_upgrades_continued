local color_util = require "::/gui/main/color_util.tl"
local ssu = require "::/gui/main/stylesheetutil.lua"

-- The help window (ui.HelpWindow) and its "?" button (ui.withHelp). Text wraps at a fixed width that
-- grows with the game's font size, as in the base game's context help
-- (gui/context_helper/context_helper.css.lua). The base game's info hint is scoped to its own
-- component (gui/main/content_card.css.lua, content_card.makeInfoHint) and has a fixed width, so its
-- look is repeated here for our class.
function data()
    local result = {}
    local a = ssu.makeAdder(result)

    local colorDefault = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
    local transparency = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data

    local ICON, GAP, HINT_ICON = 26, 10, 24

    -- page width = banner width (4:1) = width of a paragraph
    local function widths(prefix, page)
        local function width(value) return { minSize = { value, -1 }, maxSize = { value, -1 } } end
        a(prefix .. "!industry-upgrades-help-banner", { size = { page, page / 4 } })
        a(prefix .. "!industry-upgrades-help-text", width(page))
        a(prefix .. "!industry-upgrades-help-row-name", width(page - ICON - GAP))
        a(prefix .. "!industry-upgrades-help-row-text", width(page - ICON - GAP))
        a(prefix .. "!industry-upgrades-help-hint-text", width(page - HINT_ICON - 16 - 16))
        a(prefix .. "!industry-upgrades-help-footer-text", width(page - 22 - GAP))
    end
    widths("", 520)
    widths("!font-medium ", 600)
    widths("!font-large ", 660)

    a("!industry-upgrades-help-page", {
        padding = { 10, 12, 12, 12 },
    })

    a("!industry-upgrades-help-banner", {
        margin = { 0, 0, 10, 0 },
    })

    a([[!industry-upgrades-help-text,
        !industry-upgrades-help-row-name,
        !industry-upgrades-help-row-text,
        !industry-upgrades-help-hint-text,
        !industry-upgrades-help-footer-text]], {
        textAutoWrap = true,
    })

    a("!industry-upgrades-help-text", {
        margin = { 0, 0, 8, 0 },
    })

    a("!industry-upgrades-help-row", {
        margin = { 4, 0, 6, 0 },
    })

    a("!industry-upgrades-help-row-icon", {
        size = { ICON, ICON },
        margin = { 0, GAP, 0, 0 },
        gravity = { 0, 0 },
    })

    a("!industry-upgrades-help-row-name", {
        fontWeight = "Bold",
    })

    a("!industry-upgrades-help-hint", {
        backgroundImage1 = {
            fileName = "::/gui/entity_window/design/card_surface.tga",
            horizontal = { 0, 6, 26, 32 },
            vertical = { 0, 6, 26, 32 }
        },
        backgroundColor1 = color_util.withTransparencyRaw(colorDefault.Info, transparency.High),
        padding = { 4, 4, 4, 4 },
        margin = { 2, 0, 4, 0 },
    })

    a("!industry-upgrades-help-hint-icon", {
        size = { HINT_ICON, HINT_ICON },
        backgroundImage1 = { fileName = "::/gui/entity_window/design/symbol_info.tga", },
        backgroundColor1 = colorDefault.Info,
        margin = { 4, 4, 4, 4 },
    })

    a("!industry-upgrades-help-hint-text", {
        padding = { 0, 4, 0, 4 },
    })

    -- what this game does not use: dimmed like the base game's disabled construction items
    -- (gui/construction/construction.css.lua)
    a("!industry-upgrades-help-off", {
        color = colorDefault.NeutralMedium,
    })

    a("!industry-upgrades-help-footer", {
        padding = { 8, 12, 10, 12 },
    })

    a("!industry-upgrades-help-footer-icon", {
        size = { 22, 22 },
        margin = { 0, GAP, 0, 0 },
        gravity = { 0, 0 },
    })

    -- the "?" over the end of the first card's heading line
    a("!industry-upgrades-with-help", {
        gravity = { -1, 0 },
    })

    a("!industry-upgrades-with-help FloatingLayout", {
        gravity = { -1, -1 },
    })

    a("!industry-upgrades-help-button", {
        margin = { 2, 2, 0, 0 },
    })

    return result
end
