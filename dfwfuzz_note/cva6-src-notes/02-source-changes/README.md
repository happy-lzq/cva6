# 源码变更记录索引

每个阶段使用独立目录和稳定 Change ID：

| Change ID | 状态 | 内容 |
|---|---|---|
| [`CVA6-DFZ-0001`](CVA6-DFZ-0001-container/README.md) | Verified | 容器与开发环境 |
| [`CVA6-DFZ-0002`](CVA6-DFZ-0002-test-framework/README.md) | Verified | 单测试构建与仿真框架 |
| [`CVA6-DFZ-0003`](CVA6-DFZ-0003-g0-l1-identity-pl/README.md) | Verified | G0/L1 动态身份、PL 和 DPI-C TRACE |

新阶段从 `CVA6-DFZ-0004` 开始。一个记录目录至少包含 `README.md`；涉及多个
源码文件时增加 `source-inventory.md`，涉及新 schema 时增加 schema migration
说明。模板见 [`../99-templates/change-record.md`](../99-templates/change-record.md)。

状态定义：

- `Draft`：设计或代码尚未完成；
- `Implemented`：代码已实现并能 elaboration，但缺少目标路径的动态验证；
- `Verified`：目标定向测试实际触发，并通过功能和身份不变量；
- `Superseded`：由后续 Change ID 替代，原记录保留审计链。

