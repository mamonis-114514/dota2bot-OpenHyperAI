#!/usr/bin/env python3
"""Structural patch-sync check against d2vpkr (dotabuff's extraction of the
current Dota 2 game data files, master = current patch).

Name-level checks:
  1. every "item_*" name referenced in FunLib/aba_item.lua + BotLib/*.lua
     is classified against the full items_game.txt universe:
       - virtual   : handled at runtime (tDefineItemRealName / item_double_* /
                     *_outfit / broken_satanic)
       - neutral   : exists in the neutral item pool (not buyable in shops)
       - shopless  : exists in items_game but NOT in shops.txt -> cannot be
                     purchased; stale if referenced in buy lists
       - DEAD      : not in items_game at all -> removed from the game
  2. neutral item tiers in Buff/NeutralItems.lua (TierNNeutralItems arrays)
     and FretBots/SettingsNeutralItemTable.lua ({name=..., tier=N} entries)
     against neutral_items.txt (current pool + tier placement),
  3. BotLib/hero_*.lua coverage against npc_heroes.txt #base list.

Usage: python tools/patch_sync_check.py [--offline]
  Files are cached in tools/d2vpkr_cache; delete the cache to re-download.
"""

import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "d2vpkr_cache")

BASE = "https://raw.githubusercontent.com/dotabuff/d2vpkr/master/dota/scripts"
FILES = {
    "shops": BASE + "/shops.txt",
    "neutral_items": BASE + "/npc/neutral_items.txt",
    "npc_heroes": BASE + "/npc/npc_heroes.txt",
    "npc_items": BASE + "/npc/items.txt",
}


