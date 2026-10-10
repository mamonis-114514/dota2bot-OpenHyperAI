-- laning_lib.lua
-- Phase 1 (SmartPlay.Laning_Micro): laning micro that the base mode lacks.
--
--  * creep-aggro awareness + aggro dump after harassing
--  * ranged/melee harass windows with human-ish reaction delays
--  * lane state (pushing / even / danger) estimation
--  * "miss" chat calls when the lane opponent leaves vision
--
-- Everything here is advisory: mode_laning_generic.lua calls into this module
-- AFTER last-hit/deny handling, so farm is never sacrificed for harass.

local Laning = {}

local J = require( GetScriptDirectory()..'/FunLib/jmz_func' )
local Human = require( GetScriptDirectory()..'/FunLib/human_lib' )
local Localization = require( GetScriptDirectory()..'/FunLib/localization' )

local HARASS_MAX_EXTRA_RANGE = 100   -- cast slightly beyond max range
local AGGRO_CHECK_RADIUS = 800

-- ---------------------------------------------------------------------------
-- Creep aggro
-- ---------------------------------------------------------------------------

-- true when enemy lane creeps currently target the bot (drawn aggro)
function Laning.EnemyCreepAggroOn( bot )
	local creeps = bot:GetNearbyLaneCreeps( AGGRO_CHECK_RADIUS, true )
	for _, creep in pairs( creeps ) do
		if J.IsValid( creep ) and not creep:IsNull() then
			local target = creep:GetAttackTarget()
			if target ~= nil and target == bot then
				return true, creep
			end
		end
	end
	return false, nil
end

-- Attack an own creep to drop the drawn creep/tower aggro (classic dump).
-- Returns true when the dump attack was issued.
function Laning.DropAggro( bot, nAllyCreeps )
	local best, bestDist = nil, 99999
	for _, creep in pairs( nAllyCreeps or {} ) do
		if J.IsValid( creep ) and J.CanBeAttacked( creep ) then
			local d = GetUnitToUnitDistance( bot, creep )
			if d <= bot:GetAttackRange() + 120 and d < bestDist then
				best, bestDist = creep, d
			end
		end
	end
	if best ~= nil then
		bot:Action_AttackUnit( best, true )
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Lane state
-- ---------------------------------------------------------------------------

-- 'pushing' (our wave is crashing into their tower), 'danger' (their wave
-- dominates and the front drifts toward us is fine - the risky one is when
-- OUR wave is small far from our tower), or 'even'.
function Laning.GetLaneState( bot, nAllyCreeps, nEnemyCreeps )
	local aCount, eCount = 0, 0
	local aHP, eHP = 0, 0
	for _, c in pairs( nAllyCreeps or {} ) do
		if J.IsValid( c ) then aCount = aCount + 1; aHP = aHP + c:GetHealth() end
	end
	for _, c in pairs( nEnemyCreeps or {} ) do
		if J.IsValid( c ) then eCount = eCount + 1; eHP = eHP + c:GetHealth() end
	end
	if aCount >= eCount + 2 and aHP > eHP * 1.2 then return 'pushing' end
	if eCount >= aCount + 2 and eHP > aHP * 1.2 then return 'danger' end
	return 'even'
end

-- ---------------------------------------------------------------------------
-- Harass
-- ---------------------------------------------------------------------------

-- pick the harassable enemy hero in our lane, or nil
function Laning.FindHarassTarget( bot, nInRangeEnemy, botAssignedLane )
	local botAttackRange = bot:GetAttackRange()
	local laneFront = GetLaneFrontLocation( GetTeam(), botAssignedLane, 0 )
	local best, bestScore = nil, -1

	for _, enemy in pairs( nInRangeEnemy or {} ) do
		if J.IsValidHero( enemy )
		and J.CanBeAttacked( enemy )
		and not J.IsSuspiciousIllusion( enemy )
		and GetUnitToLocationDistance( enemy, laneFront ) < 1600 -- still in our lane
		and not enemy:HasModifier( 'modifier_faceless_void_chronosphere_freeze' )
		then
			local dist = GetUnitToUnitDistance( bot, enemy )
			if dist <= botAttackRange + HARASS_MAX_EXTRA_RANGE then
				-- don't harass into the enemy tower (towers friendly to the target)
				local underTower = false
				for _, tower in pairs( enemy:GetNearbyTowers( 750, false ) or {} ) do
					if J.IsValid( tower ) and not string.find( tower:GetUnitName(), 'fillers' ) then
						underTower = true
						break
					end
				end
				if not underTower or J.GetHP( enemy ) < 0.2 then
					local hpScore = 1 - J.GetHP( enemy )
					local distScore = 1 - dist / ( botAttackRange + HARASS_MAX_EXTRA_RANGE )
					local score = hpScore * 2 + distScore
					if score > bestScore then
						best, bestScore = enemy, score
					end
				end
			end
		end
	end
	return best
end

