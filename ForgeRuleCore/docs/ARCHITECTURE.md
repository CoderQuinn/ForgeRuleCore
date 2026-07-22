# ForgeRuleCore 架构与契约

> **角色**：不可变快照式 **routing / geo rule kernel** — `RuleEngine.evaluate` → Direct / Proxy / Reject  
> **QuantumLink 中的位置**：L3 策略 — TCP accept + dial 决策 **之后**  
> **当前兼容级别**：Xray / Surge 风格规则的 **narrow 子集**，不承诺完整兼容  
> **成熟度**：MVP kernel（核心匹配可用）；生产接入前须处理 MMDB 生命周期与 compiler 诊断  
> **最后更新**：2026-07-19  
> **审查依据**：[技术文案.md](./技术文案.md)

---

## 1. 职责边界

| 做 | 不做 |
|----|------|
| 加载 `geosite.json` / `geoip.mmdb` | DNS 应答、DoH、fallback / `expectIPs` 编排（EchoForge / DNS service） |
| 域名、后缀、关键字、GeoSite、GeoIP 匹配 | 包转发、socket 生命周期（NetForge） |
| 将 `RuleInput` 评估为 `RuleAction` / `RouteDecision` | NE / UI / 持久化配置管理（QuantumLink） |
| Flow 侧事实解析适配（`FlowFactsResolver`） | 规则订阅下载、文件更新策略 |
| Xray-style routing / DNS **JSON 子集解码** | 完整 Xray / Surge 规则方言 |

**设计原则**：包内只保留「加载 → 不可变快照 → 纯评估」；热更新、编排、策略类型映射由上层完成。

---

## 2. 运行时数据流

```
                    ┌─────────────────────────────────────┐
  raw flow          │         FlowRuleClassifier          │
  RuleInput ───────►│  resolve facts  →  RuleCore.route   │───► RouteDecision
  (factsResolved=false)        │              │           │
                    └──────────┼──────────────┼───────────┘
                               ▼              ▼
                      FlowFactsResolver   RuleEngine
                      (domain / FakeIP)   (顺序匹配)
                               │              │
                               │         ┌────┴────┐
                               │         ▼         ▼
                               │    GeoSiteDB   GeoIPDB
                               │         │         │
                               │    Matchers   CountryLookup
                               │              (MMDBReader)
                               ▼
                      match-ready RuleInput
                      (factsResolved=true)
```

装配入口（App Group）：

```
ForgeRuleCoreBundle.makeRuleCore / makeFlowClassifier
  → geosite.json + geoip.mmdb
  → GeoSiteDB + GeoIPDB(preheatKeys) + RuleEngine
```

---

## 3. Target 结构

```
libmaxminddb (C)
  └── GeoMMDBBridge          ← 进程级 g_db + refcount（已知约束，见 §6）
        └── ForgeRuleCore
              ├── Core       Rule, RuleEngine, Flow*, Config, Bundle
              ├── Geo        GeoSiteDB, GeoIPDB
              ├── Matchers   DomainExactSet, DomainSuffixTrie, DomainKeywordMatcher
              └── Adapters   CountryLookup
```

| 层 | 职责 | 现状评价 |
|----|------|----------|
| Kernel | 顺序评估 `Rule` → `RuleAction` | 稳定；Sendable 快照合适 |
| Flow Adapter | FakeIP / domain 事实解析 | 边界清楚，可注入 |
| Config Compiler | JSON field → `[Rule]` | narrow 可用；缺 diagnostics |
| GeoSite | 按站点建 full/suffix/keyword 索引 | 子集；`regex` / attributes 忽略 |
| GeoMMDB | IPv4 → 国家码 | **风险高**：全局单例 |

---

## 4. 稳定契约

### 4.1 Public Kernel（稳定面）

面向集成方，视为 **stable**：

| API | 说明 |
|-----|------|
| `Rule` / `RuleCondition` / `RuleAction` | 规则原语 |
| `RuleInput` | 评估输入 |
| `RuleEngine` / `RuleCore` | 评估与路由 |
| `FlowRuleClassifier` / `FlowFactsResolving` / `FakeIPStore` | Flow 适配 |
| `GeoSiteDB` / `GeoIPDB` / `CountryLookup` | Geo 依赖与注入点 |
| `FieldRoutingRuleFactory` + routing/DNS JSON DTO | 配置编译与解码 |
| `ForgeRuleCoreBundle` | App Group 装配 |
| `normalizeDomain` / `normalizeGeoipKey` | 规范化工具 |

