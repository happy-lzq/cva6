# CVA6 DeepFlowFuzz 源码修改笔记

> 权威目录：`dfwfuzz_note/cva6-src-notes/`
> 最后更新：2026-08-24
> 记录对象：`cva6-deepflowfuzz` 分支中的环境、测试框架、RTL/DPI-C 插桩与验证

本目录回答三个问题：修改了什么、为什么这样修改、怎样证明修改没有破坏
CVA6。以后与 CVA6 源码修改有关的设计说明、信号表、验证记录和决策记录，
统一放到本目录的对应子目录中，不再继续扩充单一的大型日志文件。

## 当前基线

| 项目 | 值 |
|---|---|
| 上游基线 tag | `cva6-baseline-6cb2001` |
| 上游基线 commit | `6cb200105fb9441d170e45786125a737fab98e91` |
| 开发分支 | `cva6-deepflowfuzz` |
| 当前实现 commit | `90f3cfc1eb07a0902d93123346b325f4541b884f` |
| 当前提交说明 | `fist`，说明过于笼统，详细内容以本目录为准 |
| 仿真 target | `cv64a6_imafdc_sv39` |
| 插桩编译开关 | `DFZ_TRACE` |
| TRACE 运行参数 | `+dfz_trace_file=<path>` |

基线到当前实现共有 15 个 tracked 文件变化：新增 10 个、修改 5 个，
合计 `+1684/-5`。这些变化被合并在同一个 Git 提交中，因此下面使用逻辑
Change ID 重新拆分，而不是声称 Git 能区分每一步的提交边界。

## 证据规则

- `DIRECT`：RTL/DPI 在条件成立的时钟直接观察到的事实。
- `DERIVED`：只由 DIRECT 记录进行 UID 连接、计数或守恒检查得到的事实。
- `INFERRED`：依赖微架构解释的推断，不能冒充已由 RTL 直接证明的事实。
- PC 只是指令属性；动态身份由 `front_token -> inst_uid` 以及后端
  `(trans_id, generation)` 共同确定。
- 行号只作阅读辅助。稳定定位采用“仓库相对路径 + module/function + 唯一符号”。
- 不向本目录复制 ELF、BIN、dump、大型 TSV、`work-ver` 等生成物；验证笔记只
  保存命令、摘要、不可变路径和 SHA256。

## 目录导航

| 目录 | 内容 |
|---|---|
| [`00-baseline/`](00-baseline/repository-baseline.md) | 仓库基线、目标配置、工具版本与复核命令 |
| [`01-architecture/`](01-architecture/pipeline-and-dynamic-identity.md) | CVA6 粗粒度流水线和动态身份模型 |
| [`02-source-changes/`](02-source-changes/README.md) | 按 Change ID 拆分的逐文件源码修改记录 |
| [`03-signal-maps/`](03-signal-maps/g0-l1-signal-node-map.md) | RTL 信号、握手条件、PL/Event 和身份键映射 |
| [`04-validation/`](04-validation/README.md) | 每一次可复核的构建、仿真、TRACE 验证记录 |
| [`05-decisions/`](05-decisions/ADR-0001-dynamic-instruction-identity.md) | 关键设计选择及其替代方案（ADR） |
| [`06-roadmap/`](06-roadmap/known-limitations-and-next-stage.md) | 已知边界、风险和下一阶段插桩路线 |
| [`99-templates/`](99-templates/README.md) | 新增修改记录和验证记录时使用的模板 |

## 变更登记

| ID | 日期 | 状态 | 范围 | 摘要 | 详细记录 | 验证 |
|---|---|---|---|---|---|---|
| `CVA6-DFZ-0001` | 2026-08-22 | Verified | 容器与环境 | Ubuntu 24.04 隔离环境、固定工具路径、彩色终端和入口 | [`README`](02-source-changes/CVA6-DFZ-0001-container/README.md) | 环境版本检查、smoke tests |
| `CVA6-DFZ-0002` | 2026-08-22 | Verified | 单测试框架 | 子目录内 `make build/run/trace/clean`，直接运行预编译 ELF | [`README`](02-source-changes/CVA6-DFZ-0002-test-framework/README.md) | `raw_add_xor` Spike/RTL 差分 |
| `CVA6-DFZ-0003` | 2026-08-23 | Verified | G0/L1 身份与 PL | IF/ID token、scoreboard generation、DPI-C UID、粗粒度 PL/终态 | [`README`](02-source-changes/CVA6-DFZ-0003-g0-l1-identity-pl/README.md) | [`dfz-validation-v3`](04-validation/2026-08-23-g0-l1/README.md) |

