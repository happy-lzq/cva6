# CVA6 粗粒度流水线与动态指令身份

## 目标

G0/L1 首先解决“同一条动态指令如何跨越流水线被稳定识别”，然后才记录 PL。
它不使用 PC 作为唯一身份，因为循环、重放、异常返回和多次执行都会让相同 PC
对应不同动态实例。

## 当前粗粒度路线

```text
取指/重对齐
    |
    | EVT_IF_ID_ACCEPT
    v
ID resident ---- PL_ID_RESIDENT / ID wait witnesses
    |
    | ACT_ISSUE_TO_FU
    v
scoreboard owner (trans_id, generation)
    |
    +---- PL_SB_WAIT_RESULT
    |
    +---- EVT_FU_RESPONSE
    |
    +---- PL_SB_WAIT_COMMIT / PL_SB_EXCEPTION_WAIT
    |
    +---- EVT_COMMIT / EVT_COMMIT_DROP / EVT_TRAP / EVT_FLUSH_KILL
```

这里的“前端”覆盖 realigned IF/ID 接收和 ID 驻留；“后端”覆盖 issue、
scoreboard、FU response 和 commit/flush 终态。它是完整路径的粗粒度骨架，
不是 ICache、TLB、LSU 或各 FU 内部状态的细粒度模型。

## 三层身份

### 1. `front_token`

当下式为真时，监视器在 RTL 中生成单调递增 token：

```systemverilog
fetch_valid_if_id[0] && fetch_ready_id_if[0] && !flush_ctrl_if
```

token 与当拍的 PC、raw instruction、expanded instruction、RVC 和 fetch exception
绑定。PC 仍被记录，但只是属性。

### 2. `inst_uid`

DPI-C writer 收到 `EVT_IF_ID_ACCEPT` 后，为 `(core_id, front_token)` 分配全局
单调 `inst_uid`。后续每一行先通过 token 或 scoreboard owner 解析回同一 UID。

### 3. `(trans_id, generation)`

CVA6 scoreboard 的 `trans_id` 是有限物理槽，会被反复使用。每次合法 issue 都令
该槽的 trace-only generation 加一：

```text
(core_id, trans_id, generation) -> (front_token, inst_uid)
```

FU response、commit、trap 和 flush kill 必须同时匹配 slot owner 与 generation，
从而避免把槽位复用后的新指令连接到旧指令。

## 生命周期

| 类型 | 含义 |
|---|---|
| `POINT` | 某个边界或响应在该拍发生，不代表驻留 |
| `VISIT` | 指令本拍位于某个 PL，可连续多拍出现 |
| `TERMINAL` | 该 UID 已有确定终态，不能再次终结 |
| `CENSORED` | 仿真停止时仍在途，只证明“观察结束时未完成” |

正常退休、drop、trap、ID kill 和 scoreboard flush kill 都是终态。`CENSORED`
不是失败，也不能被猜测成 commit 或 kill。

## 同拍语义顺序

同一 cycle 内的语义 rank 用来稳定离线排序：

```text
ID residency/wait
  -> issue action
  -> scoreboard PL
  -> FU response
  -> commit/trap
  -> flush/kill/reset
  -> new IF/ID birth
  -> final censored
```

这样可以表达“旧 ID 指令本拍 issue，同时下一条新指令进入 ID”的情况，而不会
把两个 token 互相覆盖。

## flush 与 reset

- frontend/unissued flush 终结尚未进入 scoreboard 的 ID token；
- full-scoreboard flush 终结仍有 owner 且本拍没有 commit/trap 的槽；
- commit/trap 与 flush 同拍时，已确定终态优先，避免重复 terminal；
- 后续 episode reset 会先为所有可见 owner 输出终态，再清空 resident；
- token 与 slot generation 在同一仿真进程内跨 episode 保持单调；
- 连续保持 reset 多拍只记录一次 reset episode。

## DPI 身份不变量

DPI-C writer 检查：

- birth 必须携带非零 token；
- token 不能重复出生；
- issue 必须存在 frontend parent；
- issue 必须带 slot；
- 活跃 slot 不能被复用；
- generation 必须严格加一；
- slot 事件必须命中 owner，并匹配 token/generation；
- 同一 token 不能有两个 terminal；
- 非法 issue 不安装 owner，避免一次错误污染后续记录。

每行的 `monitor_status` 保存检查结果，文件 footer 汇总 `identity_errors`。

## RVC 处理

对于压缩指令：

- `raw_instr = {16'b0, instruction[15:0]}`；
- `expanded_instr` 保存 decoder 使用的 32 位展开指令；
- `FLAG_RVC`/`is_rvc` 明确原始长度。

这防止 realigner 的高 16 位夹带相邻压缩指令而污染属性。