function Laning.ShouldHarass( bot, target, nEnemyCreeps, laneState )
	if target == nil then return false end

	local botHP = J.GetHP( bot )
	local targetHP = J.GetHP( target )
	local isMelee = bot:GetAttackRange() <= 320
	local enemyCreepsNearTarget = 0
	for _, c in pairs( nEnemyCreeps or {} ) do
		if J.IsValid( c ) and GetUnitToUnitDistance( c, target ) < 500 then
			enemyCreepsNearTarget = enemyCreepsNearTarget + 1
		end
	end

	-- self-preservation gates
	if botHP < 0.55 then return false end
	-- need some edge or kill pressure (Archon-grade discipline)
	local hpEdge = ( botHP - targetHP ) >= 0.10
	local killPressure = targetHP <= 0.35
	if not ( hpEdge or killPressure ) then return false end

	-- melee heroes only finish low targets or isolated ones
	if isMelee and not ( killPressure or enemyCreepsNearTarget == 0 ) then
		return false
	end

	-- too many enemy creeps near us: harass trades badly
	local creepsNearBot = 0
	for _, c in pairs( nEnemyCreeps or {} ) do
		if J.IsValid( c ) and GetUnitToUnitDistance( c, bot ) < 700 then
			creepsNearBot = creepsNearBot + 1
		end
	end
	if creepsNearBot >= 3 and laneState ~= 'pushing' then return false end

	-- don't harass while an enemy stun projectile is incoming
	if J.IsStunProjectileIncoming( bot, 600 ) then return false end

	return true
end

-- Called from mode_laning Think AFTER last-hit/deny returned no action.
-- Returns true when this frame was consumed (an order was issued).
function Laning.ThinkHarass( bot, nEnemyCreeps, nInRangeEnemy, nAllyCreeps, botAssignedLane )
	if not Human.Enabled( 'Laning_Micro' ) then return false end
	if not J.IsInLaningPhase() then return false end
	if J.IsRetreating( bot ) or J.IsGoingOnSomeone( bot ) then return false end
	if DotaTime() < 15 then return false end -- creeps not met yet

	local laneState = Laning.GetLaneState( bot, nAllyCreeps, nEnemyCreeps )

	-- 1. dump aggro first (we are being shot by creeps)
	local aggroed = Laning.EnemyCreepAggroOn( bot )
	if aggroed then
		-- small chance to "panic" and just walk instead of the perfect dump
		if not Human.Skip( 0.10 ) and Laning.DropAggro( bot, nAllyCreeps ) then
			return true
		end
		return false -- let normal positioning (behind the wave) handle it
	end

	-- 2. harass window
	local target = Laning.FindHarassTarget( bot, nInRangeEnemy, botAssignedLane )
	if not Laning.ShouldHarass( bot, target, nEnemyCreeps, laneState ) then
		return false
	end

	-- human-ish reaction gap + occasional missed window
	if not Human.Ready( bot, 'spNextHarassTime', 0.5, 1.4 ) then return false end
	if Human.Skip( 0.12 ) then
		Human.Arm( bot, 'spNextHarassTime', 0.8, 1.8 )
		return false
	end

	bot:Action_AttackUnit( target, true )
	return true
end

-- ---------------------------------------------------------------------------
-- Miss calls
-- ---------------------------------------------------------------------------

-- Called periodically from laning Think. Announces (chat) when the enemy that
-- was laneing against us disappears for >4s. Only the lowest-playerId ally bot
-- assigned to the lane sends, so humans never see duplicated calls.
function Laning.UpdateMissCall( bot, nInRangeEnemy, botAssignedLane )
	if not Human.Enabled( 'Laning_Micro' ) then return end
	if not J.IsInLaningPhase() then return end
	if GetGameMode() == GAMEMODE_1V1MID then return end
	if botAssignedLane == nil or botAssignedLane == LANE_NONE then return end

	local now = GameTime()
	local laneFront = GetLaneFrontLocation( GetTeam(), botAssignedLane, 0 )
	if bot.spLaneSeen == nil then bot.spLaneSeen = {} end

	-- remember which enemy heroes share our lane right now
	for _, enemy in pairs( nInRangeEnemy or {} ) do
		if J.IsValidHero( enemy )
		and not J.IsSuspiciousIllusion( enemy )
		and GetUnitToLocationDistance( enemy, laneFront ) < 1600
		then
			local name = enemy:GetUnitName()
			if bot.spLaneSeen[name] == nil then
				bot.spLaneSeen[name] = { last = now, announced = false }
			else
				local rec = bot.spLaneSeen[name]
				-- re-arm after being visible again for a bit
				if now - rec.last > 8 then rec.announced = false end
				rec.last = now
			end
		end
	end

	-- announce fresh disappearances
	for name, rec in pairs( bot.spLaneSeen ) do
		local gone = now - rec.last
		if gone > 4 and gone < 25 and not rec.announced then
			-- only one sender per lane (deterministic across sandboxes)
			if not Laning.AmILowestLaneSender( bot, botAssignedLane ) then
				rec.announced = true
				return
			end
			rec.announced = true
			local laneKey = 'mid'
			if botAssignedLane == LANE_TOP then laneKey = 'top' end
			if botAssignedLane == LANE_BOT then laneKey = 'bot' end
			local msgs = Localization.Get( 'say_miss_' .. laneKey )
			if msgs ~= nil and #msgs > 0 then
				bot:ActionImmediate_Chat( msgs[RandomInt( 1, #msgs )], false )
			end
			return -- one call per frame at most
		end
	end
end

function Laning.AmILowestLaneSender( bot, botAssignedLane )
	local myID = bot:GetPlayerID()
	local lowestID = myID
	for _, id in pairs( GetTeamPlayers( GetTeam() ) ) do
		local member = GetTeamMember( id )
		if member ~= nil and member:IsAlive() and member:IsBot() then
			local ok, lane = pcall( member.GetAssignedLane, member )
			if ok and lane == botAssignedLane and member:GetPlayerID() < lowestID then
				lowestID = member:GetPlayerID()
			end
		end
	end
	return lowestID == myID
end

return Laning
