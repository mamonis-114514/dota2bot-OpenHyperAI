-- draft_lib.lua
-- Phase 3: enemy draft profiling + conditional item-build adaptation.
--
-- The profile is built once per game from GetSelectedHeroName (available at
-- game start, before creeps spawn) and is deterministic, so every bot sandbox
-- reaches the same conclusion. AdjustBuyList applies at most 3 changes to a
-- hero's role buy list; the hero file remains the source of truth otherwise.

local draft_lib = {}

-- ---------------------------------------------------------------------------
-- Hero classification tables (hero short name -> true)
-- Short names = GetSelectedHeroName with the 'npc_dota_hero_' prefix removed.
-- ---------------------------------------------------------------------------
local INVIS = {
	bounty_hunter = true, riki = true, clinkz = true, nyx_assassin = true,
	mirana = true, phantom_assassin = true, invoker = true, weaver = true,
	treant = true, dark_willow = true,
	slark = true, -- shadow dance
	invoker = true, -- ghost walk (shard)
}

local HEAVY_HEAL = {
	necrolyte = true, witch_doctor = true, omniknight = true, huskar = true,
	abaddon = true, dazzle = true, oracle = true, winter_wyvern = true,
	chen = true, enchantress = true, wisp = true, alchemist = true,
}

local ILLUSION = {
	phantom_lancer = true, naga_siren = true, terrorblade = true,
	chaos_knight = true, morphling = true, arc_warden = true,
}

local CHANNEL_ULT = {
	crystal_maiden = true, enigma = true, witch_doctor = true,
	shadow_shaman = true, death_prophet = true, tinker = true,
	bane = true, ancient_apparition = true, jakiro = true, pit_lord = true,
	abyssal_underlord = true,
}

local HARD_ENGAGE = {
	magnataur = true, earthshaker = true, enigma = true, tidehunter = true,
	legion_commander = true, axe = true, batrider = true, sand_king = true,
	slardar = true, centaur = true, primal_beast = true, mars = true,
	faceless_void = true, phoenix = true, brewmaster = true, treant = true,
	puck = true, undying = true, spirit_breaker = true, doom_bringer = true,
}

local EVASION = {
	phantom_assassin = true, brewmaster = true, windrunner = true,
}

local SUMMONS = {
	lone_druid = true, broodmother = true, visage = true, beastmaster = true,
	warlock = true, lycan = true, chen = true, enchantress = true,
	venomancer = true, shadow_shaman = true,
}

-- ---------------------------------------------------------------------------
-- Profile
-- ---------------------------------------------------------------------------
local cachedProfile = nil

