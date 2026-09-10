# CVA6 顶层总架构梳理

## 1. 总体视角：从顶层到流水线

CVA6 是一个典型的 6 级流水线处理器核，整体主线可以概括为：

```text
boot/reset
   |
   v
PC Generation / Frontend
   |
   v
Fetch + ICache + Instruction Realign
   |
   v
ID Decode
   |
   v
Issue + Scoreboard + Hazard Check
   |
   v
EX Stage (ALU / LSU / BRANCH / MULT / FPU / CSR / CVXIF)
   |
   v
Commit Stage
   |
   v
Architectural state update + CSR / exception / flush
```

它不是简单的一条线性流水线，而是：

- 前端负责“取指和预测”
- 中间负责“发射与依赖控制”
- 后端负责“执行和按序提交”
- 全局控制负责“异常、flush、halt、fence、trap、CSR”

---

## 2. 顶层模块关系

从 `core/cva6.sv` 看，整个核的主干是这样的：

```text
                    +----------------------+
                    |       Frontend       |
                    | PC Gen / BTB / BHT  |
                    | ICache / fetch      |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |        ID Stage      |
                    | Decode / expand RVC  |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |     Issue Stage      |
                    | scoreboard + hazards |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |      EX Stage        |
                    | ALU / LSU / MULT     |
                    | FPU / CSR / BRANCH  |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |    Commit Stage      |
                    | GPR / FPR / CSR     |
                    +----------+-----------+
                               |
                               v
                    +----------------------+
                    |   Controller / CSR   |
                    | flush / trap / halt  |
                    +----------------------+
```

这里最关键的理解是：

- `frontend` 负责“做出下一 PC 和取多少指令”
- `id_stage` 负责“把取回来的指令变成后端能处理的指令记录”
- `issue_stage` 负责“检查能不能发射、谁占用 FU、谁能写回”
- `ex_stage` 负责“真实执行，输出结果和异常”
- `commit_stage` 负责“按序写到架构状态”
- `controller` 和 `csr` 负责“全局协调与异常恢复”

---

## 3. 前端：取指和预测主线

前端逻辑可以用下面的简图理解：

```text
boot_addr_i
    |
    v
PC Generation
    |
    +--> BTB / BHT / RAS 预测
    |
    +--> 选择下一 NPC
    |
    v
Instruction Cache Request
    |
    v
Instr Re-align
    |
    v
Instruction Queue
    |
    v
ID Stage
```

前端关键职责：

- 生成下一个 PC
- 访问 I-cache
- 对齐 fetch 返回的数据
- 处理压缩指令（RVC）
- 在分支预测失败时回滚

关键文件：

- `core/frontend/frontend.sv`
- `core/frontend/instr_realign.sv`
- `core/frontend/instr_queue.sv`
- `core/frontend/btb.sv`
- `core/frontend/bht.sv`
- `core/frontend/ras.sv`

注意：前端并不执行指令，它只负责“把能执行的指令流推进到后端”。

---

## 4. ID：把取指信息变成后端可处理的指令对象

```text
fetch_entry_i
    |
    v
ID Stage
    |
    +--> compressed decode
    +--> control-flow decode
    +--> exception / privilege check
    |
    v
scoreboard_entry_t
    |
    v
issue_entry_o -> Issue Stage
```

ID 阶段关键点：

- 接收前端送来的指令和地址
- 识别是否是压缩指令
- 解码操作码、源寄存器、目的寄存器
- 构造 `scoreboard_entry_t`
- 将合法指令交给 issue 阶段

关键文件：

- `core/id_stage.sv`
- `core/compressed_decoder.sv`
- `core/zcmt_decoder.sv`
- `core/macro_decoder.sv`

这个阶段非常关键，因为它决定了“后端如何理解一条指令”。

---

## 5. ISSUE / SCOREBOARD：发射和依赖控制主线

这是整个处理器最关键的部分之一：

```text
ID 输出的指令
    |
    v
Scoreboard
    |
    +--> 维护 issued / waiting / commit 状态
    +--> 维护 trans_id / issue_pointer / commit_pointer
    |
    v
Issue Read Operands
    |
    +--> RAW / WAW / structural hazards
    +--> operand forwarding
    +--> FU availability check
    |
    v
发射到 EX Stage
```

重要含义：

- 指令不是直接执行，而是先被 scoreboard 跟踪
- 乱序执行由 `scoreboard` 管理
- 真实提交仍保持 in-order
- 依赖检测和数据转发在 `issue_read_operands` 中处理

关键文件：

- `core/issue_stage.sv`
- `core/scoreboard.sv`
- `core/issue_read_operands.sv`

你要理解 CVA6，最重要的不是单独看某个 FU，而是看这两个模块如何把“乱序执行 + 顺序提交”组织起来。

---

## 6. EX：功能单元执行主线

