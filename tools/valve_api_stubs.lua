-- valve_api_stubs.lua
-- Offline mock of the Dota 2 bot-scripting environment for smoke testing.
-- Loaded by tools/smoke_test.py into the Lua global table before dofile-ing
-- any bot entry file. Mirrors game/botsinit.lua semantics loosely: entry files
-- run with a shared _G here, but BotLib files are loaded with fresh per-file
-- environments by the Python harness (like the engine does per bot).
--
-- Usage (set by Python before executing):
--   MOCK_SCRIPT_DIR : forward-slash absolute path of the repo's bots/ dir
--   MOCK_HERO_NAME  : unit name returned by GetBot():GetUnitName()

local MOCK_SCRIPT_DIR = os.getenv("MOCK_SCRIPT_DIR") or "."
local MOCK_HERO_NAME = os.getenv("MOCK_HERO_NAME") or "npc_dota_hero_juggernaut"

-- ---------------------------------------------------------------------------
-- Vector
-- ---------------------------------------------------------------------------
local vmeta = {
	__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, (a.z or 0) + (b.z or 0)) end,
	__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)) end,
	__mul = function(a, b)
		if type(a) == "number" then return Vector(a * b.x, a * b.y, a * (b.z or 0)) end
		if type(b) == "number" then return Vector(a.x * b, a.y * b, (a.z or 0) * b) end
		return Vector(a.x * b.x, a.y * b.y, (a.z or 0) * (b.z or 0))
	end,
	__div = function(a, b)
		if type(b) == "number" then return Vector(a.x / b, a.y / b, (a.z or 0) / b) end
		return Vector(0, 0, 0)
	end,
	__unm = function(a) return Vector(-a.x, -a.y, -(a.z or 0)) end,
	__eq = function(a, b) return a.x == b.x and a.y == b.y and (a.z or 0) == (b.z or 0) end,
	__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y) end,
	__tostring = function(a) return string.format("Vector(%.0f, %.0f, %.0f)", a.x, a.y, a.z or 0) end,
}

local vmethods = {}
function vmethods:Normalized()
	local len = math.sqrt(self.x * self.x + self.y * self.y)
	if len == 0 then return Vector(0, 0, 0) end
	return Vector(self.x / len, self.y / len, (self.z or 0) / len)
end
vmeta.__index = vmethods

function Vector(x, y, z)
	return setmetatable({ x = x, y = y, z = z or 0 }, vmeta)
end

