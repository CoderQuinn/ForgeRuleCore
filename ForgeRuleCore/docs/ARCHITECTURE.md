# ForgeRuleCore 架构与契约

> **角色**：不可变快照式 **routing / geo rule kernel** — `RuleEngine.evaluate` → Direct / Proxy / Reject  
> **QuantumLink 中的位置**：L3 策略 — TCP accept + dial 决策 **之后**  
> **当前兼容级别**：Xray / Surge 风格规则的 **narrow 子集**，不承诺完整兼容  
> **成熟度**：MVP kernel（核心匹配可用）；生产接入仍须由 host 完成 atomic reload / rollback
> **最后更新**：2026-08-30
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
  RuleInput ───────►│ resolve facts → RuleCore.classify   │───► RuleClassification
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
  → App Group/Rules/geosite.json + geoip.mmdb
  → GeoSiteDB + GeoIPDB(preheatKeys) + RuleEngine
```

---

## 3. Target 结构

```
libmaxminddb (C)
  └── GeoMMDBBridge          ← 每个 MMDBReader 独立 opaque handle
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
| Config Compiler | JSON field → `[Rule]` | narrow 可用；拒绝项有显式 diagnostics |
| GeoSite | 按站点建 full/suffix/keyword 索引 | 子集；`regex` / attributes 忽略 |
| GeoMMDB | IPv4 → 国家码 | per-reader 不可变 handle；真实 fixture 覆盖 |

---

## 4. 稳定契约

### 4.1 Public Kernel（稳定面）

面向集成方，视为 **stable**：

| API | 说明 |
|-----|------|
| `Rule` / `RuleCondition` / `RuleAction` | 规则原语 |
| `RuleInput` / `RuleDomainFactSource` | 评估输入与 domain fact 来源 |
| `RuleRevision` / `RuleClassification` | 不透明 snapshot identity 与详细分类结果 |
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
| `domainSource` | ❌ | domain 来自 flow context、DNS 或 FakeIP |
| `domainRevision` | ❌ | 产生 domain fact 的规则 revision；跨阶段原样保留 |
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
9. **`FlowRuleClassifier`**：先 `FlowFactsResolving.resolve`，再 `RuleCore.classify`。旧
   `classify(_:)` 仍返回 `RouteDecision`；`classifyWithFacts(_:)` 同时返回实际评估的
   `RuleInput` 与当前 `RuleRevision`。
10. **事实来源保留**：显式 domain 在 resolve 时保留 `.dns` 等来源和
    `domainRevision`；FakeIP fallback 必须替换来源为 `.fakeIP` 并清除旧 revision，不能把
    空白 DNS fact 的 revision 错绑到新域名。
11. **Revision 不推断**：`RuleRevision` 是 host 提供的不透明、非空 identity；未提供时
    classification 明确返回 `nil`，内核不会用路径、时间或 `latest` 猜测版本。

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
- `compile(fields:)` 返回保序的 accepted `rules` 与每个 rejected row 的 `fieldIndex` + 稳定 `reason`；只要存在 rejected row，`isSuccessful == false`。
- 拒绝：多个 domain、`domain + ip`、任意非空 `network`、`regexp:`、非法 / 空 `outboundTag`、非 `field` type。
- 验证以原始数组计数为准，不得先丢非法 entry 再把剩余 entry 当作有效 row。
- `outboundTag`：`direct` → `.direct`；`reject` / `block` → `.reject`；其他非空 → `.proxy(tag)`。
- DNS JSON（`DNSRoutingConfigJSON`）仅解码；不执行 DoH / fallback。

| Diagnostic reason | 拒绝条件 |
|-------------------|----------|
| `unsupported_rule_type` | `type` 不是 `field` |
| `missing_outbound_tag` | `outboundTag` 缺失或为空 |
| `unsupported_network` | `network` 非空 |
| `mixed_domain_and_ip` | 同一 row 同时包含 domain 与 ip |
| `multiple_domain_entries` / `multiple_ip_entries` | 同类 entry 超过一条 |
| `missing_condition` | domain 与 ip 都没有 entry |
| `invalid_domain_entry` / `invalid_ip_entry` | entry 为空或前缀 payload 为空 |
| `unsupported_domain_entry` / `unsupported_ip_entry` | 非当前 narrow subset 的表达式 |

`makeRule(from:)` / `makeRules(from:)` 仅为兼容旧调用方的 accepted-rules 投影，不携带 diagnostics。新集成必须调用 `compile(fields:)` 并在安装规则前要求 `isSuccessful`。

---

## 5. 已知约束与风险

### 5.1 MMDB：per-reader ownership 与 snapshot reload

`GeoMMDBBridge` 不再持有进程级数据库或 refcount：

- 每次 `forge_mmdb_open` 返回独立 opaque handle；打开失败不会借用其它 reader 的数据库。
- 每个 `MMDBReader` 拥有并在 `deinit` 时只关闭自己的 handle；不同路径可同时存在。
- lookup 在 reader 自己的串行队列执行，teardown 不会使其它 reader 失效。
- Swift/C 两个 target 使用相同的 `MMDB_UINT128_IS_BYTE_ARRAY` 定义，避免 `MMDB_entry_data_s` ABI 布局错读。
- `FBIPv4.beValue` 在 C `sockaddr_in` 边界经 `htonl` 转换，真实 IPv4 fixture 锁定字节序。