**非 stable / 易变（当前仍 public，计划收窄）**：`DomainSuffixTrie` 等 matcher 内部结构、`MMDBReader` / `GeoIPProvider`、`GeoSite` JSON 细节模型。外部请勿依赖其布局或生命周期细节。

```swift
public final class RuleEngine: Sendable {
    public init(rules: [Rule], geosite: GeoSiteDB, geoip: GeoIPDB)
    public func evaluate(_ input: RuleInput) -> RuleAction
}
```

`RuleInput` 字段：

| 字段 | 引擎是否消费 | 说明 |
|------|--------------|------|
| `domain` | ✅ | 规范化后参与域名 / geosite 匹配 |
| `resolvedIP` | ✅ | 仅用于 `.geoip` |
| `originalIP` | ❌ | 保留给上层 / FakeIP 上下文 |
| `port` | ❌ | **reserved**；组合条件未接线 |
| `proto` | ❌ | **reserved**；`network` 未接线 |
| `factsResolved` | ❌ | 元数据；`evaluate` 不据此分支 |

### 4.2 Evaluation Semantics

1. **不可变快照**：`RuleEngine` 初始化后 `rules` / geosite / geoip 引用不变；reload 必须由外层 atomic snapshot swap 完成（当前无内置 reload API）。
2. **自规范化**：`evaluate` **始终**对 `domain` 做 `normalizeDomain`（小写、去首尾空白与 `.`）；空串视为 `nil`。调用方无需依赖「已 resolve」才能安全评估，但 Flow 路径仍应先 `resolve` 以补全 FakeIP 域名。
3. **顺序扫描**：按规则数组顺序。
4. **首个非 `.any` 命中即返回**。
5. **`.any` = 可覆盖的 fallback**：命中后更新默认动作并 **继续** 扫描；其后具体规则可覆盖。  
   - **推荐写法**：将 `.any`（FINAL 意图）放在列表 **末尾**，且其后不再放规则。  
   - **非 Surge 字面语义**：Surge `FINAL` 习惯是「最后一条且终止」；本引擎允许 `.any` 靠前作为默认可被覆盖动作。
6. **默认动作**：无任何命中（且无 `.any` 写入）时返回 `.direct`。
7. **域名类条件**在 `domain == nil` 时不命中。
8. **`.geoip` 仅看 `resolvedIP`**，不看 `originalIP`。
9. **`FlowRuleClassifier`**：先 `FlowFactsResolving.resolve`，再 `RuleCore.route`。

### 4.3 Geo 匹配语义

**GeoSite**（`GeoSiteDB.contains`）单站点内顺序：

1. `full`（`DomainExactSet`）
2. `domain` / suffix（`DomainSuffixTrie`）
3. `plain` / keyword（`DomainKeywordMatcher` 线性扫描）

- 站点名与域名均经 `normalizeDomain`。
- 数据里的 `regex` 类型：**忽略**（DEBUG 下可能打印）。
- `attributes`：解码但不参与匹配。

**GeoIP**（`GeoIPDB.match`）：

| Key | 行为 |
|-----|------|
| `cc` / `cn` | 国家码相等则命中；lookup miss → **不命中** |
| `!cc` / `!cn` | 对正匹配取反；lookup miss 时正匹配为 false，故 **`!cc` 命中** |
| 空 / 非法码 | 不命中 |

> **契约（写死）**：`geoip:!cn` 表示「不是明确的 CN」，包含「查不到国家」的 IP（私网、缺失库、未知段）。若业务需要「明确非 CN」，须在上层先过滤 lookup miss。

Preheat：`preheatKeys` 只缓存去掉 `!` 后的正国家码解析结果。

### 4.4 条件支持矩阵

