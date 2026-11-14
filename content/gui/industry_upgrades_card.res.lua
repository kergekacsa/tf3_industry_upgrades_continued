function data()
    return {
        type = "react-plugin ::IndustryEowExtensionPoint",
        data = {
            filePath = "stardorn_industry_upgrades::/industry_upgrades/card.script@UpgradesPlugin",
            condition = "stardorn_industry_upgrades::/industry_upgrades/card.script@condition",
            order = 25, -- after the boosters (20), before the stocks (30)
        },
    }
end