## 源码文件总索引

| 仓库相对路径 | 类型 | 稳定锚点/职责 | Guard | Change ID |
|---|---|---|---|---|
| `container/Dockerfile` | 新增 | 容器基础包、用户映射、默认环境 | 无 | 0001 |
| `container/cva6` | 新增 | 宿主机 Docker 入口脚本 | 无 | 0001 |
| `container/cva6-env.sh` | 新增 | 工具路径、venv、提示符 | 交互 shell 检查 | 0001 |
| `verif/sim/cva6.py` | 修改 | `run_test()` 支持 `.elf` | 无 | 0002 |
| `verif/tests/custom/deepflowfuzz_test/Makefile` | 新增 | 单测试统一构建/仿真/TRACE | `DFZ_TRACE` 变量 | 0002/0003 |
| `verif/tests/custom/deepflowfuzz_test/raw_addr_xor/makefile` | 新增 | 子目录引入父 Makefile | 无 | 0002 |
| `verif/tests/custom/deepflowfuzz_test/raw_addr_xor/raw_add_xor.c` | 新增 | RAW 正/负样本定向程序 | `.option norvc` | 0002 |
| `core/Flist.cva6` | 修改 | 注册 `dfz_trace_monitor.sv` | 文件内部 guard | 0003 |
| `core/cva6.sv` | 修改 | `i_dfz_trace_monitor` observation cone | `` `ifdef DFZ_TRACE `` | 0003 |
| `core/dfz_trace_monitor.sv` | 新增 | `module dfz_trace_monitor` | `` `ifdef DFZ_TRACE `` | 0003 |
| `Makefile` | 修改 | Verilator `--exe` 加入 `dfz_trace.cc` | C++ 内部空操作 | 0003 |
| `corev_apu/tb/dpi/dfz_trace.h` | 新增 | 固定 DPI-C ABI | 无 | 0003 |
| `corev_apu/tb/dpi/dfz_trace.cc` | 新增 | UID、身份检查和 TSV writer | 无 TRACE 时不打开文件 | 0003 |
| `corev_apu/tb/ariane_tb.cpp` | 修改 | plusarg 白名单、`top->final()`、关闭 TRACE | 无 | 0003 |
| `verif/tests/custom/deepflowfuzz_test/TRACE.md` | 新增 | 运行侧 TRACE 格式说明 | 无 | 0003 |

## 身份与信号索引

| 前级身份 | 转换事件 | 后级身份 | 权威记录 |
|---|---|---|---|
| 无 | `EVT_IF_ID_ACCEPT` | `front_token`、DPI `inst_uid` | [`pipeline-and-dynamic-identity.md`](01-architecture/pipeline-and-dynamic-identity.md) |
| `front_token` | `ACT_ISSUE_TO_FU` | `(slot, generation, inst_uid)` | [`g0-l1-signal-node-map.md`](03-signal-maps/g0-l1-signal-node-map.md) |
| `(slot,generation)` | FU response/commit/trap/flush | 同一 `inst_uid` 的点事件或终态 | [`CVA6-DFZ-0003`](02-source-changes/CVA6-DFZ-0003-g0-l1-identity-pl/README.md) |

## 验证运行索引

| RUN_ID | Commit | Target / Test / Seed | 结果 | TRACE SHA256 | 记录 |
|---|---|---|---|---|---|
| `dfz-validation-v3` | `90f3cfc1e` | `cv64a6_imafdc_sv39` / `raw_add_xor` / 1 | `1 PASSED, 0 FAILED`; `identity_errors=0` | `2b3a1fa0c92f7007c58bf90c7b699407114e2a9c015476ad6237d2ae0dfe880c` | [`README`](04-validation/2026-08-23-g0-l1/README.md) |
| `dfz-default-validation` | `90f3cfc1e` | 同上，不启用 TRACE | `1 PASSED, 0 FAILED` | 不生成 TRACE | [`README`](04-validation/2026-08-23-g0-l1/README.md) |

## 当前边界

当前完成的是标量 CVA6 的 G0/L1 粗粒度路线：IF/ID 接收、ID 驻留、issue、
scoreboard 等待、FU response、commit/trap/flush。ICache/TLB、LSU 内部队列、
各 FU 内部阶段以及 cache 层次的细粒度 PL 尚未实现。完整边界和下一阶段见
[`known-limitations-and-next-stage.md`](06-roadmap/known-limitations-and-next-stage.md)。
