# <阶段> RTL 信号—节点映射

| 字段 | 值 |
|---|---|
| Change ID | `<CVA6-DFZ-NNNN>` |
| Target | `<target>` |
| Observation module | `<path::module/instance>` |

| Stage | Node/ID | Kind/Lifecycle | RTL expression | Fire/valid 语义 | 身份键 | 记录字段 | 终态 | 证据等级 | 稳定锚点 |
|---|---|---|---|---|---|---|---|---|---|
| `<stage>` | `<node>` | `<kind>` | `<expr>` | `<meaning>` | `<identity>` | `<fields>` | yes/no | DIRECT/DERIVED/INFERRED | `<path::symbol>` |

## 同拍优先级

```text
<old resident -> transition -> terminal -> flush -> new birth>
```

## 并发原因字段

| Bit/field | DIRECT 信号 | 含义 | 是否允许与其他原因同拍 |
|---|---|---|---|
| `<bit>` | `<signal>` | `<meaning>` | yes/no |

## 未覆盖配置

- <configuration>

