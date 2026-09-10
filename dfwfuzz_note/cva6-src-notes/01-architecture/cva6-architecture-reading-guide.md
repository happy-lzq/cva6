# CVA6 架构阅读指南

## 1. 先看结论：CVA6 是什么样的核

CVA6 是一个 6 级流水线、单发射、按序提交、乱序执行（出于功能单元并行/scoreboard 管理）的 RISC-V 64 位应用级处理器核。官方说明与源码都一致：它是一个典型的 in-order issue、out-of-order execution、in-order commit 的设计。要理解它，最关键的不是把每个小模块孤立看，而是先把“取值、解码、分发、执行、提交、控制/异常/flush”这条总线看通。

核心骨架可以从顶层模块看起：

- `core/cva6.sv`：顶层核实例化与信号连接中心
- `core/frontend/frontend.sv`：PC 生成 + I-cache 接口 + 取指/对齐 + 指令队列
- `core/id_stage.sv`：解码与前端/后端交接
- `core/issue_stage.sv`：发射控制 + scoreboard + issue_read_operands
- `core/ex_stage.sv`：各功能单元执行和访存/异常处理
- `core/commit_stage.sv`：按序提交到架构状态
- `core/controller.sv`：flush / halt / fence / exception 控制
- `core/scoreboard.sv`：指令生命周期记录和结果重排
- `core/csr_regfile.sv`：CSR 与异常/中断控制
- `core/cache_subsystem/*`：I$ / D$ / MMU / TLB 相关

这几个模块构成了 CVA6 处理器的主干。

---

## 2. 总体架构：前端与后端分工

### 2.1 前端（Front-end）

前端的职责是：

1. 生成下一个 PC
2. 向指令缓存发起取指请求
3. 对齐 cache 返回的数据
4. 识别分支/跳转预测
5. 将合法指令送到 decode 阶段

核心文件：

- `core/frontend/frontend.sv`
- `core/frontend/instr_realign.sv`
- `core/frontend/instr_queue.sv`
- `core/frontend/btb.sv`
- `core/frontend/bht.sv`
- `core/frontend/ras.sv`
- `core/frontend/instr_scan.sv`

前端并不直接执行指令，它负责提供“下一条要做什么”的入口信息。它会维护：

- PC generation
- BHT/BTB/RAS 预测
- fetch queue
- branch mispredict/flush 反馈
- exception / eret / trap vector / debug PC

CVA6 文档中对前端的描述非常明确：PC Gen 负责生成下一 PC，Fetch 负责访问缓存与对齐，随后指令送到 DECODE；同时，前端用户需要时刻理解“乱序执行后，前端可能被后端 branch mispredict/exception/fence 等事件反向修正”。

### 2.2 后端（Back-end）

后端的职责是：

1. 解码并形成 scoreboard entry
2. 检查 RAW/WAW/结构冒险
3. 按需发射到功能单元（ALU、LSU、BRANCH、MULT、FPU、CSR 等）
4. 收集结果并写回 scoreboard
5. 按序提交到架构状态

核心文件：

- `core/id_stage.sv`
- `core/issue_stage.sv`
- `core/scoreboard.sv`
- `core/ex_stage.sv`
- `core/commit_stage.sv`
- `core/controller.sv`
- `core/csr_regfile.sv`

后端是整个核的控制中枢：

- `id_stage` 负责 decode 和构造指令元数据
- `scoreboard` 负责按 trans_id 跟踪已发射但未提交的指令
- `issue_read_operands` 负责依赖检查和 operand forwarding
- `ex_stage` 负责各个功能单元执行
- `commit_stage` 决定是否真正写回架构寄存器和 CSR

---

## 3. 顶层连接：从 `cva6.sv` 读起

最好的入口不是盲目从底层模块开始，而是先从顶层 `core/cva6.sv` 看模块连接关系。

它的结构非常典型：

```systemverilog
frontend -> id_stage -> issue_stage -> ex_stage -> commit_stage
   ^            |             |             |             |
   |            +-------------+-------------+-------------+
   +------------------------------ controller / csr / caches ------------------------------+
```

在这份 RTL 里，真正的“主路由”是：

