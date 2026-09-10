# 验证记录索引

| 日期/阶段 | Commit | RUN_ID | 结果 | 记录 |
|---|---|---|---|---|
| 2026-08-23 G0/L1 | `90f3cfc1e` | `dfz-validation-v3`、`dfz-default-validation` | 两者均 `1 PASSED, 0 FAILED` | [`README`](2026-08-23-g0-l1/README.md) |

每次验证使用独立子目录，目录名采用：

```text
YYYY-MM-DD-<short-stage-name>/
```

验证记录必须包括 commit、target、test、seed、原始命令、PASS/FAIL、身份守恒、
未覆盖节点以及产物路径/哈希。不要复制大型日志或 TRACE 到笔记目录。

