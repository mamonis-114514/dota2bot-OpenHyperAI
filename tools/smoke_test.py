#!/usr/bin/env python3
"""Offline smoke test for the OpenHyperAI bot scripts.

Loads tools/valve_api_stubs.lua into a Lua runtime, then:
  1. runs syntax_check.py (all files compile),
  2. dofile's every bot entry file (FunLib, Customize, mode_*, item purchase,
     ability/item usage, hero selection) and calls its think functions over a
     few simulated frames at several game times,
  3. loads all 128 BotLib hero files in fresh per-file environments (like the
     engine does) and calls their SkillsComplement / Consider* / MinionThink.

This does NOT prove gameplay correctness — it catches load-time and
shallow-runtime errors (nil indexing, missing globals, bad requires, typos)
without a Dota 2 install. Exit code 0 = no failures.

Usage:
  python tools/smoke_test.py            # syntax + runtime
  python tools/smoke_test.py --syntax   # syntax only
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BOTS = os.path.join(ROOT, "bots")
os.environ["MOCK_SCRIPT_DIR"] = BOTS.replace("\\", "/")

MAX_ERRORS_PRINTED = 40

# (file, function) pairs that are known dead code under the mock: the real
# SkillsComplement cascade never calls them (e.g. commented-out branches), but
# the harness sweeps every no-arg Consider function it finds.
NOISE_WHITELIST = {
    ("hero_luna.lua", "ConsiderMoonGlaives"),
}


def whitelisted(name, err):
    if not err:
        return False
    fn = err.split(" :: ", 1)[0]
    return (name, fn) in NOISE_WHITELIST


def get_runtime():
    try:
        from lupa.luajit21 import LuaRuntime  # noqa
        return LuaRuntime(unpack_returned_tuples=True), "luajit21"
    except ImportError:
        pass
    try:
        from lupa.luajit import LuaRuntime  # noqa
        return LuaRuntime(unpack_returned_tuples=True), "luajit"
    except ImportError:
        pass
    from lupa import LuaRuntime
    return LuaRuntime(unpack_returned_tuples=True), "lupa-default"


def read_source(path):
    with open(path, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    return raw.decode("latin-1")


class Reporter:
    def __init__(self):
        self.errors = []
        self.calls = 0

    def add(self, tag, err):
        self.errors.append(f"{tag} :: {err}")

    def report(self):
        print(f"\n[smoke] runtime calls: {self.calls}")
        if self.errors:
            print(f"[smoke] FAIL: {len(self.errors)} error(s)")
            for i, e in enumerate(self.errors):
                if i >= MAX_ERRORS_PRINTED:
                    print(f"  ... and {len(self.errors) - MAX_ERRORS_PRINTED} more")
                    break
                print(f"  {e}")
            return 1
        print("[smoke] PASS")
        return 0


LUA_BOOTSTRAP = r"""
HARNESS = {}
local function rawload(src, name)
    if loadstring then return loadstring(src, name) end
    return load(src, name)
end

-- Run an entry file in _G (engine runs each entry file per bot in its own env
-- whose globals fall back to a shared layer; for smoke purposes _G is fine).
function HARNESS.run_entry(src, name, fn_names)
    local f, err = rawload(src, name)
    if not f then return "LOAD", tostring(err) end
    local ok, err2 = pcall(f)
    if not ok then return "INIT", tostring(err2) end
    for _, fn in ipairs(fn_names or {}) do
        local g = rawget(_G, fn)
        if type(g) == "function" then
            local ok3, err3 = pcall(g)
            HARNESS_CALLS = (HARNESS_CALLS or 0) + 1
            if not ok3 then return "CALL:" .. fn, tostring(err3) end
        end
    end
    return "OK", nil
end

