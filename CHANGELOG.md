# Changelog

## 0.7.41f.2 - 2026/10/10 — SmartPlay 博弈强度层（对线/团队/出装 BP）

在不给 bot 任何数值加成的前提下，为 bot 增加一层"游戏理解"决策（目标水平：统帅 ~3000 分）。
所有新能力由 `Customize/general.lua` 的 `SmartPlay` 开关块独立控制（默认全开），攻击性行为
统一带 0.3~1.4s 随机反应延迟 + 小概率放弃窗口（拟人化，且绝不套用于既有的逃生/救人逻辑）。

### 新增模块（全部纯 Lua，无 TS 依赖）

| 文件 | 职责 |
|---|---|
| `FunLib/human_lib.lua` | SmartPlay 开关访问器 + 反应延迟/抖动/失误骰子（J.Human） |
| `FunLib/laning_lib.lua` | 小兵仇恨感知与卸除、有纪律的骚扰、兵线状态估计、miss 报点 |
| `FunLib/camp_lib.lua` | x:50-55 堆野状态机、4/5 号位拉野控线状态机（人类玩家靠近时让位） |
| `FunLib/gank_lib.lua` | 计划性开雾（分钟锚点，10 沙盒确定性一致）、敌方集体消失推理、塔下强杀检测、防御塔优势统计 |
| `FunLib/draft_lib.lua` | 敌方阵容画像（隐身/强治疗/幻象/引导大招/强先手/闪避/召唤）+ 条件出装规则引擎 |
| `FunLib/meta_weights.lua` | 由 `tools/fetch_meta.py` 生成的统帅分段胜率表（127 英雄，OpenDota 数据烘焙） |

### 对线细节（Phase 1）

- **仇恨管理**：检测小兵是否正在攻击自己；骚扰后点己方小兵卸仇恨（带 10% "慌乱"概率直接走位）。
- **骚扰框架**：远程在血量占优（≥10% 血量差或目标 ≤35%）且不在敌塔下时从最大射程点射；
  近战只收人头或目标落单；反补/补刀永远优先于骚扰；反应延迟 + 12% 放弃窗口。
- **反补强化**：从"血量 <49% 且一刀能打掉"升级为弹道飞行时间预测（`WillKillTarget`），
  敌方英雄在附近时优先反补剥夺经验。
- **堆野**：每分钟 :50-:55，附近有野营地的 bot（核心与辅助皆可，12 级以下不打大野/远古）
  进入拖野流程，:57 起脱离刷新点，:00 后回去清双倍野。
- **拉野**：4/5 号位在兵线被推到敌方一塔 1800 码内、且同侧小/中型野怪营地 2500 码内时，
  :15-:45 把野怪拉进兵线回拉均势；带 14s 超时 + 30s 失败冷却。
- **拟人化让位**：人类玩家在营地 900 码内时 bot 完全让出该营地（2 人局你打 4 号位时 bot 不会和你抢野）。
- **miss 报点**：对线对手离开视野 >4s 时，同路 playerID 最小的 bot 发送"上路/中路/下路miss！"（四语言）。

### 团队博弈（Phase 2）

- **计划性开雾**：第 9/13/17/21/25/29/33/37 分钟的锚点窗口内，若不在推高地/守家状态、
  己方存活 ≥4 且不少于敌方，自动选择"20s 内失去视野、距敌方塔 >1100 码"的敌方核心/法系目标
  生成开雾计划；有雾的 bot 在 ≥2 队友在附近时施放，最低 playerID 的 bot 发"开雾抓人！"并 ping 目标位置；
  roam/team_roam 欲望在计划期间提升到 0.85 让全队跟进。
- **TP 反蹲**：己方英雄在本方塔 900 码内被 ≥2 名敌人攻击（近期受伤或残血）时，
  距离 >2500 码且自身健康的 bot 以绝对欲望 TP 落塔后反打，并 ping 塔的位置（45s 节流）。
- **换资源决策**：某路兵线前沿出现 ≥4 敌人而守军 ≤2 时（且本方基地不受威胁），
  8 秒滞回内把该路防守欲望压到 0.45，不再集体送死回防；最低 playerID 的 bot 发
  "守不住了，换路推！"。挂载于 `J.GetDefendLaneDesire` 包装层（纯 Lua 层，未动 TS 的 aba_defend）。