def fetch(name):
    os.makedirs(CACHE, exist_ok=True)
    local = os.path.join(CACHE, name + ".txt")
    if os.path.exists(local):
        with open(local, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    print(f"[sync] downloading {name} ...")
    with urllib.request.urlopen(FILES[name], timeout=120) as r:
        data = r.read().decode("utf-8", errors="replace")
    with open(local, "w", encoding="utf-8") as f:
        f.write(data)
    return data


def strip_comments(text):
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


def read(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def block(text, start):
    """Return the {...} block body starting at the '{' index given."""
    depth, i = 0, start
    while i < len(text):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
        i += 1
    return text[start:]


def parse_shops(text):
    return set(re.findall(r'"item"\s+"(item_[a-z0-9_]+)"', strip_comments(text)))


def parse_items_game_keys(text):
    # npc/items.txt keys: "item_bfury"\n{\n  (also single-line brace form)
    return set(re.findall(r'"(item_[a-z0-9_]+)"\s*\{', text))


def parse_neutral_tiers(text):
    """neutral_items.txt 7.4x layout:
    "neutral_items" { "neutral_tiers" { "1" { ... "items" { "item_x" "1" } } } }"""
    text = strip_comments(text)
    tiers = {}
    m = re.search(r'"neutral_tiers"\s*\{', text)
    if not m:
        return tiers
    body = block(text, m.end() - 1)
    for tm in re.finditer(r'"(\d)"\s*\{', body):
        tier = int(tm.group(1))
        tbody = block(body, tm.end() - 1)
        im = re.search(r'"items"\s*\{', tbody)
        if not im:
            continue
        names = set(re.findall(r'"(item_[a-z0-9_]+)"', block(tbody, im.end() - 1)))
        tiers.setdefault(tier, set()).update(names)
    return tiers


def parse_repo_buff_tiers(path):
    text = strip_comments(read(path))
    tiers = {}
    for m in re.finditer(r"Tier(\d)NeutralItems\s*=\s*\{(.*?)\n\}", text, re.S):
        tiers[int(m.group(1))] = set(re.findall(r'"(item_[a-z0-9_]+)"', m.group(2)))
    return tiers


def parse_repo_fretbot_neutrals(path):
    """active (non-commented) {name="item_x", tier=N} entries"""
    tiers = {}
    for line in read(path).splitlines():
        stripped = line.strip()
        if stripped.startswith("--"):
            continue
        m = re.search(r'name="(item_[a-z0-9_]+)"\s*,\s*tier=(\d)', stripped)
        if m:
            tiers.setdefault(int(m.group(2)), set()).add(m.group(1))
    return tiers


def parse_virtual_names(aba_item_text):
    """keys of tDefineItemRealName + outfit/double/broken handling"""
    text = strip_comments(aba_item_text)
    m = re.search(r"tDefineItemRealName\s*=\s*\{", text)
    virtual = set()
    if m:
        virtual |= set(re.findall(r"\['(item_[a-z0-9_]+)'\]", block(text, m.end() - 1)))
    virtual |= {n for n in re.findall(r'"(item_[a-z0-9_]+)"', text)
                if n.endswith("_outfit") or n.startswith("item_double_")
                or n == "item_broken_satanic"}
    return virtual


def parse_heroes(text):
    return set(re.findall(r'#base\s+"heroes/(npc_dota_hero_[a-z0-9_]+)\.txt"', text))


def main():
    shops = parse_shops(fetch("shops"))
    neutral_tiers = parse_neutral_tiers(fetch("neutral_items"))
    game_heroes = parse_heroes(fetch("npc_heroes"))
    game_items = parse_items_game_keys(fetch("npc_items"))
    neutral_all = set().union(*neutral_tiers.values()) if neutral_tiers else set()

    print(f"[sync] d2vpkr: shops={len(shops)}, npc_items keys={len(game_items)}, "
          f"neutral pool={len(neutral_all)} (tiers {sorted(neutral_tiers)}), "
          f"heroes={len(game_heroes)}")

    failures = 0

    # ---- 1. repo item references ----
    aba_text = read(os.path.join(ROOT, "bots/FunLib/aba_item.lua"))
    virtual = parse_virtual_names(aba_text)
    repo_items = {}
    for m in re.finditer(r'"(item_[a-z0-9_]+)"', strip_comments(aba_text)):
        repo_items.setdefault(m.group(1), set()).add("aba_item.lua")
    botlib = os.path.join(ROOT, "bots", "BotLib")
    for fn in sorted(os.listdir(botlib)):
        for m in re.finditer(r'"(item_[a-z0-9_]+)"', strip_comments(read(os.path.join(botlib, fn)))):
            repo_items.setdefault(m.group(1), set()).add(fn)

    dead, shopless = [], []
    for name in sorted(repo_items):
        # runtime-mapped virtual names (aba_item tDefineItemRealName + generic
        # handlers for item_double_* / *_outfit / item_broken_satanic)
        if (name in virtual
                or name.startswith("item_double_")
                or name.endswith("_outfit")
                or name == "item_broken_satanic"):
            continue
        if name not in game_items:
            dead.append(name)
        elif name not in shops and name not in neutral_all:
            shopless.append(name)
    if dead:
        failures += 1
        print(f"\n[sync] DEAD item names referenced by repo ({len(dead)}):")
        for n in dead:
            print(f"  {n}   [{', '.join(sorted(repo_items[n])[:3])}]")
    if shopless:
        print(f"\n[sync] WARN: exists in game but not purchasable in shops and not "
              f"neutral ({len(shopless)}) — stale only if referenced in BUY lists:")
        for n in shopless:
            print(f"  {n}   [{', '.join(sorted(repo_items[n])[:3])}]")
    if not dead and not shopless:
        print("[sync] items: all repo item references resolve")

    # ---- 2. neutral tiers ----
    if not neutral_tiers:
        failures += 1
        print("[sync] FAIL: could not parse neutral_items.txt tiers")
    else:
        for rel, parser in (
            ("bots/Buff/NeutralItems.lua", parse_repo_buff_tiers),
            ("bots/FretBots/SettingsNeutralItemTable.lua", parse_repo_fretbot_neutrals),
        ):
            repo_t = parser(os.path.join(ROOT, rel))
            tier_moves = []
            for tier, names in sorted(repo_t.items()):
                gone = names - neutral_all
                moved = names & neutral_all - set().union(
                    *[v for k, v in neutral_tiers.items() if k == tier])
                if gone:
                    failures += 1
                    print(f"[sync] {rel}: tier {tier} DEAD names: {sorted(gone)}")
                wrong_tier = {n for n in (names & neutral_all)
                              if n not in neutral_tiers.get(tier, set())}
                if wrong_tier:
                    tier_moves.append((tier, sorted(wrong_tier)))
            if tier_moves:
                failures += 1
                print(f"[sync] {rel}: tier placement mismatch vs current pool:")
                for tier, names in tier_moves:
                    actual = {n: next((t for t, ns in sorted(neutral_tiers.items())
                                       if n in ns), "?") for n in names}
                    print(f"  repo tier {tier} -> actual tiers: {actual}")

    # ---- 3. hero coverage ----
    botlib_heroes = {f[5:-4] for f in os.listdir(botlib) if f.startswith("hero_")}
    unmatched = sorted(h for h in botlib_heroes
                       if f"npc_dota_hero_{h}" not in game_heroes)
    print(f"\n[sync] game heroes: {len(game_heroes)}, BotLib files: {len(botlib_heroes)}")
    if unmatched:
        print(f"[sync] NOTE (aliases expected): {unmatched}")
    missing_files = sorted(h for h in game_heroes
                           if h.replace("npc_dota_hero_", "") not in botlib_heroes
                           and h not in {"npc_dota_hero_base", "npc_dota_hero_target_dummy"})
    if missing_files:
        failures += 1
        print(f"[sync] game heroes WITHOUT BotLib file: {missing_files}")

    if failures:
        print(f"\n[sync] FAIL: {failures} discrepancy group(s)")
        return 1
    print("\n[sync] PASS: no structural discrepancies")
    return 0


if __name__ == "__main__":
    sys.exit(main())
