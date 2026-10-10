# Offline validation tools

本目录提供无 Dota 2 环境下的离线验证（Python 3.12 + lupa/LuaJIT）。

## smoke_test.py — 语法 + 冒烟测试

```
python tools/smoke_test.py            # 语法检查 + 运行时冒烟
python tools/smoke_test.py --syntax   # 仅语法检查
```

流程：
1. `syntax_check.py`：用 LuaJIT 编译 `bots/`、`game/`、`tools/` 下全部 Lua 文件；
2. 加载 `valve_api_stubs.lua`（mock 引擎 API：GetBot/GetTeam/DotaTime/Action_*/枚举/假单位对象等）；
3. 依次加载并调用：FunLib、Customize、全部 `mode_*_generic.lua`（4 个游戏时间点各调一次
   `GetDesire()`+`Think()`）、`bot_generic`、`ability_item_usage_generic`（5 个 think 入口）、
   `item_purchase_generic`、`hero_selection`；
4. 全部 128 个 `BotLib/hero_*.lua` 在**独立环境**中加载（模拟引擎 per-bot 沙盒），先调
   `OnStart`/`SkillsComplement`/`MinionThink`，再扫全部无参 `Consider*` 函数。

退出码 0 = 全部通过。改动任何 bot 代码后必须先跑本测试。

已知限制：
- mock 只做"不崩溃"级别的校验，不证明玩法正确性；
- FretBots 主入口、Buff 模式、`game/` 引擎胶水未纳入运行时阶段；
- 带参数的 `Consider*(ability, target, ...)` 不裸调（真实调用由 SkillsComplement 传参）；
- 死代码白名单见 smoke_test.py 顶部 `NOISE_WHITELIST`。

## valve_api_stubs.lua

mock 环境要点：`CDOTA_Bot_Script` 以惰性代理模拟（aba_global_overrides 会 monkey-patch 它）；
`dofile` 自动补 `.lua`（与 Valve 沙盒一致）；Vector 支持算术与 `:Normalized()`；
天赋槽位（slot ≥ 10）返回带 `IsTalent()==true` 的技能对象。

## patch_sync_check.py — 补丁结构比对（Phase 0.5）

```
python tools/patch_sync_check.py
```

拉取 d2vpkr（dotabuff 提取的当前版本游戏数据）的 `shops.txt` / `neutral_items.txt` /
`npc_heroes.txt`，与仓库的 `aba_item.lua` 物品清单、`Buff/NeutralItems.lua` +
`FretBots/SettingsNeutralItemTable.lua` 中立物品表、`BotLib/hero_*.lua` 英雄覆盖做结构比对，
报告：物品缺失/多余、中立物品调层、英雄缺失。需联网（仅开发时）。
