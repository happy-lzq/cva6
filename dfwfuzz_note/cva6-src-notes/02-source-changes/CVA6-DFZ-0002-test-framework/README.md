# CVA6-DFZ-0002：DeepFlowFuzz 单测试框架

| 字段 | 值 |
|---|---|
| Change ID | `CVA6-DFZ-0002` |
| 状态 | Verified |
| 实施日期 | 2026-08-22 |
| 基线 | `6cb200105fb9441d170e45786125a737fab98e91` |
| 当前承载提交 | `90f3cfc1eb07a0902d93123346b325f4541b884f` |
| 目标 | 每个测试子目录用相同短命令构建 ELF/BIN/dump 并运行 Spike/RTL |

## 修改前缺失

官方 `cva6.py` 命令需要传入 target、ISS YAML、linker、GCC options、ISS options
等大量参数。它还把 directed C test 编译和 ISS 运行耦合在一个长命令中，不便于
DeepFlowFuzz 后续反复检查 ELF、反汇编和 TRACE。

## 目录契约

```text
verif/tests/custom/deepflowfuzz_test/
├── Makefile                 # 所有子测试共享的实现
└── <test-directory>/
    ├── makefile             # 只选当前目录源文件并 include ../Makefile
    ├── <test>.c             # 当前目录必须恰好一个 C 源文件
    └── build/               # 被 Git 忽略，仅影响当前子测试
```

## 修改文件

### `verif/sim/cva6.py`（修改）

稳定锚点：`run_test()`。

新增 `.elf` 类型识别，并将 `.o`/`.elf` 都视为已经链接完成的输入：

```python
elif test.endswith(".elf"):
  test_type = "elf"

if test_type in ("o", "elf"):
  elf = test_path
```

效果：`--elf_tests <file.elf>` 不再调用 GCC 重编译，Spike 和
`veri-testharness` 直接加载同一个 ELF。

### `verif/tests/custom/deepflowfuzz_test/Makefile`（新增）

公共目标：

| 命令 | 行为 |
|---|---|
| `make list` | 检查并显示当前测试、源文件和 build 内容 |
| `make check` | 要求恰好一个 `.c`，检查 linker、crt、syscalls 和工具 |
| `make build` | 生成 `<test>.elf`、`<test>.bin`、`<test>.dump` |
| `make run` | 同一 ELF 运行 Spike 与 Verilator 并比较 |
| `make spike` | 只运行 Spike |
| `make rtl` | 只运行 Verilator |
| `make trace` | 在 `make run` 基础上启用 G0/L1 TRACE |
| `make clean` | 只删除当前测试子目录的 `build/` |

根据用户决定，build 不生成独立 `.o`、`.map`、`.readelf`、`.symbols`。dump 使用：

```text
objdump -d --disassemble=main -M no-aliases,numeric
```

它只显示 `main` 的机器指令，不混入 C 源码行。GCC 仍保留 `-g`，用于未来 GDB
或地址分析；`-g` 本身不要求 objdump 显示源码。

每次运行归档到：

```text
<test>/build/runs/<RUN_ID>/
```

`build/latest` 指向最近一次任意运行；带 trace 的运行还维护独立的
`build/TRACE`，因此后续普通 `make run` 不会让稳定 TRACE 入口丢失。

### 子目录 `makefile`（新增）

它设置 `CVA6_ROOT`、`TEST_DIR`、`SRC` 后执行 `include ../Makefile`。因此在测试
子目录直接使用短命令，不需要从仓库根传递长路径。

### `raw_add_xor.c`（新增）

定向构造两组整数指令：

```text
正样本：add t2,t0,t1 -> xor t3,t2,t1   （真 RAW）
负样本：add t4,t0,t1 -> xor t5,t0,t1   （xor 不读 add 结果）
```

使用 `.option norvc` 固定这段关键汇编为 32 位指令，最终检查值：

```text
42, 51, 42, 8
```

## 标准用法

```bash
cva6
cd /workspace/cva6/verif/tests/custom/deepflowfuzz_test/raw_addr_xor

make list
make build
make run
make trace
make clean
```

## 功能边界

- 每个子目录当前只允许一个 `.c`；多文件测试需要扩展 `SRC/TEST_SOURCES` 规则；
- `RUN_ID` 默认精度为秒，手工复用同名 ID 会覆盖同目录结果；
- ELF 使用现有 linker script，会报告 RWX LOAD segment warning，当前不影响仿真；
- `.elf` 分支附近的 Python 缩进风格不统一，语法有效但应独立整理；
- parent Makefile 同时承载 0002 构建框架和 0003 TRACE 开关，修改时需检查两者。

## 验证

`raw_add_xor` 已在 Spike 与 Verilator 上完成联合差分，详见
[`dfz-validation-v3`](../../04-validation/2026-08-23-g0-l1/README.md)。
