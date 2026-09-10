# 已知边界与下一阶段路线

## 当前已经完成

- 容器化 Verilator/Spike/RISC-V 工具环境；
- 每测试子目录的统一构建和联合差分入口；
- IF/ID 动态 token 和 DPI-C UID；
- scoreboard `(slot,generation)` owner；
- ID/scoreboard 粗粒度 PL；
- FU response、commit、trap、drop、flush、reset、censored 事件定义；
- schema v1 TSV 和在线身份检查；
- 一个 RAW 定向测试上的插桩/默认模式回归。

## 必须明确的边界

1. 当前不是原论文全部细粒度 PL 的完整移植。
2. 身份出生点在 IF/ID accept；更早的 fetch、ICache、TLB transaction 尚无 UID。
3. execution 只记录 FU response，没有记录各 FU 内部驻留阶段。
4. LSU、store buffer、AMO、DCache、miss queue、TLB page walk 尚未展开。
5. 只支持 scalar `cv64a6_imafdc_sv39`；superscalar、ZCMP/ZCMT 尚不支持。
6. timing load-data trigger 的准确 owner 尚未实现，当前配置被断言禁止。
7. monitor 使用深层 scoreboard hierarchy，CVA6 上游重构后可能编译失败。
8. `uid_by_token` 和 terminal history 当前不回收，长时间 fuzz 会线性增长。
9. TRACE 没有 ROI 开关，短测试也记录启动和退出路径。
10. `identity_errors` 尚未自动转换成回归失败。
11. TRACE header 尚未嵌入 commit、ELF hash、target、seed 和工具版本。
12. 当前只有一个 `fist` 提交，阶段无法独立 Git 回退。

## P0：先提高证据可靠性

在扩大插桩前优先完成：

- 让测试脚本解析 footer，`identity_errors != 0` 时失败；
- 为 TRACE header/footer 加 commit、ELF SHA256、target、seed 和 schema hash；
- RUN_ID 加冲突检查，禁止静默覆盖已有归档；
- 增加 ROI start/stop 或最大记录数控制；
- 为长运行设计 token/terminal 历史回收或 episode 分片；
- 增加 reset、trap、drop、scoreboard full 的定向测试；
- 每个逻辑 Change ID 使用独立 Git commit。

## L2：流水线细粒度 PL

### 前端

- fetch request/response 身份；
- ICache hit/miss/refill；
- ITLB hit/miss/page walk；
- branch prediction、redirect、realigner buffer；
- 建立 fetch transaction 到 IF/ID instruction 的 lineage。

### 执行后端

- ALU/branch/CSR 的内部 accept/response；
- multiplier/divider 的 busy/iteration/response；
- LSU address generation、translation、load/store queue；
- store buffer、AMO buffer；
- DCache hit/miss/refill/eviction；
- exception/interrupt 精确 owner。

每个新 PL 必须先回答：它是 DIRECT 驻留事实，还是由若干信号推断的原因标签。

## L3 / frontier

在 L2 信号可信后再构建：

- 跨模块 PL 图和动态边；
- L1/L2 三边特征到 L3/frontier 的汇聚；
- Nanhu/CVA6 统一 schema；
- coverage、异常行为和差分结果的联合 reward；
- RL 训练策略、episode 切分和可重复 seed；
- 顺序核 bug 注入/已知 bug benchmark。

## 推荐定向测试矩阵

| 目标节点/机制 | 建议测试 |
|---|---|
| scoreboard full | 多条长延迟且相互独立的运算填满槽位 |
| exception wait / trap | illegal instruction、misaligned/access fault |
| commit drop / branch flush | 可控错误预测或分支后错误路径 |
| reset episode | 仿真中途二次 reset，检查 token/generation 单调 |
| slot reuse | 长循环并统计每槽 generation 严格递增 |
| LSU RAW | load-use、store-load forwarding、cache miss |
| divider PL | 连续 divide 和依赖消费者 |
| compressed lineage | RVC 与非 RVC 混合，核对 raw/expanded |

完成某个节点的 RTL 代码不等于验证完成；只有定向测试实际触发并通过身份守恒后，
才能把对应状态从 Implemented 更新为 Verified。

