# CVA6-DFZ-0003：G0/L1 动态身份与粗粒度 PL

| 字段 | 值 |
|---|---|
| Change ID | `CVA6-DFZ-0003` |
| 状态 | Verified |
| 实施日期 | 2026-08-23 |
| 基线 | `6cb200105fb9441d170e45786125a737fab98e91` |
| 当前承载提交 | `90f3cfc1eb07a0902d93123346b325f4541b884f` |
| Target | `cv64a6_imafdc_sv39` |
| 相关决策 | [`ADR-0001`](../../05-decisions/ADR-0001-dynamic-instruction-identity.md) |

## 目标

在不改变 CVA6 功能数据通路的前提下建立：

1. 前端动态指令出生身份；
2. 前端身份到 scoreboard 物理槽的连接；
3. 槽位复用 generation；
4. 后端 response、commit、trap、flush 的同 UID 解析；
5. IF/ID 到 commit 的第一层粗粒度 PL；
6. DPI-C 结构化 TRACE 和在线身份一致性检查。

## 非目标

本阶段没有：

- 修改 CVA6 功能模块的控制或数据输出；
- 把原论文所有细粒度 PL 一次性移植；
- 观测 IF/ID 之前的 ICache/TLB 请求身份；
- 展开 LSU、cache、乘除法器等内部状态；
- 支持 superscalar 或 ZCMP/ZCMT 一对多微操作 lineage；
- 实现 fuzz generator、RL policy 或 coverage feedback。

## 修改文件摘要

| 文件 | 类型 | 作用 |
|---|---|---|
| `core/Flist.cva6` | 修改 | 将监视器加入 RTL 文件表 |
| `core/cva6.sv` | 修改 | 只读 observation cone、flush reason、配置断言、实例化 |
| `core/dfz_trace_monitor.sv` | 新增 | token/generation 状态、PL/Event、DPI emit、final censored |
| `Makefile` | 修改 | 将 DPI-C writer 链入 Verilator harness |
| `corev_apu/tb/dpi/dfz_trace.h` | 新增 | 固定 DPI-C ABI |
| `corev_apu/tb/dpi/dfz_trace.cc` | 新增 | UID/owner monitor、TSV writer、footer |
| `corev_apu/tb/ariane_tb.cpp` | 修改 | plusarg、SV final、TRACE close |
| `deepflowfuzz_test/Makefile` | 修改/新增的一部分 | `make trace`、归档路径和稳定软链接 |
| `deepflowfuzz_test/TRACE.md` | 新增 | 运行侧字段与节点说明 |

完整逐文件说明见 [`source-inventory.md`](source-inventory.md)。

## 编译和运行隔离

RTL observation cone 与监视器全部处于：

```systemverilog
`ifdef DFZ_TRACE
...
`endif
```

普通 `make run` 不传 `+define+DFZ_TRACE`，不会实例化 RTL monitor，也不会生成
TRACE。`make trace` 同时传递：

```text
+define+DFZ_TRACE
+dfz_trace_file=<test>/build/runs/<RUN_ID>/TRACE/<test>.l1.tsv
```

DPI-C translation unit 被常规 Verilator harness 链接，但没有运行参数时不会打开
文件、分配身份或产生日志。

## 身份链

```text
IF/ID accepted instruction
  -> RTL front_token
  -> DPI (core_id, front_token) -> inst_uid
  -> issue allocates (trans_id, generation)
  -> DPI slot owner -> same inst_uid
  -> FU response / commit / trap / flush kill
```

详细状态机见
[`pipeline-and-dynamic-identity.md`](../../01-architecture/pipeline-and-dynamic-identity.md)。

## 粗粒度节点

### ID

- `PL_ID_RESIDENT`：每个 ID 驻留周期都记录；
- `PL_ID_WAIT_SB_FULL`；
- `PL_ID_WAIT_FU`；
- `PL_ID_WAIT_RAW`；
- `PL_ID_WAIT_CVXIF`；
- `PL_ID_WAIT_ACCEL`；
- `PL_ID_WAIT_OTHER`；
- `ACT_ISSUE_TO_FU`。

`PL_ID_RESIDENT.data0` 是并发 stall bitmap，而不是优先级选择，因此具体 wait
witness 可以同拍共存。

### Scoreboard/后端

- `PL_SB_WAIT_RESULT`：`issued && !result_valid`；
- `PL_SB_WAIT_COMMIT`：`issued && result_valid && !exception`；
- `PL_SB_EXCEPTION_WAIT`：`issued && result_valid && exception`；
- `EVT_FU_RESPONSE`；
- `EVT_COMMIT`、`EVT_COMMIT_DROP`、`EVT_TRAP`；
- `EVT_FLUSH_KILL`。

完整信号与条件见
[`g0-l1-signal-node-map.md`](../../03-signal-maps/g0-l1-signal-node-map.md)。

## 终态和观察结束

RTL `final` block 会对停止时仍处于 ID 或 scoreboard 的身份输出
`EVT_CENSORED`。harness 必须先调用 `top->final()`，再调用
`v_dfz_trace_close()`；否则 footer 会先关闭文件，无法记录正向 censored 证据。

reset/flush 采用以下原则：

- reset 或 flush 先终结旧 owner，再清除 trace-only resident；
- 本拍 commit/trap 的 owner 不再重复 flush-kill；
- token 和 generation 在后续 reset episode 中保持单调；
- reset 保持多个时钟只产生一次 episode witness。

## DPI-C 在线检查

writer 检查 token birth、parent、slot owner、generation 连续性、token/slot 一致性和
重复 terminal。非法 issue 只报告错误，不安装坏 owner。状态写入每行
`monitor_status`，footer 汇总：

```text
records identity_errors inst_uids live_slots terminal_uids
```

目前 `identity_errors` 只记录，不自动改变仿真退出码；验证或未来 CI 必须检查
footer。

## 验证结论

`dfz-validation-v3`：

```text
1 PASSED, 0 FAILED
identity_errors=0
2412 frontend births = 2395 issue + 16 ID kill + 1 censored
2395 issue = 2394 commit + 1 flush kill
```

关闭插桩的 `dfz-default-validation` 同样为 `1 PASSED, 0 FAILED`，且运行目录不
产生 TRACE。完整证据见
[`04-validation/2026-08-23-g0-l1`](../../04-validation/2026-08-23-g0-l1/README.md)。

## 回退边界

由于 0001/0002/0003 位于同一提交，当前不能通过单个 `git revert` 只撤销 0003。
逻辑上的最小回退集合是：

1. 删除 `core/dfz_trace_monitor.sv` 和 DPI-C 两个新文件；
2. 从 `core/Flist.cva6`、根 `Makefile` 移除对应文件；
3. 从 `core/cva6.sv` 移除 `DFZ_TRACE` observation cone；
4. 从 `ariane_tb.cpp` 移除 TRACE ABI/final close；
5. 从测试 Makefile 移除 `make trace` 部分。

实际回退前应单独 review；不要用会覆盖用户工作的破坏性 Git 命令。