- `i_frontend`：取指和预测
- `id_stage_i`：解码、生成 `scoreboard_entry_t`
- `issue_stage_i`：issue/hazard/scoreboard/commit handshake
- `ex_stage_i`：功能单元执行和访存
- `commit_stage_i`：写回架构状态
- `controller_i`：控制 flush/halt/fence
- `csr_regfile_i`：异常/CSR/特权控制与中断

你一旦能看懂这个连接，就能理解 CVA6 的设计意图：

- 前端是预测和取值系统
- 中段是指令生命周期与冒险控制
- 后端是执行和写回提交
- 控制器和 CSR 是全局协调器

---

## 4. 前端详细梳理

### 4.1 PC generation

`frontend.sv` 中最关键的逻辑是：

- `npc_d`, `npc_q`：下一 PC
- `btb_prediction` / `bht_prediction` / `ras_predict`：预测信息
- `resolved_branch_i`：来自执行阶段的 mispredict / resolve
- `set_pc_commit_i` / `pc_commit_i`：跳回 commit PC
- `eret_i`, `epc_i`, `trap_vector_base_i`：异常返回和 trap 入口

这里要抓住一点：

CVA6 前端不是“简单顺序取值”，而是“基于预测和纠正机制的 PC 生成器”。它会在以下条件下改写 NPC：

- reset
- branch prediction
- mispredict correction
- replay due to queue full
- CSR exception/interrupt/eret
- fence/fence.i/sfence.vma 等

### 4.2 instruction re-align

`instr_realign.sv` 负责把缓存返回的对齐块拆成指令流，尤其要处理：

- 压缩指令 RVC
- 非对齐 32-bit 指令跨块
- 需要组合前后两块 cache 数据

这部分逻辑决定了前端如何把 cache 批量返回的数据转成“能被 decode 的有效指令”。

### 4.3 Branch prediction

前端中的 BHT / BTB / RAS 负责：

- 条件分支预测
- 直接/间接跳转预测
- 函数返回栈预测

这里的关键思路：

- 预测是为了提高取指效率
- 真正的正确性由后端 `resolved_branch` 反馈完成修正
- 误预测会触发 `flush_if` / `flush_unissued_instr` 等

### 4.4 指令队列与 decode 交接

`fetch_entry_o` / `fetch_entry_valid_o` / `fetch_entry_ready_i` 是前端和 ID 的握手接口。最重要的是理解：

- 前端送出的是“已对齐/已预测的指令及其地址”
- ID 负责真正 decode，并生成可发射的 `scoreboard_entry_t`

---

## 5. ID 阶段：解码与指令形成

`id_stage.sv` 负责：

- 输入 fetch 结果
- 对压缩指令做扩展和转换
- 处理 `RVC`、`ZCMP`、`ZCMT` 等扩展
- 输出 `issue_entry_o` 给 `issue_stage`

decode 的输出不是原始指令，而是“可进入 scoreboard 的指令对象”：

```systemverilog
scoreboard_entry_t {
  pc,
  trans_id,
  fu,
  op,
  rs1, rs2, rd,
  result,
  valid,
  ex,
  bp,
  is_compressed,
  ...
}
```

也就是说，ID 阶段已经把一条指令“翻译成后端可理解的结构”。

这里要关注：

- `issue_entry_valid_o`
- `issue_instr_ack_i`
- `is_ctrl_flow_o`
- `issue_entry_o_prev`

这些信号体现了ID/ISSUE 之间的流水握手与控制同步。

---

## 6. ISSUE 阶段：发射、冒险、scoreboard

`issue_stage.sv` 是整个 CVA6 的核心中枢。它不只是把指令发给 EX，而是协调三件事：

1. issue instructions
2. reorder/writeback results
3. commit in order

### 6.1 `scoreboard.sv` 的位置

`scoreboard.sv` 是关键。它的职责是：

- 记录已经被 decode 但尚未提交的指令
- 为每条指令分配/管理 `trans_id`
- 收到 `wt_valid_i` / `trans_id_i` 时写回结果
- 决定哪些指令可以 commit
- 处理 branch mispredict / flush / cancellation

这个模块最重要的思想是：

- 程序有序流入，但执行可以乱序
- 结果被写回到特定 `trans_id` 位置
- commit 阶段再按序提交，保证架构状态有序

### 6.2 `issue_read_operands`

