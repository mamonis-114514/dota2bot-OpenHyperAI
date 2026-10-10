-- camp_lib.lua
-- Phase 1 (SmartPlay.Pull_And_Stack): camp stacking & lane pulling.
--
-- Delivery model: this module never runs as its own mode. It raises the farm
-- mode desire for a short, well-defined time window (mode_farm_generic wraps
-- GetDesire with Camp.DesireBonus) and takes over the farm Think via
-- Camp.FarmIntercept while the window is active. When the window ends the bot
-- falls back to whatever it was doing (engine laning for supports, etc).
--
-- Human-friendly rules:
--   * if a HUMAN player is close to the camp, bots yield it entirely
--   * if several bots qualify, only the lowest player id commits (deterministic
--     across sandboxes)
--   * every attempt has a hard timeout + personal cooldown on failure

local Camp = {}

local J = require( GetScriptDirectory()..'/FunLib/jmz_func' )
local Human = require( GetScriptDirectory()..'/FunLib/human_lib' )

local STACK_WINDOW_START = 50   -- second of minute
local STACK_WINDOW_END = 55
local STACK_RELEASE = 57        -- stop re-aggroing, commit to the drag point
local PULL_WINDOW_START = 15
local PULL_WINDOW_END = 45
local ATTEMPT_TIMEOUT = 14.0
local FAIL_COOLDOWN = 30.0
local STACK_CAMP_RADIUS = 1500  -- max travel to a stack opportunity
local PULL_CAMP_RADIUS = 2500
local HUMAN_DEFER_RADIUS = 900

local function SecondOfMinute()
	local t = DotaTime()
	if t < 0 then return -1 end
	return t % 60
end

local function AliveHumansNear( loc, radius )
	for _, id in pairs( GetTeamPlayers( GetTeam() ) ) do
		local member = GetTeamMember( id )
		if member ~= nil and member:IsAlive() and not member:IsBot()
		and GetUnitToLocationDistance( member, loc ) <= radius
		then
			return true
		end
	end
	return false
end

-- deterministic: is `bot` the lowest-player-id alive bot within `radius` of loc?
local function IsLowestIDNear( bot, loc, radius )
	local myID = bot:GetPlayerID()
	for _, id in pairs( GetTeamPlayers( GetTeam() ) ) do
		local member = GetTeamMember( id )
		if member ~= nil and member:IsAlive() and member:IsBot()
		and member:GetPlayerID() < myID
		and GetUnitToLocationDistance( member, loc ) <= radius
		then
			return false
		end
	end
	return true
end

