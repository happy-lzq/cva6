# 环境与目标配置基线

## 容器边界

| 项目 | 当前值 |
|---|---|
| 镜像 | `cva6-deepflowfuzz:base` |
| 基础系统 | Ubuntu 24.04 |
| 容器工作目录 | `/workspace/cva6` |
| 宿主机源码 | `/home/lzq/cva6/cva6-deepflowfuzz` |
| 挂载方式 | 宿主机源码目录以 `rw` bind mount 进入容器 |
| 共享内存 | `--shm-size=16g` |
| 默认并行度 | `NUM_JOBS=32` |
| 容器 hostname | `cva6` |

bind mount 的含义是：源码、`tools/` 和测试生成物实际保存在宿主机仓库目录，
容器只隔离系统包、环境变量和运行进程。它不是把源码复制到镜像内部。

## 已验证工具版本

2026-08-24 从现有镜像和挂载工具目录只读检查：

| 工具 | 版本/路径约定 |
|---|---|
| Python | 3.12.3；venv 为 `tools/venv` |
| Verilator | 5.008，`tools/verilator-v5.008` |
| Spike | 1.1.1-dev，commit `b3149ab0`，`tools/spike` |
| RISC-V GCC | 13.1.0，前缀 `riscv-none-elf-`，`tools/riscv` |
| Binutils | 2.40 |
| Bender | 0.32.1，`tools/bin/bender` |

## RTL/ISS 目标

| 项目 | 值 |
|---|---|
| CVA6 target | `cv64a6_imafdc_sv39` |
| MARCH | `rv64gc_zba_zbb_zbs_zbc_zbkb_zbkx_zkne_zknd_zknh` |
| MABI | `lp64d` |
| RTL simulator | `veri-testharness` / Verilator |
| 参考模型 | Spike |

G0/L1 插桩当前显式要求：

- `NrIssuePorts == 1`；
- `SuperscalarEn == 0`；
- `RVZCMP == 0`、`RVZCMT == 0`；
- `SdtrigMcontrol6LoadData == 0`。

这些条件由 `core/cva6.sv` 中 `DFZ_TRACE` 观察区的 initial assertions 检查。
不满足时应直接停止，而不是产生看似正常但身份错误的 TRACE。

## 进入环境

宿主机若已把入口脚本或函数加入 `PATH`/`.bashrc`：

```bash
cva6
```

容器内提示符应类似：

```text
lzq@cva6:/workspace/cva6$
```

宿主机 `.bashrc` 不在 CVA6 Git 仓库中，因此“宿主机命令是否存在”属于机器
配置，不能只通过仓库提交保证。仓库内可追踪的入口实现见
`container/cva6` 和 `container/cva6-env.sh`。