-- ---------------------------------------------------------------------------
-- Explicit constants (values that carry semantic weight in the code)
-- ---------------------------------------------------------------------------
local EXPLICIT_CONSTANTS = {
	BOT_ACTION_DESIRE_NONE = 0,
	BOT_ACTION_DESIRE_LOW = 1,
	BOT_ACTION_DESIRE_MODERATE = 2,
	BOT_ACTION_DESIRE_HIGH = 3,
	BOT_ACTION_DESIRE_ABSOLUTE = 4,
	BOT_MODE_DESIRE_NONE = 0,
	BOT_MODE_DESIRE_LOW = 0.25,
	BOT_MODE_DESIRE_MODERATE = 0.5,
	BOT_MODE_DESIRE_HIGH = 0.75,
	BOT_MODE_DESIRE_ABSOLUTE = 1.0,
	BOT_MODE_NONE = 0,
	BOT_MODE_LANING = 1,
	BOT_MODE_ATTACK = 2,
	BOT_MODE_RETREAT = 3,
	BOT_MODE_ROAM = 4,
	BOT_MODE_TEAM_ROAM = 5,
	BOT_MODE_FARM = 6,
	BOT_MODE_PUSH_TOWER_TOP = 7,
	BOT_MODE_PUSH_TOWER_MID = 8,
	BOT_MODE_PUSH_TOWER_BOT = 9,
	BOT_MODE_DEFEND_TOWER_TOP = 10,
	BOT_MODE_DEFEND_TOWER_MID = 11,
	BOT_MODE_DEFEND_TOWER_BOT = 12,
	BOT_MODE_ASSEMBLE = 13,
	BOT_MODE_ASSEMBLE_WITH_HUMANS = 14,
	BOT_MODE_RUNE = 15,
	BOT_MODE_WARD = 16,
	BOT_MODE_ROSHAN = 17,
	BOT_MODE_OUTPOST = 18,
	BOT_MODE_SECRET_SHOP = 19,
	BOT_MODE_SIDE_SHOP = 20,
	BOT_MODE_ITEM = 21,
	GAME_STATE_PRE_GAME = 0,
	GAME_STATE_GAME_IN_PROGRESS = 1,
	GAME_STATE_POST_GAME = 2,
	GAMEMODE_MO = 3,
	GAMEMODE_TURBO = 23,
	GAMEMODE_ARDM = 20,
	GAMEMODE_1V1MID = 26,
	TEAM_RADIANT = 2,
	TEAM_DIRE = 3,
	TEAM_NONE = 1,
	LANE_NONE = 0,
	LANE_BOT = 1,
	LANE_MID = 2,
	LANE_TOP = 3,
	DAMAGE_TYPE_PHYSICAL = 1,
	DAMAGE_TYPE_MAGICAL = 2,
	DAMAGE_TYPE_PURE = 3,
	ITEM_SLOT_TYPE_MAIN = 0,
	ITEM_SLOT_TYPE_BACKPACK = 1,
	ITEM_SLOT_TYPE_STASH = 2,
	ITEM_SLOT_TYPE_NEUTRAL_ACTIVE = 3,
	ITEM_SLOT_TYPE_NEUTRAL_PASSIVE = 4,
	UNIT_LIST_ALL = 0,
	UNIT_LIST_ALLIES = 1,
	UNIT_LIST_ENEMIES = 2,
	UNIT_LIST_NEUTRAL_CREEPS = 3,
	UNIT_LIST_ENEMY_CREEPS = 4,
	UNIT_LIST_ALLIED_CREEPS = 5,
	UNIT_LIST_ROSHAN = 6,
	UNIT_LIST_COURIERS = 7,
	UNIT_LIST_OTHER = 8,
	MODIFIER_PROPERTY_PROVIDES_FOW_POSITION = 0,
	BOT_MODE_ROSHAN_TARGET_NONE = 0,
	PING_TYPE_NORMAL = 0,
	PING_TYPE_ENEMY_MISSING = 1,
	PING_TYPE_RUNE = 2,
	PING_TYPE_ENEMY_IN_THIS_AREA = 3,
}

-- Deterministic auto-numbering for any other CONSTANT_LIKE_NAME global.
local autoN = 1000
local constMeta = {
	__index = function(t, k)
		if type(k) == "string" and string.match(k, "^[A-Z][A-Z0-9_]*$") then
			local v = EXPLICIT_CONSTANTS[k]
			if v == nil then
				autoN = autoN + 1
				v = autoN
			end
			rawset(t, k, v)
			return v
		end
		return nil
	end,
}
setmetatable(_G, constMeta)

-- ---------------------------------------------------------------------------
-- Math / misc engine helpers
-- ---------------------------------------------------------------------------
function RandomInt(lo, hi) return math.floor((lo + hi) / 2) end
function RandomFloat(lo, hi) return (lo + hi) / 2 end
function RandomVector(len) return Vector(len, 0, 0) end

function RemapValClamped(v, a, b, c, d)
	if b == a then return c end
	local t = (v - a) / (b - a)
	t = math.max(0, math.min(1, t))
	return c + (d - c) * t
end

function AngleDiff(a, b)
	local d = a - b
	while d > 180 do d = d - 360 end
	while d < -180 do d = d + 360 end
	return d
end