CVA6 的 issue 逻辑并不是单纯“是否有空 FU”，还包括：

- RAW: 读后写冲突
- WAW: 写后写冲突
- 结构冒险：ALU / MULT / LSU / CSR / FPU / CVXIF 等 FU 共享和独占情况
- 控制冒险：处理 branch / CSR / LSU 相关 speculatively issued instructions

它会通过 operand forwarding 直接从已完成的结果或 scoreboard 载入源操作数，避免无意义 stall。

### 6.3 需要特别注意的设计

CVA6 这是一个典型的“单发射 + scoreboard + in-order commit”核，因此你在看源码时，要把精力放在这些点：

- `trans_id` 的复用与生成
- `issue_pointer` / `commit_pointer`
- `scoreboard_entry_t.valid`
- `resolved_branch_i.is_mispredict`
- `flush_unissued_instr_i`
- `issue_instr_valid_o` 和 `decoded_instr_ack_o`

这些是理解微架构的关键。

---

## 7. EX 阶段：功能单元执行

`ex_stage.sv` 是“功能单元的总入口”，它实例化多个功能单元：

- ALU / AES / BRANCH
- MULT
- LSU (load/store unit)
- FPU
- CSR
- CVXIF / accelerator / MMU-related units

从接口上看，它接受：

- `rs1_forwarding_i`
- `rs2_forwarding_i`
- `fu_data_i`
- `alu_valid_i`, `branch_valid_i`, `lsu_valid_i`, `mult_valid_i`, `fpu_valid_i`, `csr_valid_i` 等

然后输出：

- `flu_result_o`, `load_result_o`, `store_result_o`, `fpu_result_o`
- `resolved_branch_o`
- `load_exception_o`, `store_exception_o`, `fpu_exception_o`

这里要注意：

- EX 阶段看起来像“执行器”，但它实际也是“结果归档和异常收集中心”
- `resolved_branch_o` 会反馈到 front-end，用于处理 mispredict
- `lsu`、`tlb`、`pmp`、`mmu` 相关逻辑要求你把访存和异常路径一起理解

---

## 8. COMMIT 阶段：架构状态更新

`commit_stage.sv` 负责：

- 按顺序从 scoreboard 取最早指令
- 处理异常、drop、CSR side effects
- 写回 GPR/FPR
- 执行 store / CSR / fence / sfence / trap 等需要按序生效的操作

它最重要的判定逻辑：

- `commit_instr_i[0].valid`
- `commit_instr_i[0].ex.valid`
- `commit_drop_i[0]`
- `halt_i`
- `commit_lsu_ready_i`
- `csr_exception_i.valid`

这意味着 commit 阶段不仅是“写寄存器”，还是“最终的状态一致性裁决点”。

如果一个指令有异常、或者被 flush/cancel，commit 可能不会真的写回架构状态，而只是 drop 或记录异常。

---

## 9. 控制与异常：controller 与 csr

### 9.1 `controller.sv`

`controller` 是 flush / halt / fence / branch mispredict 的控制中心。它会发出：

- `flush_if_o`
- `flush_unissued_instr_o`
- `flush_id_o`
- `flush_ex_o`
- `flush_bp_o`
- `flush_icache_o`
- `flush_dcache_o`
- `flush_tlb_o` / `flush_tlb_vvma_o` / `flush_tlb_gvma_o`
- `halt_o`, `halt_frontend_o`

你可以把它看作“全局状态机”，负责在异常、mispredict、fence、sfence.vma、CSR side-effect 等情况下重置流水线。

### 9.2 `csr_regfile.sv`

CSR 模块控制：

- 特权态与虚拟化状态
- trap / eret / epc / trap_vector_base
- 例外和中断
- memory translation (页表 / TLB)
- perf counters
- debug mode

它和 commit 阶段互相配合：

- commit 阶段决定“哪条指令可以提交”
- CSR 模块决定“提交后是否要更新 CSR 和 trap 状态”

---

## 10. 缓存和 MMU：不是“外部模块”，而是核的一部分

CVA6 的缓存与 MMU 系统不是单独“外围”，它和核的前端/后端直接耦合：

- I$ 接口：`icache_dreq` / `icache_areq`
- D$ 接口：`dcache_req_ports_*`
- MMU/TLB：`enable_translation_i`, `flush_tlb_i`, `satp_ppn_i`, `asid_i` 等