- **敌方集体消失推理**：≥3 名存活敌人失踪 >12s 时，每 60s 发"小心，敌人全消失了！"警告。
- **视野压力**：防御塔数量领先 ≥2 时，辅助的插眼欲望提升至至少 0.5（保持进攻视野跟进）。

### 出装与 BP 适应（Phase 3）

- **条件出装**（每次最多 3 处改动，`[DraftAdapt]` 前缀日志可查）：
  敌方 ≥2 强治疗 → 寂灭宝珠（Spirit Vessel）；敌幻象系 + 我近战核心 → 狂战斧；
  敌闪避系 → 金箍棒；敌 ≥2 引导大招 + 我中单 → 紫怨；敌强先手 ≥2 → 黑皇杖提前/补入。
- **BP 权重**：`tools/fetch_meta.py` 从 OpenDota 拉取统帅分段（b4*0.65+b5*0.35 加权）胜率，
  烘焙进选人评分（±10% 温和偏置，位置权重/克制关系仍是主导）。
  STRATZ token 存于 `tools/stratz_token.local`（已 gitignore），`--stratz` 可切换数据源（严控调用次数）。

### 拟人化（Phase 4）

- 所有新增攻击性行为（骚扰/拉野/开雾跟进）统一走 `J.Human` 反应延迟与失误骰子。
- bot 主动 ping：开雾目标位置、被强杀的塔位（带分钟/45s 节流）。
- 新聊天文案全部进入四语言表（en/zh/ru/ja）；默认语言改为 `zh`（`Customize.Localization`）。

### 配置开关（`Customize/general.lua` → `Customize.SmartPlay`）

`Enable` 总开关；`Laning_Micro`（仇恨/骚扰/反补）、`Pull_And_Stack`（堆野拉野）、
`Team_Coordination`（开雾/反蹲/换资源/警告）、`Draft_Adaptive_Items`（条件出装）、
`Meta_BP`（胜率偏置）、`Humanize`（拟人化噪声）、`Laning_All_Heroes`（**实验性**：
让全部英雄改用脚本对线逻辑而非引擎内置对线，默认关闭，供对比测试）。

### 明确的范围限制（诚实声明）

- **骚扰/反补/仇恨逻辑目前只对"脚本对线"的 bot 生效**（Valve 判定的 bug 英雄 + 实验开关打开后的全部英雄）。
  其余英雄的对线由引擎 C++ 内置逻辑负责，无法从 Lua 层安全注入攻击指令（会与每帧的模式指令打架）。
  请用 `Laning_All_Heroes = true` 对比测试后决定是否默认打开。
- 堆野/拉野依赖 `GetNeutralSpawners()` 引擎数据与 `ActionQueue` 指令语义，离线只能验证不崩溃，
  实际拖野成功率需要在游戏里观察（所有尝试都有超时回退，失败不会卡死 bot）。
- 开雾计划的"跟进"是通过提升 roam 欲望实现的，bot 到达目标附近后的具体包抄仍由既有 roam 逻辑决定。

### 工具链（Phase 0，见上一版本说明）

- `tools/smoke_test.py`（语法 + 冒烟 + SmartPlay 模块直检，当前 981 次运行时调用全绿）、
  `tools/patch_sync_check.py`（d2vpkr 结构比对）、`tools/fetch_meta.py`（meta 数据烘焙）。

## 0.7.41f.1 - 2026/10/10 — 补丁同步 7.41a → 7.41f + 离线验证基建