```text
发射指令
    |
    v
Functional Units
    |
    +--> ALU
    +--> BRANCH
    +--> MULT
    +--> LSU
    +--> FPU
    +--> CSR
    +--> CVXIF / accelerator
    |
    v
结果回写 + 异常回写
    |
    v
Scoreboard / Writeback
```

这个阶段做的事情：

- 真正执行算术/访存/分支逻辑
- 产出执行结果
- 产生异常/中断相关信息
- 回传 branch resolve 信息给前端

关键文件：

- `core/ex_stage.sv`
- `core/alu.sv`
- `core/branch_unit.sv`
- `core/load_store_unit.sv`
- `core/mult.sv`

看 EX 阶段时，你应该重点看：

- 指令如何被分发到不同 FU
- 结果从哪个 wb port 返回
- misspredict/exception 是如何反馈

---

## 7. COMMIT：架构状态更新主线

```text
Scoreboard commit candidate
    |
    v
Commit Stage
    |
    +--> 检查异常 / drop / commit_ack
    +--> 更新 GPR / FPR
    +--> 处理 store / CSR / fence / sfence
    +--> 生成最终架构状态变化
```

Commit stage 是“最终正确性裁判点”：

- 只按序提交
- 如果指令有异常，可能不写回
- CSR 指令、store、fence 等需要特别处理
- commit 之后，架构状态才发生改变

关键文件：

- `core/commit_stage.sv`

这一阶段很重要，因为它决定“真正的 CPU 语义”是否成立。

---

## 8. 控制与异常：全局协调主线

```text
Exception / trap / interrupt / debug / fence
    |
    v
CSR Regfile + Controller
    |
    +--> 设置 trap vector
    +--> 设置 EPC / ERet
    +--> flush_if / flush_id / flush_ex
    +--> halt / fence state
    +--> TLB / ICache / DCache flush
    |
    v
Frontend / ID / EX / Commit 同步恢复
```

这是一个非常关键的全局层：

- mispredict 需要前端修正
- exception 需要全部流水线抹掉或处理
- fence / sfence / csr side effects 要同步
- TLB / cache flush 需要协调

关键文件：

- `core/controller.sv`
- `core/csr_regfile.sv`

如果你把前端、ID、Issue、EX、Commit 理解成“数据通路”，那么 controller 和 csr 就是“全局控制器”。

---

## 9. Memory hierarchy：不是外挂，而是核的一部分

```text
LSU / EX --> DCache --> MMU/TLB --> Memory interconnect
                             ^
                             |
                    ICache / fetch path
```

CVA6 把缓存和 MMU 也纳入核内部视角：

- I$ 直接服务前端取指
- D$ 服务 LSU
- TLB / PTW 负责虚实地址转换
- 系统总线连接外部存储器

关键文件：

- `core/cache_subsystem/*`
- `core/cva6_mmu/*`

---

## 10. 一张“最简主线图”

如果你只记住一张最重要的逻辑图，用下面这张就够了：

```text
PC/Fetch
   |
   v
ID Decode
   |
   v
Issue + Scoreboard
   |
   +--> RAW/WAW/hazard check
   +--> operand forwarding
   |
   v
EX FU execution
   |
   +--> load/store / branch / ALU / mult / fpu / csr
   |
   v
Writeback + exception
   |
   v
Commit
   |
   v
Architectural state

同时存在的全局控制：
Exception / interrupt / trap / fence / flush / halt / CSR / TLB
```

---

## 11. 阅读建议：怎么从总图切入源码

建议用这个顺序：

1. 先看顶层 [core/cva6.sv](cva6-deepflowfuzz/core/cva6.sv)
2. 再看前端 [core/frontend/frontend.sv](cva6-deepflowfuzz/core/frontend/frontend.sv)
3. 再看 ID [core/id_stage.sv](cva6-deepflowfuzz/core/id_stage.sv)
4. 再看 ISSUE/SB [core/issue_stage.sv](cva6-deepflowfuzz/core/issue_stage.sv) 和 [core/scoreboard.sv](cva6-deepflowfuzz/core/scoreboard.sv)
5. 再看 EX [core/ex_stage.sv](cva6-deepflowfuzz/core/ex_stage.sv)
6. 再看 COMMIT [core/commit_stage.sv](cva6-deepflowfuzz/core/commit_stage.sv)
7. 最后看 CONTROLLER / CSR / CACHE / MMU

这样能避免“看了很多模块但不知道它们怎么串起来”的问题。

---

## 12. 结论

CVA6 的顶层架构核心可以概括为：

```text
取指与预测 -> 解码 -> issue/hazard -> 执行 -> 回写 -> 提交
                \_______________________全局控制/异常/flush______________________/
```

这是理解它的最好总线。

如果你要继续往下做“前端/后端详细梳理”，下一步就不要再看所有模块，而是严格按这个主线拆成：

- 前端微架构
- ISSUE/SB 微架构
- EXU 微架构
- 提交和 CSR 控制
- Cache/MMU 访存层

这样会很清晰。