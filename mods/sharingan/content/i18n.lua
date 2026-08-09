local I18N = {}

local TRANSLATIONS = {
    en = {
        room = {
            treasure = "Treasure",
            shop = "Shop",
            arcade = "Arcade",
            devil = "Devil",
            angel = "Angel",
            library = "Library",
            challenge = "Challenge",
            curse = "Curse",
            sacrifice = "Sacrifice",
            vault = "Vault",
            dice = "Dice",
            planetarium = "Planetarium",
            cleanBedroom = "Clean Bed",
            dirtyBedroom = "Dirty Bed",
            crawlSpace = "Crawl Space",
            blackMarket = "Black Market",
            secret = "Secret",
            superSecret = "Super Secret",
            ultraSecret = "Ultra Secret",
            bossRush = "Boss Rush",
        },
        map = {
            title = "SHARINGAN  |  FLOOR MAP",
            visited = "Gray room = already visited",
            warning = "Game is not paused.",
        },
    },
    zh = {
        room = {
            treasure = "宝箱房",
            shop = "商店",
            arcade = "游戏厅",
            devil = "恶魔房",
            angel = "天使房",
            library = "图书馆",
            challenge = "挑战房",
            curse = "诅咒房",
            sacrifice = "献祭房",
            vault = "金库",
            dice = "骰子房",
            planetarium = "星象房",
            cleanBedroom = "干净卧室",
            dirtyBedroom = "肮脏卧室",
            crawlSpace = "夹层",
            blackMarket = "黑市",
            secret = "隐藏房",
            superSecret = "超级隐藏房",
            ultraSecret = "究极隐藏房",
            bossRush = "Boss Rush",
        },
        map = {
            title = "写轮眼  |  楼层地图",
            visited = "灰色房间 = 已访问",
            warning = "游戏不会暂停。",
        },
    },
}

local function lookup(language, key)
    local value = TRANSLATIONS[language]
    for part in string.gmatch(key, "[^.]+") do
        if type(value) ~= "table" then return nil end
        value = value[part]
    end
    return value
end

function I18N.GetLanguage()
    -- Isaac's public Font API does not reliably expose the active Chinese
    -- glyph atlas to ordinary Lua mods. Keep the HUD readable and deterministic.
    return "en"
end

function I18N.Get(key)
    local value = lookup(I18N.GetLanguage(), key)
    if value == nil then value = lookup("en", key) end
    return value or key
end

return I18N
