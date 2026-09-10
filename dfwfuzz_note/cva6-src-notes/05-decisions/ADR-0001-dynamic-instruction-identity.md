# ADR-0001：动态指令身份不使用 PC 作为主键

| 字段 | 值 |
|---|---|
| 状态 | Accepted |
| 日期 | 2026-08-23 |
| 关联变更 | `CVA6-DFZ-0003` |

## 背景

同一个 PC 可因循环、函数重入、异常返回、分支恢复或重复 workload 多次产生动态
指令实例。CVA6 又使用有限 scoreboard `trans_id`，同一个槽在不同时刻属于不同
指令。因此 PC 或裸 slot 都不足以作为 DeepFlowFuzz 的动态身份。

## 决策

采用三层身份：

```text
RTL frontend: front_token
host global:  inst_uid
RTL backend:  (trans_id, generation) -> front_token/inst_uid
```

- `front_token` 在真实 IF/ID accept 时出生；
- DPI-C 将 `(core_id,front_token)` 映射为 `inst_uid`；
- issue 时建立 `(core_id,slot,generation)` owner；
- 后端事件通过 owner 回到同一 UID；
- PC、raw/expanded instruction、FU 和 OP 都是属性；
- reset/flush/仿真结束必须为 live identity 提供显式终态或 CENSORED。

## 被否决的替代方案

### 只用 PC

实现简单，但无法区分同 PC 的多个动态实例，也无法正确表达循环和恢复。

### 只用 `trans_id`

scoreboard 槽会复用；迟到 response 或跨 flush 事件可能错误连接到新 owner。

### 在 C++ 中根据 PC/时间猜测

这是启发式推断，无法作为 RTL 身份事实，也会把错误隐藏在离线脚本中。

### 直接修改每个功能模块传递全宽 UID

最稳定但侵入面过大，会改动大量 RTL 接口并增加功能/时序风险。G0/L1 先选择
simulation-only observation cone；后续上游结构变化频繁时再评估显式 trace interface。

## 结果

正面影响：

- PC 不再承担错误的唯一身份职责；
- slot reuse 可验证；
- 前后端事件可做严格守恒；
- 可表达 kill、trap、drop 和 censored；
- 不驱动功能 RTL，默认构建关闭。

代价和风险：

- C++ 身份表随累计动态指令数增长；
- 深层 hierarchy observation 对上游重构敏感；
- superscalar 和 macro-op 需要扩展 lineage；
- 当前 identity error 只写日志，需 CI 显式判定失败。