本版本将脚本同步到游戏当前补丁 7.41f（依据 [Liquipedia 7.41b–7.41f 版本页](https://liquipedia.net/dota2/Main_Page) 与 d2vpkr 当前游戏数据），并建立无 Dota 2 环境下的离线验证工具链。

### 新增：tools/ 离线验证（无游戏环境可跑）

- `tools/smoke_test.py`：加载 mock 引擎 API（`valve_api_stubs.lua`）后，依次加载 FunLib / Customize / 全部 mode 文件（4 个游戏时间点） / 5 个引擎入口 / 全部 128 个 BotLib 英雄文件（独立沙盒环境），调用其 think 与 Consider 函数，捕获运行时错误。
- `tools/syntax_check.py`：LuaJIT 编译检查全部 Lua 文件。
- `tools/patch_sync_check.py`：拉取 d2vpkr（当前版本游戏数据）比对仓库物品名 / 中立物品分层 / 英雄覆盖，报告死物品名与调层。每次游戏出新补丁后运行即可定位需同步项（文件缓存在 `tools/d2vpkr_cache/`，删除即重新下载）。
- 用法见 `tools/README.md`。

### 清理

- 删除 `bots/--mode_item_generic.lua`（文件名损坏、从未被引擎加载、内容恒返回无欲望的死 stub）。
- 删除 `bots/mode_retreat_generic_wip.lua`（无任何引用的废弃实现）。

### 修复（真实 bug）

- **Tinker**：`hero_tinker.lua` 8 处 `J.Utils.GetItem('item_x')` 缺少 `bot` 参数（正确签名 `GetItem(bot, itemName)`）→ Tinker 的灵魂戒指 / 希瓦 / 羊刀 / 虚灵刀判定每帧报脚本错误且永远无法施放。现修复。
- **Tidehunter**：出装表中的 `item_great_scepter` 在当前游戏数据中不存在（后一行已是 `item_ultimate_scepter`，疑为笔误残留）→ 购买会失败。已删除该行。
- **aba_item.lua**：`item_drum_of_endurance` 已在当前版本被彻底移除（d2vpkr npc_items 无定义），从卖出配对表中删除。

### 修复（7.41b 回归）

- **Invoker**：7.41b 起 Invoke 在 6/12/18 级奖励技能点，导致 ARDM / `!pos` 换位重建时 `level - abilityPoints` 的已花点数裁剪偏少 1~3 条、反复尝试升级已满技能。改为按技能槽位等级求和统计（对所有英雄都更精确）。

### 已核实无需改动（避免无谓风险）

- **物品/中立物品**：7.41b–f 无物品增删改名、无中立物品调层；`Buff/NeutralItems.lua` 与 `FretBots/SettingsNeutralItemTable.lua` 与当前 7.41f 中立池完全一致（`patch_sync_check` 验证）。
- **英雄覆盖**：游戏 129 个英雄（含 Largo / Kez / Ringmaster），BotLib 128 文件全覆盖（`lone_druid_bear` 为有意别名）。已知怪癖：Largo 仅 3 行天赋、Kez 天赋槽位非标准——均为 7.41 本体特性，非 b–f 回归。
- **天赋表（15 个受影响英雄逐一核对）**：纯级别对调（Alchemist/Arc Warden/Doom/Meepo/Bounty Hunter/Earth Spirit 的 20↔25、10↔15 等）不会破坏本仓库按位置选人的逻辑——被对调的两个天赋本就是作者在同一侧同时选中的，只是获取等级对调；替换类天赋（Puck/Lone Druid/Tiny/Venomancer/Kez/Snapfire/Legion Commander/Treant 等）逐个人工评估，新效果均适配 bot 玩法（如 Snapfire 15 级 +125 施法距离对 bot 更优）。**结论：无需修改任何 `tTalentTreeList`。**
- **Morphling 波形**（7.41c 全局施法）：KV 施法距离仍为 700–925，`J.GetProperCastRange` 对全局值优雅退化，现有逻辑功能完好。
- **Storm Spirit 充能公式 / Muerta 层数公式**（7.41c）：仓库使用引擎动态取值（`GetLevel`/`GetSpecialValueInt`），自动跟随，无硬编码。
- **Medusa/Zeus 开关技能不再被沉默禁用**（7.41e）：仓库无相关沉默门控，无需清理。
- **TP 自施法落点**（7.41d）：引擎侧行为，脚本无感。
- **水符使用/争议符规避**：`mode_rune_generic.lua` 已有"残血/缺蓝喝水符"与"敌人可能拿符"判断，无需重复建设。

### 已知待办

- `patch_sync_check` 的 25 个 WARN（定义存在但商店不可购）均只出现在 `aba_item.lua` 物品目录表或运行时映射良好的合成变体（dagon_2、ultimate_scepter_2、travel_boots_2 等），不影响购买主链路；不出装列表引用。
- d2vpkr master 的数据新鲜度以抓取日为准；每次新补丁后重跑 `tools/patch_sync_check.py`。