`MMDBReader` 不提供原地 `reopen()`。热更新必须先构建新的完整 `RuleEngine` / `GeoIPDB` snapshot，验证成功后由上层原子替换；旧 snapshot 可继续服务在途读取，直至其 reader 自然析构。

### 5.2 Compiler 兼容投影

`compile(fields:)` 会显式报告每个拒绝 row；但兼容 API `makeRule(from:)` / `makeRules(from:)` 仍只返回 accepted rules。接入方若用兼容投影直接安装部分规则，配置意图仍可能被缩窄。生产集成必须使用 compilation 结果并拒绝 `isSuccessful == false` 的配置。

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
- DNS/flow domain fact provenance、rule revision 与 detailed classification envelope
- Field routing / DNS JSON 解码与 primitive lowering
- Domain matchers、GeoSite temp JSON、GeoIP stub
- `RuleEngine` 顺序、`.any` fallback、域名规范化
- **契约回归**（`ContractRegressionTests`）：见 [CONTRACT-TESTS.md](./CONTRACT-TESTS.md)
- **治理**：见 [TESTING.md](./TESTING.md)；CI 跑 `Scripts/check-test-governance.sh` + `swift test`

**新增语义规则**：先补 fixture 或 table-driven / 契约测试，再改 matcher / compiler。

**已知缺口**：

- 大型生产 `geoip.mmdb` fixture 与更多国家/边界样例（小型官方 fixture 已覆盖 reader contract）
- 并发 classify / snapshot swap
- Bundle 版本 manifest、checksum 与 rollback

---

## 8. QuantumLink / NetForge 集成

| 阶段 | 工作 | 状态 |
|------|------|------|
| Phase 2 | Extension 链接 ForgeRuleCore SPM | 规划 |
| Phase 2 | App Group 加载 geosite / geoip | 固定 layout、真实 I/O、错误分类与 host-supplied revision 已覆盖；reload 待 host |
| Phase 2 | NetForge `TrafficPolicyProvider` → `evaluate` | 规划 |
| Phase 2 | 热更新：snapshot swap + provider message | 规划；reader handle 已支持并存 |

**当前**：QuantumLink 侧主要是 App Group 文件通道；Xcode target 链接仍以规划为准。

---

## 9. 架构 TODO

优先级与 [技术文案.md](./技术文案.md) 审查结论对齐（F1/F2/F3 = P0）。

### P0 — 正确性与可观测性

- [x] README routing 范围与 narrow compiler 对齐
- [x] 架构文档写死：`geoip:!cc` miss 行为、MMDB per-reader ownership、`port`/`proto` reserved、`.any` 推荐置底
- [x] `FieldRoutingRuleFactory` diagnostics API（拒绝 row 带稳定 reason 与原始下标；部分结果不报告成功）
- [x] MMDB：per-reader opaque handle；移除误导性 `reopen()`；真实 fixture 锁定 ABI、IPv4 字节序、独立 ownership 与 teardown
- [x] 回归测试：`geoip:!cc` + lookup miss；MMDB 真实 lookup、不同数据库并存、失败隔离与 teardown

### P1 — MVP 规则语义与 API 边界

- [ ] `IP-CIDR` / `IP-CIDR6` + factory 接线
- [ ] Composite：domain OR；`domain + ip + network + port` AND
- [ ] `network` 从「解析后拒绝」升级为引擎条件
- [ ] 收窄 public surface（matchers / MMDB internals → package 或非 public）
- [ ] 评估是否增加显式 `final` 条件（短路）以贴近 Surge

### P2 — Reload 与集成生命周期

- [ ] `RuleCoreSnapshot` / `RuleCoreProvider`：atomic swap（rules + GeoSite + GeoIP）
- [ ] 线程安全：classify 可并发；reload 不长时间阻塞读路径
- [x] `ForgeRuleCoreBundle`：可注入 App Group resolver、文件存在性与稳定错误细分
- [x] `RuleClassification`：保留 snapshot revision 与 DNS/flow domain fact provenance
- [ ] Bundle manifest：版本、checksum、兼容性与 rollback 信息
- [ ] NetForge `PolicyDecision` / QuantumLink provider message 类型映射

### P3 — 兼容性与性能

- [ ] 官方 geosite / routing fixture 兼容套件
- [ ] 评估 geosite `regex` / attributes
- [ ] `DomainSuffixTrie` 减少 label `String` 分配
- [ ] Keyword 规模上来后考虑 Aho-Corasick
- [ ] Benchmark 后再决定是否引入保序 rule index

### Next（当前冲刺）

1. Compiler diagnostics（已完成）
2. MMDB per-instance ownership（已完成）
3. App Group bundle I/O / error contracts（已完成）
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
| 2026-08-29 | compiler diagnostics；GeoMMDB per-reader handle 与真实 fixture contract |
| 2026-08-30 | RuleRevision、domain fact provenance 与详细 classification envelope |

---

## 11. 链接

- [TESTING.md](./TESTING.md) — 单元测试治理与 CI 策略
- [技术文案.md](./技术文案.md) — 代码审查发现与评级（过程文档）
- [CONTRACT-TESTS.md](./CONTRACT-TESTS.md) — 契约测试与回归计划
- [QuantumLink 技术升级.md](../../../QuantumLink/docs/技术升级.md) — 跨仓 Review 与升级总控
- [README.md](../../README.md) — 包入口
- [QuantumLink Architecture-Evolution](../../QuantumLink/docs/Architecture-Evolution.md)
- [NetForge ARCHITECTURE.md](../../NetForge/docs/ARCHITECTURE.md)
