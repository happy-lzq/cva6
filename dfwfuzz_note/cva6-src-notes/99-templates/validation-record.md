# YYYY-MM-DD <阶段/测试> 验证

| 字段 | 值 |
|---|---|
| Change ID | `<CVA6-DFZ-NNNN>` |
| Commit | `<full SHA>` |
| Dirty tree | yes/no；若 yes，附 `git diff --stat` |
| Target | `<target>` |
| Test | `<path/name>` |
| Seed | `<seed>` |
| RUN_ID | `<immutable run id>` |
| 工具版本 | `<Verilator/Spike/GCC>` |

## 命令

```bash
<exact commands>
```

## 功能结果

```text
<PASS/FAIL and comparator summary>
```

## TRACE/产物

| 产物 | 路径 | 大小/行数 | SHA256 |
|---|---|---|---|
| ELF | `<path>` | `<size>` | `<hash>` |
| TRACE | `<path>` | `<size/records>` | `<hash>` |

## 身份与节点统计

```text
<footer, node counts, closure equations>
```

## 实际覆盖

- 已触发：<nodes/scenarios>
- 未触发：<nodes/scenarios>

## 警告与结论边界

<warning、已证明内容、不能由本次结果推出的内容。>

