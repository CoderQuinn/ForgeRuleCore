# ForgeRuleCore 契约测试与回归计划

> **目的**：把 `ARCHITECTURE.md` 中的稳定契约落成可执行测试，防止语义漂移。  
> **日期**：2026-07-22  
> **范围**：单元测试 + 契约回归（不含真实 MMDB fixture、不含 App Group Bundle I/O）  
> **实现文件**：`Tests/ForgeRuleCoreTests/ContractRegressionTests.swift`

---

## 1. 背景

现有测试（`ForgeRuleCoreTests.swift` + `RuleEngineAndMatchersTests.swift`）已覆盖：

- FlowFactsResolver / FakeIP
- narrow field factory 的正向路径
- DomainExact / SuffixTrie / Keyword
- GeoIP 正匹配与 `!cc` 在 **有 lookup 结果** 时的否定
- RuleEngine 基本域名 / geosite / any 交互

架构契约中仍缺 **写死语义** 的回归锁：

| 契约 ID | 来源 | 风险若未测 |
|---------|------|------------|
| C-GEOIP-MISS | ARCHITECTURE §4.3 | 上层误以为 `!cn` 要「明确非 CN」 |
| C-GEOIP-RESOLVED | §4.2 #8 | 误用 `originalIP` 做 geo 匹配 |
| C-ANY-ORDER | §4.2 #5 | FINAL 放置错误导致默认动作不对 |
| C-DEFAULT-DIRECT | §4.2 #6 | 空规则集行为变化 |
| C-EVAL-NORMALIZE | §4.2 #2 | 依赖调用方先 normalize |
| C-PORT-PROTO-IGNORED | §4.1 reserved | 误以为已支持端口/协议分流 |
| C-COMPILER-DROP | §4.5 | 静默丢弃行为无回归基线 |
| C-OUTBOUND-MAP | §4.5 | tag 映射漂移 |
| C-GEOSITE-REGEX | §4.3 | 误以为 regex 生效 |
| C-FIRST-WINS | §4.2 #4 | 多规则命中顺序错误 |

---

## 2. 测试分类

### 2.1 单元测试（已有 + 本 PR 补充）

针对单一组件、可注入 stub：

- `GeoIPDB` + `StubCountryLookup`
- `RuleEngine` + 空/临时 GeoSite
- `FieldRoutingRuleFactory`
- Matchers / normalize helpers

### 2.2 契约回归（本 PR 重点）

每个用例对应一条 **不得无文档变更的行为**。失败即视为契约破坏，须先改 ARCHITECTURE 再改测试。

### 2.3 明确不在本 PR

- 真实 `geoip.mmdb` / 官方 geosite 大文件
- `MMDBReader` 多路径全局单例（需进程级隔离，另开）
- `ForgeRuleCoreBundle` App Group（需 mock FileManager）
- Compiler diagnostics API（尚未实现；本 PR 只锁定「静默丢弃」现状）

---

## 3. 用例明细

### C-GEOIP-MISS — `geoip:!cc` 在 lookup miss 时命中

```
给定：CountryLookup 对某 IP 返回 nil
当：GeoIPDB.match(key: "!cn", ip:)
则：true

给定：同上
当：match(key: "cn", ip:)
则：false
```

引擎路径：规则 `[.geoip("!cn") → proxy]`，resolvedIP miss → `.proxy`。

### C-GEOIP-RESOLVED — 只用 resolvedIP

```
给定：originalIP → .us，resolvedIP → .cn
当：规则 .geoip("cn")
则：命中 .direct（或配置的 action）
当：规则 .geoip("us")
则：不命中（落到默认）
```

### C-ANY-ORDER

| 规则顺序 | 输入 | 期望 |
|----------|------|------|
| `[any→reject, suffix special→proxy]` | `a.special.test` | `.proxy` |
| `[any→reject]` 仅 | `other.com` | `.reject` |
| `[suffix→proxy, any→reject]` | `other.com` | `.reject` |
| `[suffix→proxy, any→reject]` | `a.special.test` | `.proxy`（首个非 any） |

### C-DEFAULT-DIRECT

空规则列表 → `.direct`。

### C-EVAL-NORMALIZE

未先经 Resolver；`domain: "  API.X.COM "` + `.domainFull("api.x.com")` → 命中。

### C-PORT-PROTO-IGNORED

同一域名规则；`port`/`proto` 不同不得改变 action。

### C-COMPILER-DROP（现状基线）

下列 field 行 **不产出** Rule（静默丢弃）：

- 两个 `domain:` entry
- `domain` + `geoip` 同时存在
- `network: "tcp"`
- `regexp:…`
- `type: "other"`
- 空 / 缺失 `outboundTag`

### C-OUTBOUND-MAP

| outboundTag | action |
|-------------|--------|
| `direct` / `Direct` | `.direct` |
| `reject` / `block` | `.reject` |
| `Proxy-A` | `.proxy("Proxy-A")` |

### C-GEOSITE-REGEX

临时 geosite JSON 仅含 `type: regex` → `contains` 为 false。

### C-FIRST-WINS

两条均可命中的 suffix 规则，只返回第一条的 action。

---

## 4. 运行方式

```bash
# Repo root (canonical / CI)
./Scripts/check-test-governance.sh
./Scripts/run-tests.sh

# Package directory
cd ForgeRuleCore
swift test
```

治理策略与 PR checklist 见 [TESTING.md](./TESTING.md)。

验收：全部 `@Test` 通过（含本 PR 新增契约用例），且 governance gate 绿。

---

## 5. 维护规则

1. 新增 ARCHITECTURE 契约 → 同步加 `C-*` 用例。  
2. 有意改变契约 → 先改 ARCHITECTURE，再改测试，PR 说明「契约变更」。  
3. 不得为了让测试绿而弱化断言含义。

---

## 6. 与升级路线关系

对应 [QuantumLink 技术升级.md](../../../QuantumLink/docs/技术升级.md) Wave 0 第 5 项，以及本仓 ARCHITECTURE P0：「`geoip:!cc` + lookup miss 契约测试」。