| 条件 | 状态 | 入口 |
|------|------|------|
| DOMAIN / full | ✅ | `domainFull`，config `full:` |
| DOMAIN-SUFFIX | ✅ | `domainSuffix`，`domain:` 或无前缀 |
| DOMAIN-KEYWORD | ✅ | `domainKeyword`，`keyword:` |
| GEOSITE | ⚠️ 子集 | `geosite:`；无 regex / attributes |
| GEOIP | ⚠️ 子集 | `geoip:cc` / `geoip:!cc`；非 IP 列表文件 |
| FINAL | ⚠️ 近似 | `.any`；推荐置底 |
| IP-CIDR / IP-CIDR6 | ❌ | 未实现 |
| network / port / AND / OR | ❌ | factory 拒绝或引擎未消费 |

### 4.5 Config Compiler Contract

`FieldRoutingRuleFactory` = **narrow compiler**：

- 每个 `type: field` row 最多产出 **一条** primitive `Rule`。
- 接受：单个 domain entry **或** 单个 `geoip:` entry。
- **静默丢弃**（当前行为，已知缺陷）：多个 domain、`domain + ip`、可识别非空 `network`、`regexp:`、非法 / 空 `outboundTag`、非 `field` type。
- `outboundTag`：`direct` → `.direct`；`reject` / `block` → `.reject`；其他非空 → `.proxy(tag)`。
- DNS JSON（`DNSRoutingConfigJSON`）仅解码；不执行 DoH / fallback。

长期目标：`compile(fields:) →` 带 `accepted` / `rejected(reason)` 的 diagnostics，禁止无痕迹丢规则。

---

## 5. 已知约束与风险

### 5.1 MMDB：进程内单活跃库（硬约束）

`GeoMMDBBridge` 使用进程级 `g_db` + `g_refcount`：

- 已有打开实例时，再次 `open(不同路径)` **不会切换**数据库。
- `MMDBReader.reopen()` 可能影响其它逻辑上的 reader。
- 查找路径与 Swift `DispatchQueue` 串行保护叠加，语义难推理。

**当前集成约束**：进程（或 Network Extension）内 **只应存在一个活跃 MMDB 路径**；不要并行打开多个 `MMDBReader` 指向不同文件。真正的热更新应通过 **整份 `RuleEngine` / `GeoIPDB` snapshot 替换** 实现，而不是依赖 `reopen()`。

### 5.2 Compiler 静默丢规则

配置意图与运行时规则集可能不一致，且无 API 反馈。接入方应在 diagnostics 落地前自行校验，或只下发已确认的 primitive 规则。

### 5.3 性能量级（指导用）

| 组件 | 时间 | 备注 |
|------|------|------|
| `RuleEngine.evaluate` | \(O(R \cdot C)\) | \(R\)=规则数 |
| Suffix trie 查询 | \(O(L)\) | \(L\)=标签数；当前有 per-label `String` 分配 |
| Keyword | \(O(K \cdot \|d\|)\) | 规模大时再考虑自动机 |
| GeoIP | MMDB lookup + 串行队列 | 热点更可能在此，而非 trie |

在补齐 CIDR / 组合条件前，**不优先**做规则索引。

---

## 6. 依赖

- **ForgeBase**：`FBIPv4`、`TransportProtocol` 等
- **内嵌 libmaxminddb**：经 `GeoMMDBBridge` 封装

与独立实验包 ForgeMMDB：MVP 以本包内 GeoMMDB 路径为准；二者勿在同进程混用多实例打开。

---

## 7. 测试契约

`ForgeRuleCoreTests`（Swift Testing）覆盖 narrow contract：

- FlowFactsResolver（含 FakeIP / 空白域名）
- Field routing / DNS JSON 解码与 primitive lowering
- Domain matchers、GeoSite temp JSON、GeoIP stub
- `RuleEngine` 顺序、`.any` fallback、域名规范化
- **契约回归**（`ContractRegressionTests`）：见 [CONTRACT-TESTS.md](./CONTRACT-TESTS.md)
- **治理**：见 [TESTING.md](./TESTING.md)；CI 跑 `Scripts/check-test-governance.sh` + `swift test`

**新增语义规则**：先补 fixture 或 table-driven / 契约测试，再改 matcher / compiler。

**已知缺口**：

- 小型真实 `geoip.mmdb` fixture
- compiler rejected reason（待 diagnostics API）
- 并发 classify / snapshot swap
- Bundle 文件缺失细分错误
- MMDB 多路径单例行为的进程级测试
---

## 8. QuantumLink / NetForge 集成

