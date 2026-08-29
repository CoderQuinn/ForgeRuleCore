# ForgeRuleCore

<p align="center">
  <a href="README.md">English</a> |
  <strong>简体中文</strong>
</p>

[![CI](https://github.com/CoderQuinn/ForgeRuleCore/actions/workflows/ci.yml/badge.svg?branch=feat-0.1.0)](https://github.com/CoderQuinn/ForgeRuleCore/actions/workflows/ci.yml)
![Swift Testing](https://img.shields.io/badge/tests-Swift_Testing-orange?logo=swift)
![Status](https://img.shields.io/badge/status-mvp_kernel-blue)
![Platform](https://img.shields.io/badge/platform-iOS%2015%2B%20%7C%20macOS%2013%2B-blue)
![SPM](https://img.shields.io/badge/SPM-compatible-brightgreen)
![License](https://img.shields.io/github/license/CoderQuinn/ForgeRuleCore)

ForgeRuleCore 是供路由与 DNS 共用的 Swift 规则内核，包含 `RuleCore`、`GeoSiteDB`、`GeoIPDB` 以及流适配器 `FlowRuleClassifier`。

- **Product：** `ForgeRuleCore`
- **Import：** `import ForgeRuleCore`
- **装配入口：** `ForgeRuleCoreBundle.makeRuleCore` / `makeFlowClassifier`
- **Package 路径：** `ForgeRuleCore/`；可在该目录运行 `swift test`，或在仓库根目录运行 `./Scripts/run-tests.sh`

## Xray 风格配置（受限子集）

- **路由：** 解码 `RoutingConfigJSON`，再调用 `FieldRoutingRuleFactory.compile(fields:)`。结果包含保序的已接受规则，以及每个被拒绝 row 的原始下标和稳定 reason；安装规则前必须确认 `isSuccessful`。`makeRule(from:)` 与 `makeRules(from:)` 作为兼容投影保留，但不返回 diagnostics。当前 narrow compiler 每个 `field` 行只接受一个 primitive：单条 `domain`（`geosite:` / `full:` / `domain:` / `keyword:` / 普通后缀）或单条 `ip`（`geoip:` / `geoip:!cn`）。多条 domain、domain+ip 组合、任意非空 `network`、`regexp:` 与 `IP-CIDR` 尚不支持。
- **DNS：** 通过 `DNSRoutingConfigJSON` 解码 `hosts` 与字符串/对象混合的 `servers`。DoH、`expectIPs` 校验和 `skipFallback` 编排属于上层 DNS 服务，不在本 package 内实现。
- **GeoMMDB：** 每个 `MMDBReader` 独立拥有一个不可变 database handle。reload 应创建新的完整规则 snapshot 后替换，不再提供原地 `reopen`。固定版本的 MaxMind 官方测试库覆盖 IPv4 字节序、不同数据库并存、打开失败隔离与 teardown。

## 文档

- [ARCHITECTURE.md](ForgeRuleCore/docs/ARCHITECTURE.md) — 稳定契约
- [TESTING.md](ForgeRuleCore/docs/TESTING.md) — 单元测试治理与 CI 策略
- [CONTRACT-TESTS.md](ForgeRuleCore/docs/CONTRACT-TESTS.md) — 契约/回归测试计划
- [技术文案.md](ForgeRuleCore/docs/技术文案.md) — 代码审查记录

## 本地验证

```bash
./Scripts/ci.sh
./Scripts/check-test-governance.sh
./Scripts/run-tests.sh
./Scripts/coverage.sh
```

`./Scripts/ci.sh` 是本地与 GitHub Actions 共用的唯一完整门禁：执行 49 项测试治理下限、Debug/Release 测试、将严格 Swift 并发诊断视为错误、通用 iOS 15 arm64 构建，以及首方生产代码覆盖率。初始覆盖率 ratchet 为 67.00%；测试与 vendored `libmaxminddb` 不计入，但 package 自身 Swift 源码与 `GeoMMDBBridge.c` 均在范围内。依赖锁定到已审查的 ForgeBase 0.3.0，以获得 Swift 6 `Sendable` packet 契约。

## TODO

- DOMAIN / DOMAIN-SUFFIX / DOMAIN-KEYWORD（primitive 已完成，组合语义待扩展）
- DOMAIN-SET
- IP-CIDR
- GEOIP / GEOSITE（已完成受限子集）
- FINAL（通过 `.any`；详见架构文档）
