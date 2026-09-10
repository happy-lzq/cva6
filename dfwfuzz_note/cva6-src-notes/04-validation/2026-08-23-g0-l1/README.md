# 2026-08-23 G0/L1 身份与 PL 验证

| 字段 | 值 |
|---|---|
| Change ID | `CVA6-DFZ-0003` |
| Commit | `90f3cfc1eb07a0902d93123346b325f4541b884f` |
| Target | `cv64a6_imafdc_sv39` |
| Test | `raw_addr_xor/raw_add_xor.c` |
| Seed | 1 |
| 插桩 RUN_ID | `dfz-validation-v3` |
| 默认 RUN_ID | `dfz-default-validation` |
| 结果 | 两种模式均 `1 PASSED, 0 FAILED` |

## 执行命令

进入容器后：

```bash
cd /workspace/cva6/verif/tests/custom/deepflowfuzz_test/raw_addr_xor

make trace RUN_ID=dfz-validation-v3
make run RUN_ID=dfz-default-validation
```

带插桩运行实际给 Verilator 传入：

```text
isscomp_opts="+define+DFZ_TRACE"
issrun_opts="+debug_disable=1 +UVM_VERBOSITY=UVM_NONE
             +dfz_trace_file=.../dfz-validation-v3/TRACE/raw_add_xor.l1.tsv"
```

普通运行的 compile opts 为空，run opts 不含 `dfz_trace_file`。

## 差分结果

```text
Spike processed instruction count:      2386
Verilator processed instruction count:  2387
[PASSED]: 1491 matched
1 PASSED, 0 FAILED
```

处理器和参考模型日志中的总 instruction count 可以包含不同的启动/终止观察边界；
本次官方 comparator 的建筑状态比较为 1491 matched，最终结论为 PASS。

普通 `dfz-default-validation` 同样为：

```text
[PASSED]: 1491 matched
1 PASSED, 0 FAILED
```

且其 run 目录没有 `TRACE/`，证明普通模式不会生成插桩日志。

## TRACE 产物

归档路径：

```text
verif/tests/custom/deepflowfuzz_test/raw_addr_xor/
  build/runs/dfz-validation-v3/TRACE/raw_add_xor.l1.tsv
```

稳定入口：

```text
build/TRACE -> runs/dfz-validation-v3/TRACE
```

产物属性：

| 项目 | 值 |
|---|---|
| TSV 文件大小 | 3,832,291 bytes（盘点时） |
| 文件总行数 | 22,705（2 header + 22,702 records + 1 footer） |
| 数据记录 | 22,702 |
| TRACE SHA256 | `2b3a1fa0c92f7007c58bf90c7b699407114e2a9c015476ad6237d2ae0dfe880c` |
| ELF SHA256 | `f72840eb6e2b745aafae26f25cef97080b8ab87df6f7f3c7719d856a78caee04` |

footer：

```text
# records=22702 identity_errors=0 inst_uids=2412 live_slots=0 terminal_uids=2411
```

## 节点计数

```text
EVT_IF_ID_ACCEPT       2412
PL_ID_RESIDENT         4044
PL_ID_WAIT_RAW         1632
PL_ID_WAIT_FU             1
ACT_ISSUE_TO_FU        2395
PL_SB_WAIT_RESULT      4930
EVT_FU_RESPONSE        2394
PL_SB_WAIT_COMMIT      2465
EVT_COMMIT             2394
EVT_ID_KILL              16
EVT_FLUSH_KILL            1
EVT_PIPELINE_FLUSH       17
EVT_CENSORED              1
```

未列出的已定义节点在该 workload 中计数为 0。

## 身份守恒

前端：

```text
2412 IF/ID birth
= 2395 issue + 16 ID kill + 1 censored
delta = 0
```

后端：

```text
2395 issue
= 2394 commit + 1 flush kill
delta = 0
```

`live_slots=0` 说明 observation 结束时没有未释放的 scoreboard owner；唯一
`CENSORED` 是 frontend resident，不是 identity error。

## 其他一致性检查

- `identity_errors=0`；
- 所有已验证数据行的 `monitor_status=OK`；
- RVC 行的 `raw_instr[31:16]` 非零数量为 0；
- DPI-C 文件通过 `g++ -std=c++17 -Wall -Wextra -Werror -fsyntax-only`；
- Verilator 5.008 完整 elaboration、C++ 编译和链接通过；
- 插桩模式与默认模式的差分回归都通过。

## 可复核命令

```bash
trace=build/runs/dfz-validation-v3/TRACE/raw_add_xor.l1.tsv

sha256sum "$trace" build/raw_add_xor.elf
wc -l "$trace"
tail -n 1 "$trace"

awk -F '\t' 'NR>2 && $1 !~ /^#/ {n[$10]++}
  END {for (k in n) print k,n[k]}' "$trace" | sort
```

## 尚未覆盖

本次只有短 ALU RAW 测试，尚未动态触发：scoreboard full、CVXIF、accelerator、
exception wait、trap、commit drop 和后续 episode reset。也没有覆盖 ICache、TLB、
LSU、cache miss、分支预测、CSR、debug 和长时间 slot 复用压力。

因此本记录证明的是“当前 G0/L1 骨架在该定向测试上身份闭合且不破坏差分”，
不证明所有已定义节点或未来 L2/L3 机制已经完成验证。

## 非阻塞警告

链接器报告 ELF 存在 RWX LOAD segment。它来自当前 bare-metal linker layout，
本次 Spike/RTL 都加载同一 ELF 且回归通过；仍应在安全/部署语境下单独处理。