function draft_lib.GetEnemyProfile()
	if cachedProfile ~= nil then return cachedProfile end

	local profile = {
		names = {}, invis = {}, heavy_heal = {}, illusion = {},
		channel = {}, engage = {}, evasion = {}, summons = {},
	}
	for _, id in ipairs(GetTeamPlayers(GetOpposingTeam())) do
		local ok, name = pcall(GetSelectedHeroName, id)
		if ok and name ~= nil and name ~= "" then
			local short = string.gsub(name, "npc_dota_hero_", "")
			profile.names[#profile.names + 1] = short
			if INVIS[short] then profile.invis[#profile.invis + 1] = short end
			if HEAVY_HEAL[short] then profile.heavy_heal[#profile.heavy_heal + 1] = short end
			if ILLUSION[short] then profile.illusion[#profile.illusion + 1] = short end
			if CHANNEL_ULT[short] then profile.channel[#profile.channel + 1] = short end
			if HARD_ENGAGE[short] then profile.engage[#profile.engage + 1] = short end
			if EVASION[short] then profile.evasion[#profile.evasion + 1] = short end
			if SUMMONS[short] then profile.summons[#profile.summons + 1] = short end
		end
	end

	cachedProfile = profile
	return profile
end

-- ---------------------------------------------------------------------------
-- Buy-list adaptation
-- ---------------------------------------------------------------------------
local function shortName(unitName)
	return string.gsub(unitName or "", "npc_dota_hero_", "")
end

local function findItem(list, names)
	for _, item in ipairs(list) do
		for _, want in ipairs(names) do
			if item == want then return true end
		end
	end
	return false
end

local function indexOf(list, names)
	for i, item in ipairs(list) do
		for _, want in ipairs(names) do
			if item == want then return i end
		end
	end
	return nil
end

-- insert after the first boots-ish entry (so consumables/openers stay first),
-- falling back to the middle of the list
local function insertAfterBoots(list, item)
	local bootsIdx = indexOf(list, {
		"item_boots", "item_phase_boots", "item_power_treads",
		"item_arcane_boots", "item_tranquil_boots", "item_travel_boots",
		"item_travel_boots_2",
	})
	local at = bootsIdx and (bootsIdx + 2) or math.max(2, math.ceil(#list / 2))
	table.insert(list, math.min(at, #list + 1), item)
end

local function removeItem(list, item)
	for i, v in ipairs(list) do
		if v == item then table.remove(list, i) return true end
	end
	return false
end

-- AdjustBuyList(bot, buyList, pos) -> adjusted buyList, changeLogTable
-- buyList: array of item names (the hero's role build, already resolved)
function draft_lib.AdjustBuyList(bot, buyList, pos)
	local changes = {}
	local profile = draft_lib.GetEnemyProfile()
	local isMelee = (bot:GetAttackRange() or 320) <= 320
	local insertions, reorders = 0, 0

	local function canInsert()
		return insertions < 2
	end
	local function insert(item, reason)
		if findItem(buyList, { item }) then return false end
		insertAfterBoots(buyList, item)
		insertions = insertions + 1
		changes[#changes + 1] = item .. " (" .. reason .. ")"
		return true
	end

	-- 1. strong enemy healing -> Spirit Vessel (any role; classic pos-4 answer)
	if #profile.heavy_heal >= 2
	and not findItem(buyList, { "item_spirit_vessel", "item_urn_of_shadows" })
	and canInsert()
	then
		insert("item_spirit_vessel", "enemy healing: "
			.. table.concat(profile.heavy_heal, ","))
	end

	-- 2. illusions + melee core -> Battle Fury (cleave)
	if #profile.illusion >= 1 and pos <= 2 and isMelee
	and not findItem(buyList, {
		"item_bfury", "item_mjollnir", "item_gleipnir",
		"item_shivas_guard", "item_radiance",
	})
	and canInsert()
	then
		insert("item_bfury", "enemy illusions: "
			.. table.concat(profile.illusion, ","))
	end

	-- 3. evasion threat -> Monkey King Bar
	if #profile.evasion >= 1 and pos <= 3
	and not findItem(buyList, { "item_mkb", "item_bloodthorn" })
	and canInsert()
	then
		insert("item_mkb", "enemy evasion: "
			.. table.concat(profile.evasion, ","))
	end

	-- 4. multiple channeling ults + mid -> Orchid to shut them down
	if #profile.channel >= 2 and pos == 2
	and not findItem(buyList, {
		"item_orchid", "item_orchid_malevolence", "item_bloodthorn",
		"item_sheepstick", "item_abyssal_blade",
	})
	and canInsert()
	then
		insert("item_orchid", "enemy channel ults: "
			.. table.concat(profile.channel, ","))
	end

	-- 5. heavy engage draft -> BKB earlier (or added for pos 2/3)
	if #profile.engage >= 2 then
		local bkbIdx = indexOf(buyList, { "item_black_king_bar" })
		if bkbIdx ~= nil and bkbIdx > 4 and reorders < 1 then
			removeItem(buyList, "item_black_king_bar")
			table.insert(buyList, 4, "item_black_king_bar")
			reorders = reorders + 1
			changes[#changes + 1] = "black_king_bar moved earlier (enemy engage: "
				.. table.concat(profile.engage, ",") .. ")"
		elseif bkbIdx == nil and (pos == 2 or pos == 3) and canInsert() then
			insert("item_black_king_bar", "enemy engage: "
				.. table.concat(profile.engage, ","))
		end
	end

	-- invis: dust/sentry stocking is already handled by the purchase engine
	-- via Role['invisEnemyExist']; nothing to change in the build itself.
	if #profile.invis >= 1 then
		changes[#changes + 1] = "noted invis threats: "
			.. table.concat(profile.invis, ",") .. " (dust/sentries handled by base logic)"
	end

	return buyList, changes, shortName(bot:GetUnitName())
end

return draft_lib
