# G0/L1 RTL 信号—身份—节点映射

> Change ID：`CVA6-DFZ-0003`
> Target：`cv64a6_imafdc_sv39`
> Observation module：`core/cva6.sv::i_dfz_trace_monitor`
> Monitor module：`core/dfz_trace_monitor.sv::dfz_trace_monitor`

## 证据等级

- `DIRECT`：事件/状态成立时直接采样 RTL 信号；
- `DERIVED`：DPI 根据 DIRECT token/slot 连接 UID 或做计数；
- `INFERRED`：对等待原因或微架构含义的解释，不等同于额外 RTL 事实。

## 前端和 ID

| Node | ID | 类型 | RTL 成立条件/输入 | 身份 | 主要字段 | 证据 |
|---|---:|---|---|---|---|---|
| `EVT_IF_ID_ACCEPT` | 1 | Event/Point | `fetch_valid_if_id[0] && fetch_ready_id_if[0] && !flush_ctrl_if` | 新建 `front_token`，DPI 新建 `inst_uid` | PC、raw、expanded、RVC、fetch exception | DIRECT + DERIVED UID |
| `PL_ID_RESIDENT` | 99 | PL/Visit | `issue_entry_valid_id_issue[0] && id_token_q!=0` | 当前 `front_token/inst_uid` | FU、OP、PC、stall bitmap | DIRECT |
| `PL_ID_WAIT_SB_FULL` | 100 | PL/Visit | ID resident 且未 issue，`sb_full` | 当前 frontend identity | 无额外数据 | DIRECT |
| `PL_ID_WAIT_FU` | 101 | PL/Visit | ID resident 且未 issue，`fu_busy[0]` | 当前 frontend identity | FU/OP | DIRECT |
| `PL_ID_WAIT_RAW` | 102 | PL/Visit | ID resident 且未 issue，`stall_raw[0] && !stall_acc_id` | 当前 frontend identity | `data0[2:0]={rs3,rs2,rs1}` | DIRECT |
| `PL_ID_WAIT_CVXIF` | 103 | PL/Visit | FU 为 CVXIF，且 `!(x_issue_valid && x_issue_ready)` | 当前 frontend identity | FU/OP | DIRECT 条件；等待含义为粗粒度解释 |
| `PL_ID_WAIT_ACCEL` | 104 | PL/Visit | ID resident 且未 issue，`stall_acc_id` | 当前 frontend identity | FU/OP | DIRECT |
| `PL_ID_WAIT_OTHER` | 105 | PL/Visit | ID resident、未 issue，且已分类 wait 全部为假 | 当前 frontend identity | FU/OP | DERIVED 分类 |
| `EVT_ID_KILL` | 2 | Event/Terminal | ID resident 且 `flush_ctrl_if || flush_unissued_instr_ctrl_id` | 终结 frontend identity | `data0=flush_reason` | DIRECT |
| `ACT_ISSUE_TO_FU` | 200 | Action/Point | `issue_entry_valid_id_issue[0] && issue_instr_issue_id[0] && !flush_unissued_instr_ctrl_id` | `front_token -> (rvfi_issue_pointer[0], generation)` | slot、generation、FU、OP | DIRECT + DERIVED owner |

`PL_ID_RESIDENT.data0` bitmap：

| Bit | 事实 |
|---:|---|
| 0 | scoreboard full |
| 1 | selected FU busy |
| 2 | RAW stall（accelerator stall 时抑制该归类） |
| 3 | accelerator stall |
| 4 | CVXIF issue handshake wait |
| 5 | rs1 stall |
| 6 | rs2 stall |
| 7 | rs3 stall |

bitmap 是并发事实。具体 wait 节点也允许在同一拍出现多个，不使用“只保留第一个
原因”的优先编码。

## Scoreboard 驻留

每个 slot 的数据直接读取：

```text
issue_stage_i.i_scoreboard.mem_q[slot]
```

| Node | ID | 类型 | RTL 谓词 | 身份 | 证据 |
|---|---:|---|---|---|---|
| `PL_SB_WAIT_RESULT` | 110 | PL/Visit | `issued && !sbe.valid` | `(slot,generation)->inst_uid` | DIRECT |
| `PL_SB_WAIT_COMMIT` | 111 | PL/Visit | `issued && sbe.valid && !sbe.ex.valid` | 同上 | DIRECT |
| `PL_SB_EXCEPTION_WAIT` | 112 | PL/Visit | `issued && sbe.valid && sbe.ex.valid` | 同上 | DIRECT |