在 `core/cva6.sv` 中，cache subsystem 被直接实例化，说明核设计把 memory hierarchy 视为处理器核心的一部分，而不是简单的 SoC 外设。

---

## 11. 最推荐的阅读顺序

如果你准备自己做一个核，建议按这个顺序读：

### 第一阶段：纵览总线

1. `core/cva6.sv`：先看顶层信号连接
2. `core/frontend/frontend.sv`：理解前端和 PC/预测
3. `core/id_stage.sv`：理解 decode 的输出结构
4. `core/issue_stage.sv`：理解 issue / scoreboard / commit control
5. `core/ex_stage.sv`：理解功能单元接口
6. `core/commit_stage.sv`：理解架构状态写回
7. `core/controller.sv`：理解 flush / halt / fence

### 第二阶段：重点模块深入

8. `core/scoreboard.sv`：最核心的数据结构
9. `core/frontend/instr_realign.sv`：前端取值和对齐
10. `core/csr_regfile.sv`：异常/特权/中断
11. `core/cache_subsystem/*`：访存和 MMU

### 第三阶段：结合文档看

12. `docs/design/design-manual/source/subsystem.adoc`
13. `docs/design/design-manual/source/cva6_frontend.adoc`
14. `docs/design/design-manual/source/cva6_id_stage.adoc`
15. `docs/design/design-manual/source/cva6_issue_stage.adoc`
16. `docs/design/design-manual/source/cva6_execute.adoc`
17. `docs/design/design-manual/source/cva6_commit_stage.adoc`

文档是“语义层”，代码是“实现层”，两者要结合。

---

## 12. 对后续自己做核的启发

如果你后面要参考自己的“一生一芯 B 阶段 5 级流水线核”来构建一个完整可流片核，CVA6 提供的主要启发不只是某一个模块，而是整套工程思路：

1. 先设计核心状态和阶段划分
   - PCGen / IF / ID / ISSUE / EX / COMMIT

2. 先设计统一的 instruction metadata
   - PC, fu, op, rd/rs1/rs2, trans_id, valid/ex/bp

3. 再设计控制与冒险机制
   - scoreboard, issue logic, operand forwarding, flush controller

4. 再落地功能单元与访存层
   - ALU/LSU/FPU/BRANCH/MULT/CSR/TLB

5. 最后设计异常、特权、fence、debug、MMU 等系统能力

也就是说，CVA6 不是“一个超级复杂的单模块”，而是一个典型的“总控 + 数据通路 + 功能单元 + 状态机”的处理器系统设计范例。

---

## 13. 关键结论

- 前端负责“预测和取值”，后端负责“部件执行和架构提交”
- `scoreboard` 是区分 CVA6 是否“理解透彻”的关键模块
- `controller` 决定 pipeline 如何恢复和 flush
- `commit_stage` 保证 architectural state 有序
- `csr_regfile` 和 memory system 是将“处理器核”扩展成“可运行系统”的关键

如果之后你要做自己的核，最重要的不是一口气实现所有 ISA 特性，而是先把下面四个问题想清楚：

- 指令如何进入流水线？
- 如何处理 RAW/WAW/结构冒险？
- 结果如何在 scoreboard 中被重排与提交？
- 什么时候 flush / trap / fence / exception 导致前端和后端同步重置？

这四个问题，基本就是 CVA6 微架构学习的主线。

---

## 14. 相关参考

- 顶层结构：`core/cva6.sv`
- 前端：`core/frontend/frontend.sv`
- ID：`core/id_stage.sv`
- ISSUE：`core/issue_stage.sv`
- SCOREBOARD：`core/scoreboard.sv`
- EX：`core/ex_stage.sv`
- COMMIT：`core/commit_stage.sv`
- CONTROLLER：`core/controller.sv`
- 现有动态身份笔记：`dfwfuzz_note/cva6-src-notes/01-architecture/pipeline-and-dynamic-identity.md`

如果后续要继续做“模块内和模块间微架构详细梳理”，下一步应从 `scoreboard`、`issue_read_operands`、`LSU`、`branch prediction`、`TLB/MMU`、`CSR` 这六个子模块分别展开。
