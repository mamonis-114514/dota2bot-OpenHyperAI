-- human_lib.lua
-- SmartPlay feature switches + human-like timing helpers for the enhanced
-- decision layer (see Customize/general.lua -> Customize.SmartPlay).
--
-- Design rules:
--   * decision-layer only, bots never gain stats from anything gated here
--   * delays/jitter apply to NEW aggressive behaviors only; existing
--     dodge/save/escape logic is never throttled through this module
--   * per-bot state lives on the bot handle, like the rest of the codebase

local human_lib = {}

local Customize = require( GetScriptDirectory()..'/Customize/general' )

-- Defaults for when the user's permanent override (game/Customize/general.lua)
-- predates the SmartPlay block: everything on.
local DEFAULTS = {
	Enable = true,
	Laning_Micro = true,
	Pull_And_Stack = true,
	Team_Coordination = true,
	Draft_Adaptive_Items = true,
	Meta_BP = true,
	Humanize = true,
	Laning_All_Heroes = false, -- experimental, see general.lua
}

-- human_lib.Enabled('Laning_Micro') -> boolean
-- subfeature == nil checks the master switch only.
function human_lib.Enabled( subfeature )
	if Customize.Enable == false then return false end
	local sp = Customize.SmartPlay
	if sp == nil then sp = DEFAULTS end
	if sp.Enable == false then return false end
	if subfeature == nil then return true end
	return sp[subfeature] ~= false
end

-- Reaction-window gate: returns true when the action may fire now and arms
-- the next window with a randomized human-ish delay.
function human_lib.Ready( bot, key, minDelay, maxDelay )
	local now = GameTime()
	if bot[key] == nil or now >= bot[key] then
		bot[key] = now + RandomFloat( minDelay or 0.3, maxDelay or 0.9 )
		return true
	end
	return false
end

-- Re-arm a window without firing (e.g. after an aborted attempt).
function human_lib.Arm( bot, key, minDelay, maxDelay )
	bot[key] = GameTime() + RandomFloat( minDelay or 0.3, maxDelay or 0.9 )
end

-- Imperfection dice: with `chance` probability skip the current window.
function human_lib.Skip( chance )
	if not human_lib.Enabled( 'Humanize' ) then return false end
	return RandomInt( 1, 100 ) <= math.floor( ( chance or 0.15 ) * 100 )
end

-- Aim/position jitter for harass and approach points.
function human_lib.Jitter( loc, radius )
	if not human_lib.Enabled( 'Humanize' ) then return loc end
	return loc + RandomVector( radius or 80 )
end

return human_lib