| 阶段 | 工作 | 状态 |
|------|------|------|
| Phase 2 | Extension 链接 ForgeRuleCore SPM | 规划 |
| Phase 2 | App Group 加载 geosite / geoip | Bundle 已有；缺文件诊断 |
| Phase 2 | NetForge `TrafficPolicyProvider` → `evaluate` | 规划 |
| Phase 2 | 热更新：snapshot swap + provider message | 规划；**勿依赖 `reopen()`** |

**当前**：QuantumLink 侧主要是 App Group 文件通道；Xcode target 链接仍以规划为准。

---

## 9. 架构 TODO

优先级与 [技术文案.md](./技术文案.md) 审查结论对齐（F1/F2/F3 = P0）。

### P0 — 正确性与可观测性

- [x] README routing 范围与 narrow compiler 对齐
- [x] 架构文档写死：`geoip:!cc` miss 行为、MMDB 单活跃库、`port`/`proto` reserved、`.any` 推荐置底
- [ ] `FieldRoutingRuleFactory` diagnostics API（禁止静默丢规则无痕迹）
- [ ] MMDB：文档约束落地为 API 保障，或改为 per-instance `MMDB_s*`；收敛 / 隐藏误导性 `reopen()`
- [x] 回归测试：`geoip:!cc` + lookup miss；（若保留全局 bridge）单路径约束说明测试 — miss 契约见 `ContractRegressionTests` / [CONTRACT-TESTS.md](./CONTRACT-TESTS.md)；MMDB 多路径仍待 API 保障

### P1 — MVP 规则语义与 API 边界

- [ ] `IP-CIDR` / `IP-CIDR6` + factory 接线
- [ ] Composite：domain OR；`domain + ip + network + port` AND
- [ ] `network` 从「解析后拒绝」升级为引擎条件
- [ ] 收窄 public surface（matchers / MMDB internals → package 或非 public）
- [ ] 评估是否增加显式 `final` 条件（短路）以贴近 Surge

### P2 — Reload 与集成生命周期

- [ ] `RuleCoreSnapshot` / `RuleCoreProvider`：atomic swap（rules + GeoSite + GeoIP）
- [ ] 线程安全：classify 可并发；reload 不长时间阻塞读路径
- [ ] `ForgeRuleCoreBundle`：文件存在性、版本、错误细分
- [ ] NetForge `PolicyDecision` / QuantumLink provider message 类型映射

### P3 — 兼容性与性能

- [ ] 官方 geosite / routing fixture 兼容套件
- [ ] 评估 geosite `regex` / attributes
- [ ] `DomainSuffixTrie` 减少 label `String` 分配
- [ ] Keyword 规模上来后考虑 Aho-Corasick
- [ ] Benchmark 后再决定是否引入保序 rule index

### Next（当前冲刺）

1. Compiler diagnostics  
2. MMDB 单实例约束产品化（API 或 per-instance）  
3. `geoip:!` miss 契约测试  
4. `IP-CIDR` / `IP-CIDR6`  
5. Composite condition model  
6. Reloadable snapshot provider  

---

## 10. 迭代记录

| 日期 | 变更 |
|------|------|
| 2026-02 | RuleEngine, GeoSiteDB, GeoIPDB 初始 |
| 2026-02 | Domain matchers + libmaxminddb 集成 |
| 2026-02 | FlowRuleClassifier, FieldRoutingConfig |
| 2026-04-30 | 文档化；QuantumLink 接入列入 Phase 2 |
| 2026-06-27 | 明确 narrow compiler 契约与架构 TODO |
| 2026-07-19 | 吸收代码审查：数据流、stable API、Geo/`!cc`/MMDB 硬约束、TODO 重排 |

---

## 11. 链接

- [TESTING.md](./TESTING.md) — 单元测试治理与 CI 策略
- [技术文案.md](./技术文案.md) — 代码审查发现与评级（过程文档）
- [CONTRACT-TESTS.md](./CONTRACT-TESTS.md) — 契约测试与回归计划
- [QuantumLink 技术升级.md](../../../QuantumLink/docs/技术升级.md) — 跨仓 Review 与升级总控
- [README.md](../../README.md) — 包入口
- [QuantumLink Architecture-Evolution](../../QuantumLink/docs/Architecture-Evolution.md)
- [NetForge ARCHITECTURE.md](../../NetForge/docs/ARCHITECTURE.md)