-- smallOrMediumOnly: pull camps (same-side small/medium); otherwise all camps
local function GetCampList( smallOrMediumOnly )
	local camps = {}
	local ok, spawners = pcall( GetNeutralSpawners )
	if not ok or spawners == nil then return camps end
	for _, camp in pairs( spawners ) do
		if camp ~= nil and camp.cattr ~= nil and camp.cattr.location ~= nil then
			local sameSide = ( camp.team == nil ) or ( camp.team == GetTeam() )
			if smallOrMediumOnly then
				if sameSide and ( camp.type == 'small' or camp.type == 'medium' ) then
					camps[#camps + 1] = camp
				end
			else
				camps[#camps + 1] = camp
			end
		end
	end
	return camps
end

local function HasCampCreeps( bot, radius )
	local creeps = bot:GetNearbyNeutralCreeps( radius )
	for _, c in pairs( creeps ) do
		if J.IsValid( c ) and not c:IsNull() then return true end
	end
	return false
end

local function NearestCampCreep( bot, radius )
	local creeps = bot:GetNearbyNeutralCreeps( radius )
	for _, c in pairs( creeps ) do
		if J.IsValid( c ) and not c:IsNull() then return c end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Stacking
-- ---------------------------------------------------------------------------

-- desire bonus (0..0.85) when a stack opportunity is actionable right now
function Camp.StackDesireBonus( bot )
	if not Human.Enabled( 'Pull_And_Stack' ) then return 0 end
	local sec = SecondOfMinute()
	if sec < STACK_WINDOW_START or sec > STACK_WINDOW_END then return 0 end
	if DotaTime() < 2 * 60 then return 0 end -- let the first spawns settle
	if J.IsRetreating( bot ) or J.IsGoingOnSomeone( bot ) then return 0 end
	if J.Utils.IsTeamPushingSecondTierOrHighGround( bot ) then return 0 end
	if bot.spStackFailUntil ~= nil and GameTime() < bot.spStackFailUntil then return 0 end

	local botLevel = bot:GetLevel()
	for _, camp in ipairs( GetCampList( false ) ) do
		local loc = camp.cattr.location
		if not ( camp.type == 'ancient' and botLevel < 12 )
		and GetUnitToLocationDistance( bot, loc ) <= STACK_CAMP_RADIUS
		and not AliveHumansNear( loc, HUMAN_DEFER_RADIUS )
		and IsLowestIDNear( bot, loc, STACK_CAMP_RADIUS )
		then
			return 0.85
		end
	end
	return 0
end

-- consumes the farm think during a stack attempt; returns true when handled
function Camp.FarmIntercept( bot )
	if not Human.Enabled( 'Pull_And_Stack' ) then return false end

	local sec = SecondOfMinute()

	-- pull handling first (its window does not overlap the stack window)
	if Camp.PullIntercept( bot ) then return true end
	if Camp.PullDesireBonus( bot ) > 0 and Camp.TryCommitPull( bot ) then
		return true
	end

	local stackActive = ( sec >= STACK_WINDOW_START ) or ( sec < 5 )

	-- clear stale state once the minute has safely rolled over
	if bot.spStackState ~= nil and not stackActive then
		bot.spStackState = nil
		bot.spStackCamp = nil
	end

	-- active attempt: drag camp creeps out of the spawn box
	if bot.spStackState == 'drag' then
		local camp = bot.spStackCamp
		if sec < 5 then
			-- new spawn set is out: resume (farm think will fight the double camp)
			bot.spStackState = nil
			bot.spStackCamp = nil
			return false
		end
		if camp == nil or DotaTime() > ( bot.spStackTryTime or 0 ) + ATTEMPT_TIMEOUT then
			bot.spStackState = nil
			bot.spStackCamp = nil
			bot.spStackFailUntil = GameTime() + FAIL_COOLDOWN
			return false
		end
		local target = NearestCampCreep( bot, 800 )
		if target == nil then
			bot.spStackState = nil
			bot.spStackCamp = nil
			bot.spStackFailUntil = GameTime() + FAIL_COOLDOWN
			return false
		end
		local stackPoint = J.VectorTowards( camp.cattr.location, J.GetTeamFountain(), 900 )
		if sec >= STACK_RELEASE then
			bot:Action_MoveToLocation( stackPoint )
		else
			bot:Action_AttackUnit( target, true )
			bot:ActionQueue_MoveToLocation( stackPoint )
		end
		return true
	end

	-- entering the window near a camp: commit
	if sec >= STACK_WINDOW_START and sec <= STACK_WINDOW_END
	and Camp.StackDesireBonus( bot ) > 0
	then
		for _, camp in ipairs( GetCampList( false ) ) do
			local loc = camp.cattr.location
			if not ( camp.type == 'ancient' and bot:GetLevel() < 12 )
			and GetUnitToLocationDistance( bot, loc ) <= STACK_CAMP_RADIUS
			and not AliveHumansNear( loc, HUMAN_DEFER_RADIUS )
			then
				if HasCampCreeps( bot, 900 ) then
					bot.spStackState = 'drag'
					bot.spStackCamp = camp
					bot.spStackTryTime = DotaTime()
				else
					-- camp empty: be there when the new set spawns
					bot:Action_MoveToLocation( loc + RandomVector( 100 ) )
				end
				return true
			end
		end
	end

	return false
end

-- ---------------------------------------------------------------------------
-- Lane pulling (pos 4/5): lure a small camp into our wave to reset the lane
-- ---------------------------------------------------------------------------

function Camp.PullDesireBonus( bot )
	if not Human.Enabled( 'Pull_And_Stack' ) then return 0 end
	local pos = J.GetPosition( bot )
	if pos == nil or pos < 4 then return 0 end -- supports only
	if not J.IsInLaningPhase() then return 0 end
	local sec = SecondOfMinute()
	if sec < PULL_WINDOW_START or sec > PULL_WINDOW_END then return 0 end
	if J.IsRetreating( bot ) or J.IsGoingOnSomeone( bot ) then return 0 end
	if J.GetHP( bot ) < 0.6 then return 0 end
	if bot.spPullFailUntil ~= nil and GameTime() < bot.spPullFailUntil then return 0 end
	if bot.spNextPullTime ~= nil and GameTime() < bot.spNextPullTime then return 0 end

	local lane = bot:GetAssignedLane()
	if lane == nil or lane == LANE_NONE then return 0 end
	local laneFront = GetLaneFrontLocation( GetTeam(), lane, 0 )

	-- lane must be pushed toward the enemy (that is when a pull resets it)
	local enemyTower = nil
	for _, tower in pairs( GetUnitList( UNIT_LIST_ENEMY_BUILDINGS ) or {} ) do
		if J.IsValid( tower )
		and string.find( tower:GetUnitName(), 'tower' ) ~= nil
		and string.find( tower:GetUnitName(), 'fillers' ) == nil
		then
			if enemyTower == nil
			or GetUnitToLocationDistance( tower, laneFront ) < GetUnitToLocationDistance( enemyTower, laneFront )
			then
				enemyTower = tower
			end
		end
	end
	if enemyTower == nil then return 0 end
	if GetUnitToLocationDistance( enemyTower, laneFront ) > 1800 then return 0 end

	-- a same-side small/medium camp close to the lane front, no enemies around
	for _, camp in ipairs( GetCampList( true ) ) do
		local loc = camp.cattr.location
		if GetUnitToLocationDistance( loc, laneFront ) <= PULL_CAMP_RADIUS
		and not AliveHumansNear( loc, HUMAN_DEFER_RADIUS )
		and IsLowestIDNear( bot, loc, PULL_CAMP_RADIUS )
		and #bot:GetNearbyHeroes( 1200, true, BOT_MODE_NONE ) == 0
		then
			return 0.7
		end
	end
	return 0
end

function Camp.TryCommitPull( bot )
	if bot.spPullState ~= nil then return false end
	if not Human.Ready( bot, 'spNextPullTime', 1.0, 2.0 ) then return false end
	if Human.Skip( 0.15 ) then return false end
	bot.spPullState = 'drag'
	bot.spPullTryTime = DotaTime()
	return true
end

-- pull drag: lures neutrals toward our wave; returns true while handled
function Camp.PullIntercept( bot )
	if bot.spPullState ~= 'drag' then return false end

	local lane = bot:GetAssignedLane()
	local laneFront = GetLaneFrontLocation( GetTeam(), lane or LANE_MID, 0 )
	if DotaTime() > ( bot.spPullTryTime or 0 ) + ATTEMPT_TIMEOUT then
		bot.spPullState = nil
		bot.spPullFailUntil = GameTime() + FAIL_COOLDOWN
		return false
	end

	-- our lane creeps are the destination
	local waveCreep = nil
	for _, c in pairs( bot:GetNearbyLaneCreeps( 1200, false ) ) do
		if J.IsValid( c ) and GetUnitToLocationDistance( c, laneFront ) < 1600 then
			waveCreep = c
			break
		end
	end

	local target = NearestCampCreep( bot, 700 )
	if waveCreep == nil or target == nil then
		bot.spPullState = nil
		bot.spPullFailUntil = GameTime() + FAIL_COOLDOWN
		return false
	end

	-- success: neutrals are mixing with the wave
	if GetUnitToUnitDistance( target, waveCreep ) < 400 then
		bot.spPullState = nil
		return false
	end

	bot:Action_AttackUnit( target, true )
	bot:ActionQueue_MoveToLocation( waveCreep:GetLocation() + RandomVector( 60 ) )
	return true
end

-- combined desire hook used by mode_farm_generic
function Camp.DesireBonus( bot )
	local stackBonus = Camp.StackDesireBonus( bot )
	if stackBonus > 0 then return stackBonus end
	return Camp.PullDesireBonus( bot )
end

return Camp
