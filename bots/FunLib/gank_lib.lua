-- gank_lib.lua
-- Phase 2 (SmartPlay.Team_Coordination):
--   * planned smoke ganks (time-anchored, deterministic across sandboxes)
--   * "enemies all missing" inference + warning chat / defend-desire nudge
--   * tower-dive detection consumed by the TP scroll logic
--   * team tower-count advantage used for aggressive warding
--
-- Determinism: every bot computes the same plan from shared engine state at
-- the same minute anchors, so the 10 sandboxes converge without a coordinator.

local Gank = {}

local J = require( GetScriptDirectory()..'/FunLib/jmz_func' )
local Human = require( GetScriptDirectory()..'/FunLib/human_lib' )
local Localization = require( GetScriptDirectory()..'/FunLib/localization' )
local HeroRoles = require( GetScriptDirectory()..'/FunLib/aba_hero_roles_map' )

local SMOKE_ANCHOR_MINUTES = { 9, 13, 17, 21, 25, 29, 33, 37 }
local SMOKE_WINDOW = 25          -- seconds a plan stays valid after the anchor
local SMOKE_TARGET_TOWER_DIST = 1100
local SMOKE_TARGET_SEEN_AGO = 20
local DIVE_RADIUS = 900
local WARN_MISSING_COUNT = 3
local WARN_MISSING_AWAY = 12

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function AliveEnemyIDs()
	local ids = {}
	for _, id in pairs( GetTeamPlayers( GetOpposingTeam() ) ) do
		if IsHeroAlive( id ) then ids[#ids + 1] = id end
	end
	return ids
end

local function AliveAllyIDs()
	local ids = {}
	for _, id in pairs( GetTeamPlayers( GetTeam() ) ) do
		local member = GetTeamMember( id )
		if member ~= nil and member:IsAlive() then ids[#ids + 1] = id end
	end
	return ids
end

local function IsLowestIDAliveSender( bot )
	local myID = bot:GetPlayerID()
	for _, id in pairs( AliveAllyIDs() ) do
		local member = GetTeamMember( id )
		if member ~= nil and member:IsBot() and member:GetPlayerID() < myID then
			return false
		end
	end
	return true
end

local function DistanceToNearestEnemyTower( loc )
	local nearest = 99999
	for _, tower in pairs( GetUnitList( UNIT_LIST_ENEMY_BUILDINGS ) or {} ) do
		if J.IsValid( tower )
		and string.find( tower:GetUnitName(), 'tower' ) ~= nil
		and string.find( tower:GetUnitName(), 'fillers' ) == nil
		then
			local d = GetUnitToLocationDistance( tower, loc )
			if d < nearest then nearest = d end
		end
	end
	return nearest
end

-- ---------------------------------------------------------------------------
-- smoke plan
-- ---------------------------------------------------------------------------

-- nil when no plan; { name, id, loc, until } otherwise
-- (cached per bot for 2s: desire functions run every frame)
function Gank.GetActiveSmokePlan( bot )
	if not Human.Enabled( 'Team_Coordination' ) then return nil end

	local now = GameTime()
	if bot.spSmokePlanCache ~= nil
	and now - bot.spSmokePlanCache.t < 2.0
	then
		return bot.spSmokePlanCache.plan
	end

	local plan = Gank.ComputeSmokePlan( bot )
	bot.spSmokePlanCache = { t = now, plan = plan }
	return plan
end

function Gank.ComputeSmokePlan( bot )
	if not Human.Enabled( 'Team_Coordination' ) then return nil end

	local t = DotaTime()
	if t < 8 * 60 or t > 45 * 60 then return nil end

	local minute = math.floor( t / 60 )
	local inWindow = false
	for _, m in ipairs( SMOKE_ANCHOR_MINUTES ) do
		if minute == m and ( t - m * 60 ) <= SMOKE_WINDOW then inWindow = true end
	end
	if not inWindow then return nil end

	-- veto: busy doing something more important
	if J.Utils.IsTeamPushingSecondTierOrHighGround( bot ) then return nil end
	for _, lane in ipairs( { LANE_TOP, LANE_MID, LANE_BOT } ) do
		if GetDefendLaneDesire( lane ) > 0.6 then return nil end
	end

	-- enough bodies, not outnumbered
	local allyAlive = #AliveAllyIDs()
	local enemyAlive = #AliveEnemyIDs()
	if allyAlive < 4 or enemyAlive > allyAlive then return nil end

	-- pick the juiciest isolated target from recent vision memory
	local best, bestScore = nil, -1
	for _, id in ipairs( AliveEnemyIDs() ) do
		local info = GetHeroLastSeenInfo( id )
		if info ~= nil and info[1] ~= nil then
			local dInfo = info[1]
			if dInfo.time_since_seen ~= nil and dInfo.time_since_seen <= SMOKE_TARGET_SEEN_AGO
			and dInfo.location ~= nil
			and DistanceToNearestEnemyTower( dInfo.location ) > SMOKE_TARGET_TOWER_DIST
			then
				local member = GetTeamMember( id )
				local name = ( member ~= nil and member:GetUnitName() ) or tostring( id )
				local roleScore = 0
				if HeroRoles.HasRole( name, 'carry' ) then roleScore = roleScore + 2 end
				if HeroRoles.HasRole( name, 'nuker' ) then roleScore = roleScore + 1 end
				local hpScore = 0
				if member ~= nil and member:IsAlive() then hpScore = ( 1 - J.GetHP( member ) ) end
				local score = roleScore * 2 + hpScore - dInfo.time_since_seen * 0.05
				if score > bestScore then
					best = { name = name, id = id, loc = dInfo.location, validUntil = minute * 60 + SMOKE_WINDOW }
					bestScore = score
				end
			end
		end
	end
	return best
end

-- deterministic announce: only the lowest-id alive bot chats & pings
function Gank.AnnounceSmokePlan( bot, plan )
	if plan == nil then return end
	if bot.spSmokeAnnouncedMinute == math.floor( DotaTime() / 60 ) then return end
	if not IsLowestIDAliveSender( bot ) then return end
	bot.spSmokeAnnouncedMinute = math.floor( DotaTime() / 60 )

	local msgs = Localization.Get( 'say_smoke_gank' )
	if msgs ~= nil and #msgs > 0 then
		bot:ActionImmediate_Chat( msgs[RandomInt( 1, #msgs )], false )
	end
	if plan.loc ~= nil then
		bot:ActionImmediate_Ping( plan.loc.x, plan.loc.y, true )
	end
end

-- deterministic dive alert (chat + ping on the dived tower), throttled 45s
function Gank.AnnounceDive( bot, dive )
	if dive == nil then return end
	if bot.spDiveAnnounceTime ~= nil and DotaTime() - bot.spDiveAnnounceTime < 45 then return end
	if not IsLowestIDAliveSender( bot ) then return end
	bot.spDiveAnnounceTime = DotaTime()

	if dive.loc ~= nil then
		bot:ActionImmediate_Ping( dive.loc.x, dive.loc.y, true )
	end
end

-- ---------------------------------------------------------------------------
-- enemies-missing inference
-- ---------------------------------------------------------------------------

-- true when >= WARN_MISSING_COUNT living enemies have been unseen for a while
function Gank.EnemiesMostlyMissing()
	local missing = 0
	local alive = 0
	for _, id in ipairs( AliveEnemyIDs() ) do
		alive = alive + 1
		local info = GetHeroLastSeenInfo( id )
		if info ~= nil and info[1] ~= nil
		and info[1].time_since_seen ~= nil
		and info[1].time_since_seen > WARN_MISSING_AWAY
		and info[1].time_since_seen < 90
		then
			missing = missing + 1
		end
	end
	return alive >= 3 and missing >= WARN_MISSING_COUNT
end

-- periodic warning chat; call from a throttled think for every bot
function Gank.UpdateWarnings( bot )
	if not Human.Enabled( 'Team_Coordination' ) then return end
	if DotaTime() < 3 * 60 or DotaTime() > 40 * 60 then return end
	if not Gank.EnemiesMostlyMissing() then return end
	if bot.spWarnTime ~= nil and DotaTime() - bot.spWarnTime < 60 then return end
	if not IsLowestIDAliveSender( bot ) then return end

	bot.spWarnTime = DotaTime()
	local msgs = Localization.Get( 'say_enemies_missing' )
	if msgs ~= nil and #msgs > 0 then
		bot:ActionImmediate_Chat( msgs[RandomInt( 1, #msgs )], false )
	end
end

-- ---------------------------------------------------------------------------
-- tower dive detection (consumed by item_tpscroll consideration)
-- ---------------------------------------------------------------------------

local OUR_TOWER_CONSTANTS = {
	TOWER_TOP_1, TOWER_TOP_2, TOWER_TOP_3,
	TOWER_MID_1, TOWER_MID_2, TOWER_MID_3,
	TOWER_BOT_1, TOWER_BOT_2, TOWER_BOT_3,
}

-- nil, or { tower, loc, enemies, ally }
function Gank.GetTowerDive( bot )
	if not Human.Enabled( 'Team_Coordination' ) then return nil end
	if not bot:IsAlive() then return nil end
	if J.IsGoingOnSomeone( bot ) or J.IsRetreating( bot ) then return nil end
	if J.GetHP( bot ) < 0.5 then return nil end

	for _, towerConst in ipairs( OUR_TOWER_CONSTANTS ) do
		local tower = GetTower( GetTeam(), towerConst )
		if tower ~= nil and J.IsValid( tower ) and tower:IsAlive() then
			local towerLoc = tower:GetLocation()
			local allies, alliesHurt = 0, 0
			for _, id in ipairs( AliveAllyIDs() ) do
				local member = GetTeamMember( id )
				if member ~= nil and GetUnitToLocationDistance( member, towerLoc ) <= DIVE_RADIUS then
					allies = allies + 1
					if member:WasRecentlyDamagedByAnyHero( 3 )
					or J.GetHP( member ) < 0.7
					then
						alliesHurt = alliesHurt + 1
					end
				end
			end
			local enemies = J.GetEnemiesNearLoc( towerLoc, DIVE_RADIUS )
			local enemyCount = ( enemies ~= nil ) and #enemies or 0

			if allies >= 1 and alliesHurt >= 1 and enemyCount >= 2
			and ( tower:WasRecentlyDamagedByAnyHero( 3 ) or alliesHurt >= 1 )
			then
				local diveLoc = J.VectorTowards( towerLoc, J.GetTeamFountain(), 350 )
				return { tower = tower, loc = diveLoc, enemies = enemyCount }
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- macro state for warding / trading decisions
-- ---------------------------------------------------------------------------

-- alive primary towers: ours minus theirs (positive = we are ahead)
function Gank.TowerCountAdvantage()
	local ours, theirs = 0, 0
	for _, towerConst in ipairs( OUR_TOWER_CONSTANTS ) do
		if GetTower( GetTeam(), towerConst ) ~= nil then ours = ours + 1 end
		if GetTower( GetOpposingTeam(), towerConst ) ~= nil then theirs = theirs + 1 end
	end
	return ours - theirs
end

return Gank