每行还携带该 slot 中的 PC、FU 和 OP。这里记录的是 scoreboard 宏状态，不代表
指令正位于某个 FU 的具体内部流水级。

## FU response、提交和终态

| Node | ID | 类型 | RTL 成立条件/输入 | 身份/终态 | data0 / data1 | 证据 |
|---|---:|---|---|---|---|---|
| `EVT_FU_RESPONSE` | 4 | Event/Point | `wt_valid_ex_id[w]` 且 slot 仍 issued/有 owner | slot owner，不终结 | result / cause | DIRECT |
| `EVT_COMMIT` | 5 | Event/Terminal | `commit_ack_commit_id[c] && !commit_drop_id_commit[c]` | 终结 slot owner | committed result / 0 | DIRECT |
| `EVT_COMMIT_DROP` | 9 | Event/Terminal | `commit_ack_commit_id[c] && commit_drop_id_commit[c]` | 终结但非建筑退休 | result / 0 | DIRECT |
| `EVT_TRAP` | 6 | Event/Terminal | `ex_commit.valid`，且该 slot 本拍未 commit | 终结异常 owner | cause / tval | DIRECT |
| `EVT_FLUSH_KILL` | 7 | Event/Terminal | full scoreboard flush，slot live，且本拍未 commit/trap | 终结 slot owner | flush reason / 0 | DIRECT |
| `EVT_CENSORED` | 8 | Event/Censored | SV final 时 ID 或 scoreboard owner 仍 live | 不猜测最终结果 | 0 / 0 | DIRECT at observation end |

FU response 的准确含义是“观察到 FU 响应”。若同拍 full flush，响应仍可作为
point witness 被记录，但 owner 最终由 flush kill 终结；不能把它命名成一定被
scoreboard 接纳的 writeback。

## 控制事件

| Node | ID | 类型 | 条件 | 身份 | 数据 |
|---|---:|---|---|---|---|
| `EVT_PIPELINE_FLUSH` | 10 | Event/Point | IF、unissued 或 scoreboard 任一 flush | 无指令身份 | `data0=reason`；`data1[2:0]={sb,unissued,if}` |
| `EVT_PIPELINE_RESET` | 11 | Event/Point | 后续 reset episode 首次进入 | 无指令身份 | `data0[31]=1` |

flush reason `data0`：

| Bit | 原始信号/原因 |
|---:|---|
| 0 | `resolved_branch.is_mispredict` |
| 1 | `ex_commit.valid` |
| 2 | `eret` |
| 3 | `set_debug_pc` |
| 4 | `flush_csr_ctrl` |
| 5 | `flush_commit` |
| 6 | `fence_i_commit_controller` |
| 7 | `fence_commit_controller` |
| 8 | `sfence_vma_commit_controller` |
| 9 | `hfence_vvma_commit_controller` |
| 10 | `hfence_gvma_commit_controller` |
| 11 | `flush_acc` |
| 31 | reset episode |

## 身份字段有效性

字段只有在 `flags` 相应位为 1 时才权威：

| Flag | 意义 |
|---:|---|
| `0x001` | frontend token |
| `0x002` | slot + generation |
| `0x004` | PC |
| `0x008` | raw instruction |
| `0x010` | expanded instruction |
| `0x020` | FU |
| `0x040` | OP |
| `0x080` | exception |
| `0x100` | drop |
| `0x200` | RVC |

当前 TSV 完整列和运行侧解释以
`verif/tests/custom/deepflowfuzz_test/TRACE.md` 为准。

## 未动态触发的节点

`raw_add_xor` 验证没有触发以下路径：

- `PL_ID_WAIT_SB_FULL`；
- `PL_ID_WAIT_CVXIF`；
- `PL_ID_WAIT_ACCEL`；
- `PL_ID_WAIT_OTHER`；
- `PL_SB_EXCEPTION_WAIT`；
- `EVT_TRAP`；
- `EVT_COMMIT_DROP`；
- `EVT_PIPELINE_RESET`。

因此这些节点当前是“已实现、已通过 elaboration”，不是“已由定向测试覆盖”。