function Bound(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function Min(a, b) return math.min(a, b) end
function Max(a, b) return math.max(a, b) end

function LerpVectors(a, b, t) return Vector(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, 0) end

local function dist2d(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return 9999 end
	local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
	return math.sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------------------
-- Mock abilities / items
-- ---------------------------------------------------------------------------
local function make_mock_ability(name)
	local a = {}
	a.__mock = "ability"
	a.GetName = function() return name or "mock_ability" end
	a.IsNull = function() return false end
	a.IsTrained = function() return true end
	a.IsTalent = function() return false end
	a.IsFullyCastable = function() return false end
	a.IsHidden = function() return false end
	a.IsPassive = function() return false end
	a.IsStolen = function() return false end
	a.IsActivated = function() return true end
	a.IsUltimate = function() return false end
	a.IsItem = function() return false end
	a.IsToggleable = function() return false end
	a.GetLevel = function() return 1 end
	a.GetMaxLevel = function() return 1 end
	a.GetCastRange = function() return 600 end
	a.GetManaCost = function() return 100 end
	a.GetCooldown = function() return 10 end
	a.GetCooldownTimeRemaining = function() return 0 end
	a.GetAbilityDamage = function() return 100 end
	a.GetCastPoint = function() return 0.3 end
	a.GetAOERadius = function() return 200 end
	a.GetBehavior = function() return 0 end
	a.GetTargetType = function() return 0 end
	a.GetSpecialValueInt = function() return 0 end
	a.GetSpecialValueFloat = function() return 0.0 end
	a.GetAutoCastState = function() return false end
	a.GetToggleState = function() return false end
	a.IsInAbilityPhase = function() return false end
	a.IsCastingAbility = function() return false end
	a.IsCooldownReady = function() return true end
	a.GetHeroLevelRequiredToUpgrade = function() return 25 end
	return a
end

local abilityCache = {}
local function mock_ability(name)
	if name == nil then return nil end
	if abilityCache[name] == nil then abilityCache[name] = make_mock_ability(name) end
	return abilityCache[name]
end

local talentCache = {}
local function mock_talent(slot)
	if talentCache[slot] == nil then
		local t = make_mock_ability("special_bonus_mock_" .. tostring(slot))
		t.IsTalent = function() return true end
		talentCache[slot] = t
	end
	return talentCache[slot]
end

-- ---------------------------------------------------------------------------
-- Mock units
-- ---------------------------------------------------------------------------
local function make_mock_unit()
	local u = {}
	u.__mock = "unit"
	u.__mockUnitName = MOCK_HERO_NAME
	u.__mockLocation = Vector(0, 0, 0)

	local function b() return false end
	local function n() return 0 end

	u.GetName = function() return "mock_unit" end
	u.GetUnitName = function() return u.__mockUnitName end
	u.GetTeam = function() return TEAM_RADIANT end
	u.GetTeamSlot = function() return 0 end
	u.GetPlayerID = function() return 0 end
	u.GetPlayerName = function() return "MockPlayer" end
	u.GetPlayerColor = function() return 3 end
	u.GetSteamID = function() return 0 end
	u.IsBot = function() return true end
	u.IsHero = function() return true end
	u.IsRealHero = function() return true end
	u.IsIllusion = function() return false end
	u.IsControllable = function() return true end
	u.IsAlive = function() return true end
	u.IsInvulnerable = function() return false end
	u.IsKillable = function() return true end
	u.IsNull = function() return false end
	u.IsCreep = function() return false end
	u.IsTower = function() return false end
	u.IsBuilding = function() return false end
	u.IsAncientCreep = function() return false end
	u.IsDominated = function() return false end
	u.IsMagicImmune = function() return false end
	u.IsRooted = b
	u.IsStunned = b
	u.IsSilenced = b
	u.IsHexed = b
	u.IsNightmared = b
	u.IsDisarmed = b
	u.IsAttackImmune = b
	u.IsInvisible = b
	u.IsChanneling = b
	u.IsUsingAbility = b
	u.IsCastingAbility = b
	u.IsInAbilityPhase = b
	u.IsBlind = b
	u.IsSpeciallyDeniable = function() return false end
	u.IsOther = function() return false end
	u.IsCourier = function() return false end
	u.IsPowerCogs = function() return false end
	u.IsFacingLocation = function() return true end
	u.IsFacingUnit = function() return true end
	u.CanBeSeen = function() return true end
	u.CanBeDominated = function() return false end

	u.GetLocation = function() return u.__mockLocation end
	u.GetExtrapolatedLocation = function() return u.__mockLocation end
	u.GetMovementDirectionStability = function() return 1 end
	u.GetAnimActivity = function() return 0 end
	u.GetCurrentActionType = function() return 0 end
	u.GetActiveMode = function() return BOT_MODE_NONE end
	u.GetActiveModeDesire = function() return 0 end

	u.GetHealth = function() return 1000 end
	u.GetMaxHealth = function() return 1000 end
	u.GetHealthRegen = function() return 5 end
	u.GetMana = function() return 500 end
	u.GetMaxMana = function() return 500 end
	u.GetManaRegen = function() return 2 end
	u.GetLevel = function() return 6 end
	u.GetAttackDamage = function() return 60 end
	u.GetAttackRange = function() return 500 end
	u.GetAttackSpeed = function() return 100 end
	u.GetAttackPoint = function() return 0.3 end
	u.GetAttackTarget = function() return nil end
	u.GetAttackProjectileSpeed = function() return 900 end
	u.GetSecondsPerAttack = function() return 1 end
	u.GetLastAttackTime = function() return 0 end
	u.GetCastPoint = function() return 0.3 end
	u.GetCurrentMovementSpeed = function() return 300 end
	u.GetCurrentVisionRange = function() return 1800 end
	u.GetNetWorth = function() return 5000 end
	u.GetGold = function() return 600 end
	u.GetStreak = n
	u.GetKills = n
	u.GetDeaths = n
	u.GetAssists = n
	u.GetRespawnTime = n
	u.GetTimeToRespawn = n
	u.GetPrimaryAttribute = n
	u.GetAttributeValue = function() return 10 end
	u.GetMagicResist = function() return 0.25 end
	u.GetSpellAmp = n
	u.GetRawOffensivePower = function() return 1000 end
	u.GetOffensivePower = function() return 1000 end
	u.GetEstimatedDamageToTarget = function() return 100 end
	u.GetAbilityPoints = function() return 1 end
	u.GetPowerTreadsStat = n
	u.GetHeightLevel = function() return 0 end
	u.GetAssignedLane = function() return LANE_NONE end
	u.GetDayTimeVisionRange = function() return 1800 end
	u.GetNightTimeVisionRange = function() return 800 end
	u.GetMaximumHealth = function() return 1000 end

	u.GetNearbyHeroes = function() return {} end
	u.GetNearbyLaneCreeps = function() return {} end
	u.GetNearbyCreeps = function() return {} end
	u.GetNearbyNeutralCreeps = function() return {} end
	u.GetNearbyTowers = function() return {} end
	u.GetNearbyBarracks = function() return {} end
	u.GetNearbyTrees = function() return {} end
	u.GetNearbyWards = function() return {} end
	u.GetNearbyRuneSpots = function() return {} end
	u.GetNearbyPings = function() return {} end
	u.GetIncomingTrackingProjectiles = function() return {} end
	u.GetLinearProjectiles = function() return {} end
	u.GetMostRecentPing = function() return nil end

	u.WasRecentlyDamagedByAnyHero = b
	u.WasRecentlyDamagedByAnyUnit = b
	u.WasRecentlyDamagedByHero = b
	u.WasRecentlyDamagedByCreep = b
	u.WasRecentlyDamagedByTower = b
	u.WasRecentlyHitByAnyHero = b
	u.HasModifier = b
	u.HasScepter = b
	u.HasShard = b
	u.HasBlackQueenCapsule = b
	u.GetModifierCount = n
	u.GetModifierStackCount = n
	u.GetModifierName = function() return "" end
	u.GetModifierByName = function() return nil end
	u.GetModifierList = function() return {} end

	u.GetTarget = function() return nil end
	u.SetTarget = function() end
	u.SetStickyTarget = function() end
	u.GetStickyTarget = function() return nil end

	u.GetAbilityByName = function(_, name) return mock_ability(name) end
	u.GetAbilityInSlot = function(_, slot)
		if type(slot) == "number" and slot >= 10 then return mock_talent(slot) end
		return mock_ability("mock_slot_ability_" .. tostring(slot))
	end
	u.GetAbilityByIndex = function(_, idx)
		if type(idx) == "number" and idx >= 10 then return mock_talent(idx) end
		return mock_ability("mock_index_ability_" .. tostring(idx))
	end
	u.GetAbilityList = function() return {} end
	u.GetCurrentActiveAbility = function() return nil end

	u.FindItemSlot = function() return -1 end
	u.GetItemInSlot = function() return nil end
	u.GetItemSlotType = function() return -1 end
	u.GetNumItemsInInventory = function() return 0 end
	u.GetPurchaseTime = function() return 0 end
	u.SetPurchaseTime = function() end
	u.HasItemInInventory = b
	u.SellSpecifiedItem = function() end

	-- Action no-ops
	for _, actionName in ipairs({
		"Action_AttackUnit", "Action_AttackMove", "Action_MoveToUnit", "Action_MoveToLocation",
		"Action_MoveDirectly", "Action_UseAbility", "Action_UseAbilityOnEntity", "Action_UseAbilityOnLocation",
		"Action_UseAbilityOnTree", "Action_UseAbilityOnPosition", "Action_PickUpItem", "Action_PickUpRune",
		"Action_DropItem", "Action_Buyback", "Action_Glyph", "Action_LevelAbility", "Action_CastAbility",
		"Action_ClearActions", "ActionImmediate_Chat", "ActionImmediate_Ping", "ActionImmediate_Glyph",
		"ActionPush", "ActionPush_MoveToLocation", "ActionPush_UseAbility", "ActionPush_AttackUnit",
		"ActionPush_DropItem", "ActionPush_PickUpItem", "ActionPush_BuyItem", "ActionPush_SellItem",
	}) do
		u[actionName] = function() return 0 end
	end
	u.ActionQueue = function(...) return 0 end
	u.ActionQueue_UseAbility = function() return 0 end
	u.ActionQueue_UseAbilityOnEntity = function() return 0 end
	u.ActionQueue_UseAbilityOnLocation = function() return 0 end
	u.ActionQueue_Clear = function() end
	u.ClearActions = function() end
	u.ClearCurrBuyingBasicItemList = function() end

	-- generic order entry points (some are monkey-patched via CDOTA_Bot_Script)
	u.Action = function() return 0 end
	u.ActionImmediate = function() return 0 end
	u.ActionPush = function() return 0 end
	u.GetUnitToLocationDistance = function(_, loc)
		if loc == nil then return 9999 end
		return dist2d(u.__mockLocation, loc)
	end
	u.NumQueuedActions = function() return 0 end
	u.ActionImmediate_Courier = function() return 0 end
	u.DistanceFromFountain = function() return 5000 end
	u.DistanceFromSecretShop = function() return 5000 end
	u.DistanceFromSideShop = function() return 5000 end
	u.NumModifiers = function() return 0 end
	u.OriginalGetHealth = function() return 1000 end
	u.OriginalGetMaxHealth = function() return 1000 end
	u.IsMuted = function() return false end
	u.GetCourierValue = function() return 0 end
	u.GetStashValue = function() return 0 end

	u.AddItem = function() return true end
	u.BuyItem = function() return true end
	u.SellItem = function() return true end
	u.CreateItem = function() return nil end
	u.SetNextItemPurchaseValue = function() end
	u.AddItemToStash = function() return true end

	u.HoldPosition = function() return 0 end
	u.ToggleNoOp = function() end
	return u
end

local unitCache = {}
local function mock_unit(id)
	if unitCache[id] == nil then unitCache[id] = make_mock_unit() end
	return unitCache[id]
end

-- Engine "class" table that aba_global_overrides.lua monkey-patches.
-- Any method looked up on it resolves to the mock default implementation,
-- so the overrides wrap (and then delegate to) working stubs.
CDOTA_Bot_Script = setmetatable({}, {
	__index = function(t, k)
		local v = make_mock_unit()[k]
		if type(v) ~= "function" then v = function() return nil end end
		rawset(t, k, v)
		return v
	end,
})

-- Valve's sandboxed dofile auto-appends ".lua"; stock Lua does not.
local rawdofile = dofile
function dofile(path)
	if type(path) == "string" and not string.match(path, "%.lua$") then
		path = path .. ".lua"
	end
	return rawdofile(path)
end

-- ---------------------------------------------------------------------------
-- Global engine functions
-- ---------------------------------------------------------------------------
function GetBot() return mock_unit("bot") end
function GetTeam() return TEAM_RADIANT end
function GetOpposingTeam() return TEAM_DIRE end
function GetTeamPlayers(team) return { 0, 1, 2, 3, 4 } end
function GetTeamMember(i) return mock_unit("member" .. tostring(i)) end
function GetTeamForPlayer(i) return TEAM_RADIANT end
function GetUnitList(listType) return {} end
function GetHeroAliveCount(team) return 5 end

local g_time = 30.0
function DotaTime() return g_time end
function GameTime() return g_time end
function GetTime() return g_time end
function GetAbsoluteTime() return g_time + 1000 end
function MOCK_SetTime(t) g_time = t end

function GetGameState() return GAME_STATE_GAME_IN_PROGRESS end
function GetGameMode() return 0 end
function IsGameModeTurbo() return false end
function IsServer() return true end

function GetHeroKills(id) return 0 end
function GetHeroDeaths(id) return 0 end
function GetHeroLevel(id) return 6 end
function GetHeroLastSeenInfo(id) return {} end
function IsHeroAlive(id) return true end
function IsPlayerBot(id) return true end
function IsPlayerInHeroSelectionControl(id) return false end

function GetScriptDirectory() return MOCK_SCRIPT_DIR end
function GetSelectedHeroName(id) return MOCK_HERO_NAME end
function SelectHero(id, name) end
function GetItemCost(name) return 1000 end
function GetItemStockCount(name) return 99 end
function GetItemComponents(name) return {} end
function CreateItem(name, who) return nil end
function GetDroppedItemList() return {} end

function GetUnitToUnitDistance(a, b)
	local la, lb = a:GetLocation(), b:GetLocation()
	if la == nil or lb == nil then return 9999 end
	return dist2d(la, lb)
end
function GetUnitToLocationDistance(a, loc)
	local la = a:GetLocation()
	if la == nil or loc == nil then return 9999 end
	return dist2d(la, loc)
end

function GetLaneFrontAmount(team, lane, b) return 0.5 end
function GetLaneFrontLocation(team, lane, offset) return Vector(0, 0, 0) end
function GetAmountAlongLane(lane, loc) return { amount = 0.5, location = Vector(0, 0, 0) } end
function GetLane(laneNumber) return nil end

function GetTower(team, n) return mock_unit("tower" .. tostring(n)) end
function GetBarracks(team, n) return mock_unit("barracks" .. tostring(n)) end
function GetAncient(team) return mock_unit("ancient" .. tostring(team)) end
function GetRuneSpawnLocation(runeType) return Vector(0, 0, 0) end
function GetRuneType(rune) return 0 end
function GetRuneStatus(rune) return 0 end
function GetIncomingTeleports() return {} end
function GetCourier() return mock_unit("courier") end
function GetCourierState() return 0 end
function GetShopLocation(team, shop) return Vector(0, 0, 0) end
function GetTreeLocation(id) return Vector(0, 0, 0) end
function GetNeutralSpawners() return {} end
function GetHeightLevel(loc) return 0 end
function IsLocationPassable(loc) return true end
function IsLocationVisible(loc) return true end
function GetRoshanLocation() return Vector(0, 0, 0) end
function GetRoshanKillTime() return 99999 end
function GetRoshanDesire() return 0.1 end
function GetPushLaneDesire(lane) return 0.3 end
function GetDefendLaneDesire(lane) return 0.2 end
function GetRoamDesire() return 0.1 end
function GetGlyphCooldown() return 0 end
function GetMaxDesire() return 1 end

-- Team-desire setters used by Valve framework glue (no-op offline)
function SetPushLaneDesire(lane, v) end
function SetDefendLaneDesire(lane, v) end
function SetRoamDesire(v) end
function SetRoshanDesire(v) end

function InstallChatCallback(fn) return 0 end
function GetLinearProjectiles() return {} end
function GetTrackingProjectiles() return {} end
function IsValidBuildingTarget(u, b) return false end
function GetWorldBounds() return { min = Vector(-8300, -8300, 0), max = Vector(8300, 8300, 0) } end

-- FretBots / Buff mode guard: pretend not enabled so those paths stay inert.
function IsFretBotsEnabled() return false end
