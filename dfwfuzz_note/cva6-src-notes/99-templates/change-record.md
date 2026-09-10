# CVA6-DFZ-<NNNN>：<变更标题>

| 字段 | 值 |
|---|---|
| Change ID | `CVA6-DFZ-<NNNN>` |
| 状态 | Draft / Implemented / Verified / Superseded |
| 日期 | YYYY-MM-DD |
| Base commit | `<full SHA>` |
| Result commit | `<full SHA 或尚未提交>` |
| Target | `<target>` |
| 相关 ADR | `<link 或 none>` |
| Supersedes | `<Change ID 或 none>` |

## 目标

<这次修改要建立的可验证能力。>

## 非目标

<本次明确不做什么，防止过度声称。>

## 修改前缺失事实

<修改前 RTL/脚本没有提供的 DIRECT 事实或工作流能力。>

## 修改文件

| 路径 | 新增/修改 | module/function/稳定符号 | 修改行为 | Guard |
|---|---|---|---|---|
| `<path>` | `<type>` | `<anchor>` | `<behavior>` | `<guard>` |

## 握手与事件语义

对每个观测点写明：

- 精确 `valid && ready/fire` 条件；
- 采样的是旧状态还是新状态；
- 身份输入与身份输出；
- 记录字段与 flags；
- flush/reset/commit 的同拍优先级；
- 证据等级：DIRECT / DERIVED / INFERRED。

## 不变量与守恒式

```text
<birth = transitions + terminals + censored>
```

## 功能影响

- 是否驱动原 RTL；
- 是否只在 simulation guard 下存在；
- 普通模式如何保持不变；
- 资源、性能、日志容量影响。

## 验证

| RUN_ID | Test/Seed | 实际触发节点 | 结果 | 记录链接 |
|---|---|---|---|---|
| `<id>` | `<test>` | `<nodes>` | `<PASS/FAIL>` | `<link>` |

## 风险与边界

<未验证配置、层次路径风险、schema 兼容性、长期运行风险。>

## 回退与后续

<最小回退文件集合，以及下一 Change ID 应做什么。>

