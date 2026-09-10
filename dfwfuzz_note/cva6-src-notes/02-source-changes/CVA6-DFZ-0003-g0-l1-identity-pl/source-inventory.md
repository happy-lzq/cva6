# CVA6-DFZ-0003 逐文件源码清单

本文只描述 G0/L1 身份与 PL 阶段。容器和单测试框架分别见 0001、0002。

## 1. `core/Flist.cva6`

稳定锚点：`// Top-level source files`。

新增：

```text
${CVA6_REPO_DIR}/core/dfz_trace_monitor.sv
```

目的：让 Verilator/elaboration 能解析 `dfz_trace_monitor`。监视器文件本身有
`DFZ_TRACE` guard，因此普通构建不会产生 module 内容。

## 2. `core/cva6.sv`

稳定锚点：`` `ifdef DFZ_TRACE ``、实例名 `i_dfz_trace_monitor`。

新增约 142 行，只读取已有信号，不驱动任何原有 net/register。内容分为：

1. IF/ID accept 与 issue fire 派生条件；
2. scoreboard 每槽状态 observation；
3. writeback exception/cause observation；
4. commit slot/PC/result observation；
5. flush reason bitmap；
6. `dfz_trace_monitor` 实例；
7. scalar、ZCMP/ZCMT、timing trigger 配置断言。

关键条件：

```systemverilog
dfz_if_accept = fetch_valid_if_id[0] &&
                fetch_ready_id_if[0] &&
                !flush_ctrl_if;

dfz_issue_fire = issue_entry_valid_id_issue[0] &&
                 issue_instr_issue_id[0] &&
                 !flush_unissued_instr_ctrl_id;
```

压缩指令 raw 编码被规范化为 `{16'b0, instruction[15:0]}`，expanded instruction
来自 `id_stage_i.instruction_deco[0]`。

风险：scoreboard 信号使用
`issue_stage_i.i_scoreboard.mem_q[slot]` 深层层次路径。上游重命名实例或改变内部
结构会让 monitor 编译失败；后续应考虑显式 observation interface 或 bind。

## 3. `core/dfz_trace_monitor.sv`

稳定锚点：`module dfz_trace_monitor`。

这是 595 行 simulation-only 主体：

- 定义 DPI ABI、source、node、kind、lifecycle、flags；
- 维护 `cycle_q`、`next_front_token_q` 和 ID resident 属性；
- 为每个 scoreboard slot 维护 token、generation、raw/expanded/RVC；
- 每拍输出 ID PL、scoreboard PL、response、terminal 和 flush；
- 检查“issue 但无 frontend token”的 RTL invariant；
- 在后续 reset 关闭 live identity，并保证每个 reset episode 只记录一次；
- 在 SV `final` 输出 ID/scoreboard `EVT_CENSORED`。

状态更新顺序与事件顺序刻意分开：先用旧状态生成本拍 witness，再以非阻塞赋值
更新 owner。full scoreboard flush 最后清空所有 slot token，和功能 scoreboard 的
flush 优先级保持一致。

## 4. 根 `Makefile`

稳定锚点：`verilate_command` 的 `--exe` 源文件列表。

新增：

```text
corev_apu/tb/dpi/dfz_trace.cc
```

目的：把三个 `extern "C"` DPI 函数链接进 `Variane_testharness`。现有链接参数
已有 pthread；Verilator 使用 `--threads-dpi none`。普通运行虽然包含该 C++ 对象，
但没有 trace path 时不会产生文件或身份状态。

## 5. `corev_apu/tb/dpi/dfz_trace.h`

稳定锚点：

```text
v_dfz_trace_init
v_dfz_trace_emit
v_dfz_trace_close
```

定义 SystemVerilog 与 C++ 共用的固定 ABI。字段宽度显式使用 C/C++ 标准整数
语义，避免随平台变化。

## 6. `corev_apu/tb/dpi/dfz_trace.cc`

稳定锚点：`monitor_identity()`、`write_record()` 和三个 DPI 导出函数。

内部核心表：

```text
uid_by_token[(core,token)]       -> inst_uid
owner_by_slot[(core,slot)]       -> token, inst_uid, generation
last_generation[(core,slot)]     -> last generation
terminal_tokens[(core,token)]    -> already terminal
```

writer 行为：

- 自动创建输出父目录；
- 以覆盖模式打开本次 TRACE；
- 4 MiB stdio buffer；
- 每 4096 条或 terminal 记录刷新；
- 以 mutex 保护全局状态；
- schema v1 TSV 共 25 列；
- 显式 close，并注册 `atexit` 兜底；
- footer 输出记录数与身份一致性统计。

错误不会安装非法 slot owner，但当前也不会自动使仿真返回失败。

## 7. `corev_apu/tb/ariane_tb.cpp`

稳定锚点：`verilog_plusargs[]` 和 `done_processing` 尾部。

三项修改：

1. include `dpi/dfz_trace.h`；
2. plusarg 白名单加入 `dfz_trace_file`，并补齐 `nullptr` 结尾；
3. 仿真结束时依次调用 `top->final()`、`v_dfz_trace_close()`。

顺序不可交换：`top->final()` 会触发 SV final block 写入 censored 记录，文件必须
在它之后关闭。

## 8. `verif/tests/custom/deepflowfuzz_test/Makefile`

稳定锚点：`DFZ_TRACE ?= 0`、`TRACE_FILE`、target `trace:`。

TRACE 部分：

- compile opts 加 `+define+DFZ_TRACE`；
- runtime opts 加 `+dfz_trace_file=...`；
- archive 位于 `build/runs/<RUN_ID>/TRACE/`；
- `build/TRACE` 是最近一次 trace run 的稳定软链接；
- 普通 run 只更新 `build/latest`，不改写稳定 TRACE 链接；
- `trace` target 检查 archive 和 stable 文件都存在。

## 9. `verif/tests/custom/deepflowfuzz_test/TRACE.md`

这是运行侧格式说明，记录：

- identity chain；
- Node/Kind/Lifecycle 定义；
- `PL_ID_RESIDENT.data0` stall bitmap；
- RVC raw/expanded 约定；
- flush reason bits；
- flags 与 `monitor_status` 契约。

源码修改历史以本目录为权威；TRACE 字段的当前运行契约以该文件和 writer header
为准。后续修改 schema 时，必须在同一 Change ID 中同步 RTL constants、C++
node dictionary、运行侧 TRACE.md 和本目录信号表。

## 明确未修改的功能模块

本阶段没有修改：

- `core/scoreboard.sv`；
- `core/id_stage.sv`；
- `core/issue_stage.sv`；
- `core/ex_stage.sv`；
- `core/commit_stage.sv`；
- 任意 cache、TLB、LSU 或 functional unit 功能实现。

因此当前方案是顶层被动观察，不是把 instrumentation 嵌入上述模块的数据通路。

