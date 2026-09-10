# CVA6-DFZ-0001：容器与开发环境

| 字段 | 值 |
|---|---|
| Change ID | `CVA6-DFZ-0001` |
| 状态 | Verified |
| 实施日期 | 2026-08-22 |
| 基线 | `6cb200105fb9441d170e45786125a737fab98e91` |
| 当前承载提交 | `90f3cfc1eb07a0902d93123346b325f4541b884f` |
| 目标 | 为 CVA6 构建与宿主机隔离、源码可持久化的 Verilator 开发环境 |

## 修改前缺失

宿主机最初只有 `make` 和 `python3`；Verilator、Spike、RISC-V bare-metal
GCC/objcopy 和 Bender 均不可用。直接把多版本 EDA/编译工具安装到宿主机会使
Nanhu、RTL2MuPATH 和 CVA6 的依赖互相污染。

## 修改文件

### `container/Dockerfile`（新增）

主要行为：

- 使用 Ubuntu 24.04；
- 强制 apt 使用 IPv4，并切换清华 Ubuntu 镜像；
- 安装 autoconf、bison、CMake、device-tree-compiler、flex、`libfl-dev`、
  GMP/MPC/MPFR、Python venv 等构建依赖；
- 通过 build args 创建与宿主机一致的 UID/GID 用户，避免 bind mount 文件变成
  root 所有；
- 将 `/workspace/cva6/tools/bin`、Verilator 和 Spike 加入 PATH；
- 把 `cva6-env.sh` 放入容器用户 home，并由 `.bashrc` 加载。

`libfl-dev` 是解决 Verilator 构建时缺失 `/usr/include/FlexLexer.h` 的必要修正。

### `container/cva6`（新增）

这是宿主机侧入口脚本，不在容器内部完成 Docker-in-Docker。它执行：

```text
docker run --rm -it
  --name cva6
  --hostname cva6
  --shm-size=16g
  -v /home/lzq/cva6/cva6-deepflowfuzz:/workspace/cva6:rw
```

同时传递终端色彩变量和 `NUM_JOBS`，并以 `cva6-env.sh` 作为交互 rcfile。

### `container/cva6-env.sh`（新增）

统一设置：

- `CVA6_ROOT=/workspace/cva6`；
- `RISCV`、`VERILATOR_INSTALL_DIR`、`SPIKE_INSTALL_DIR`；
- Bender/Verilator/Spike PATH；
- `tools/venv`；
- `verif/sim/setup-env.sh`；
- 交互终端彩色 `PS1`。

## 数据与隔离边界

容器使用 `--rm`，退出后容器实例消失；源码、工具链和测试结果位于 bind mount，
不会消失。当前工具链是构建在仓库的 `tools/` 中，而不是烘焙到镜像 layer 中，
所以镜像和该源码目录需要配套使用。

## 验证

已确认：

```text
Python 3.12.3
Verilator 5.008
Spike 1.1.1-dev b3149ab0
riscv-none-elf-gcc 13.1.0
GNU Binutils 2.40
Bender 0.32.1
```

CVA6 官方 smoke tests、后续 `raw_add_xor` Spike/Verilator 差分均已通过。

## 已知风险

- Dockerfile 没有固定 Ubuntu 包的精确版本；
- apt 镜像站是外部依赖；
- `container/cva6` 硬编码宿主路径和用户名 `lzq`；
- 宿主 `.bashrc` 中的 `cva6` 命令不在本仓库版本控制内；
- `tools/` 较大且被 `.gitignore` 排除，单独拿镜像不能重现完整工具；
- `container/Dockerfile` 当前存在一处尾随空白，功能无影响但需后续清理。