-- Load a BotLib hero file in a fresh environment, then call its X functions.
function HARNESS.run_hero(src, name, minion)
    local f, err = rawload(src, name)
    if not f then return "LOAD", tostring(err), 0, {} end
    local env = setmetatable({}, { __index = _G })
    if setfenv then setfenv(f, env) else f = load(src, name, "t", env) end
    local ok, X = pcall(f)
    if not ok then return "INIT", tostring(X), 0, {} end
    if type(X) ~= "table" then return "NO_X", "did not return a table", 0, {} end
    local errs, calls = {}, 0
    local function nparams(fn)
        if debug and debug.getinfo then
            local oki, info = pcall(debug.getinfo, fn, "u")
            if oki and type(info) == "table" then
                return info.nparams or info.params or 0
            end
        end
        return 0
    end
    local function call_report(fn, tag, ...)
        calls = calls + 1
        local okc, e2 = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end, ...)
        if not okc then errs[#errs + 1] = tag .. " :: " .. tostring(e2) end
    end
    -- Run entry points first (they initialize globals the Consider functions read)
    for _, k in ipairs({ "OnStart", "SkillsComplement", "MinionThink" }) do
        local v = X[k]
        if type(v) == "function" then call_report(v, k, minion) end
    end
    for k, v in pairs(X) do
        if type(v) == "function" and string.sub(k, 1, 8) == "Consider" then
            -- Consider functions with parameters expect ability/target arguments
            -- supplied by SkillsComplement; calling them bare would only produce
            -- mock noise, so only no-arg Consider functions are exercised here.
            if nparams(v) == 0 then call_report(v, k) end
        end
    end
    return "OK", nil, calls, errs
end
"""


def run_entry(lua, rep, path, fn_names, times=(30.0, 300.0, 900.0, 1500.0)):
    rel = os.path.relpath(path, ROOT)
    src = read_source(path)
    lua.globals().MOCK_SRC = src
    lua.globals().MOCK_CHUNK = "@" + rel.replace("\\", "/")
    for t in times:
        lua.execute(f"MOCK_SetTime({t})")
        fn_table = "{" + ",".join('"%s"' % f for f in fn_names) + "}"
        status, err = lua.eval('HARNESS.run_entry(MOCK_SRC, MOCK_CHUNK, %s)' % fn_table)
        rep.calls += 1
        if status != "OK":
            rep.add(f"{rel} [t={t} {status}]", err)
            return  # a load/init failure will repeat for every time slice


def main():
    syntax_only = "--syntax" in sys.argv
    lua, rtname = get_runtime()
    rep = Reporter()
    print(f"[smoke] runtime: {rtname}")

    # ---- 1. syntax (in-process) ----
    sys.path.insert(0, HERE)
    import syntax_check
    rc = syntax_check.main()
    if rc != 0:
        print("[smoke] syntax failed, aborting runtime phase")
        return 1
    if syntax_only:
        return 0

    # ---- 2. boot stub environment ----
    lua.execute('package.path = "?.lua;" .. (package.path or "")')
    stub_src = read_source(os.path.join(HERE, "valve_api_stubs.lua"))
    lua.execute(stub_src)
    lua.execute(LUA_BOOTSTRAP)
    lua.execute('HARNESS.minion = GetBot()')  # any mock unit works as a minion

    # ---- 3. FunLib + Customize ----
    for rel in [
        "bots/Customize/general.lua",
        "bots/FunLib/jmz_func.lua",
    ]:
        path = os.path.join(ROOT, rel)
        lua.globals().MOCK_SRC = read_source(path)
        lua.globals().MOCK_CHUNK = "@" + rel.replace("\\", "/")
        status, err = lua.eval('HARNESS.run_entry(MOCK_SRC, MOCK_CHUNK, {})')
        rep.calls += 1
        if status != "OK":
            rep.add(f"{rel} [{status}]", err)

    # require-check the J library resolves into the global J
    try:
        lua.execute('J = require(GetScriptDirectory().."/FunLib/jmz_func"); '
                    'assert(type(J) == "table", "jmz_func did not load into J")')
    except Exception as e:  # noqa
        rep.add("FunLib/jmz_func [require]", str(e))

    # ---- 3b. SmartPlay modules: direct exercises ----
    lua.execute(r'''
SP_CHECKS = {}
local function spcheck(name, fn)
    local ok, err = pcall(fn)
    SP_CHECKS[#SP_CHECKS + 1] = { name, ok, err }
end
spcheck("human_lib.Enabled", function()
    local H = require(GetScriptDirectory()..'/FunLib/human_lib')
    assert(H.Enabled('Laning_Micro') == true)
    assert(H.Enabled(nil) == true)
    local b = GetBot()
    assert(H.Ready(b, 't1', 0.1, 0.2) == true)
    assert(H.Ready(b, 't1', 0.1, 0.2) == false)
end)
spcheck("draft_lib.profile+adjust", function()
    local D = require(GetScriptDirectory()..'/FunLib/draft_lib')
    local p = D.GetEnemyProfile()
    assert(type(p) == 'table' and type(p.names) == 'table')
    local bot = GetBot()
    local list = { "item_tango", "item_magic_wand", "item_power_treads",
                   "item_maelstrom", "item_skadi" }
    local adjusted, changes = D.AdjustBuyList(bot, list, 4)
    assert(type(adjusted) == 'table' and type(changes) == 'table')
end)
spcheck("gank_lib.plan+dive+missing", function()
    local G = require(GetScriptDirectory()..'/FunLib/gank_lib')
    local bot = GetBot()
    local plan = G.GetActiveSmokePlan(bot)
    assert(plan == nil or type(plan) == 'table')
    local dive = G.GetTowerDive(bot)
    assert(dive == nil or type(dive) == 'table')
    assert(type(G.EnemiesMostlyMissing()) == 'boolean')
    assert(type(G.TowerCountAdvantage()) == 'number')
    G.UpdateWarnings(bot)
end)
spcheck("camp_lib.bonus+intercept", function()
    local C = require(GetScriptDirectory()..'/FunLib/camp_lib')
    local bot = GetBot()
    assert(type(C.StackDesireBonus(bot)) == 'number')
    assert(type(C.PullDesireBonus(bot)) == 'number')
    assert(type(C.DesireBonus(bot)) == 'number')
    assert(C.FarmIntercept(bot) == false)
end)
spcheck("laning_lib.harass+miss", function()
    local L = require(GetScriptDirectory()..'/FunLib/laning_lib')
    local bot = GetBot()
    assert(L.EnemyCreepAggroOn(bot) == false)
    assert(type(L.GetLaneState(bot, {}, {})) == 'string')
    assert(L.ThinkHarass(bot, {}, {}, {}, 1) == false)
    L.UpdateMissCall(bot, {}, 1)
end)
''')
    sp_checks = lua.globals().SP_CHECKS
    for i in range(1, len(sp_checks) + 1):
        name, ok, err = sp_checks[i][1], sp_checks[i][2], sp_checks[i][3]
        rep.calls += 1
        if not ok:
            rep.add(f"SmartPlay/{name}", str(err))

    # ---- 4. mode files ----
    mode_files = sorted(
        f for f in os.listdir(BOTS)
        if f.startswith("mode_") and f.endswith("_generic.lua") and not f.startswith("--")
    )
    mode_fns = ["GetDesire", "Think"]
    for fn in mode_files:
        run_entry(lua, rep, os.path.join(BOTS, fn), mode_fns)

    # ---- 5. per-bot entry files (mock bot = juggernaut) ----
    for rel, fns in [
        ("bots/bot_generic.lua", ["MinionThink"]),
        ("bots/ability_item_usage_generic.lua",
         ["AbilityUsageThink", "ItemUsageThink", "BuybackUsageThink",
          "CourierUsageThink", "AbilityLevelUpThink"]),
        ("bots/item_purchase_generic.lua", ["ItemPurchaseThink"]),
        ("bots/hero_selection.lua", ["Think", "UpdateLaneAssignments"]),
    ]:
        run_entry(lua, rep, os.path.join(ROOT, rel), fns)

    # ---- 6. all BotLib hero files in fresh envs ----
    botlib = os.path.join(BOTS, "BotLib")
    hero_files = sorted(f for f in os.listdir(botlib) if f.endswith(".lua"))
    lua.execute("HERO_ERRS = {}")
    for fn in hero_files:
        path = os.path.join(botlib, fn)
        lua.globals().MOCK_SRC = read_source(path)
        lua.globals().MOCK_CHUNK = "@bots/BotLib/" + fn
        lua.execute(
            'local st, err, calls, errs = HARNESS.run_hero(MOCK_SRC, MOCK_CHUNK, HARNESS.minion); '
            'table.insert(HERO_ERRS, { st, err, calls, errs, MOCK_CHUNK })'
        )
    hero_errs = lua.globals().HERO_ERRS
    n_hero_fail = 0
    for i in range(1, len(hero_errs) + 1):
        row = hero_errs[i]
        st, err, calls, errs = row[1], row[2], row[3], row[4]
        rep.calls += int(calls)
        name = f"bots/BotLib/{hero_files[i - 1]}"
        if st != "OK":
            n_hero_fail += 1
            rep.add(f"{name} [{st}]", err)
        else:
            for e in errs.values():
                if whitelisted(hero_files[i - 1], e):
                    continue
                rep.add(name, e)

    return rep.report()


if __name__ == "__main__":
    sys.exit(main())
