# 仓库基线与差异边界

## 可复核基线

| 项目 | 值 |
|---|---|
| 仓库 | `/home/lzq/cva6/cva6-deepflowfuzz` |
| 基线 tag | `cva6-baseline-6cb2001` |
| 基线 commit | `6cb200105fb9441d170e45786125a737fab98e91` |
| 基线提交主题 | `Fix Zcmt JVT index calculation (#3451)` |
| 开发分支 | `cva6-deepflowfuzz` |
| 当前实现 commit | `90f3cfc1eb07a0902d93123346b325f4541b884f` |
| 当前提交主题 | `fist` |
| 当前远端 | `origin/cva6-deepflowfuzz` 指向同一 commit |

`cva6-baseline-6cb2001` 是在 Verilator、Spike、GCC 和 smoke tests 已成功后
建立的本地 annotated tag。它是本项目的“修改前行为基线”，不是声明 CVA6
官方发布了同名 release。

## 当前差异规模

从基线到 `90f3cfc1e`：

- 15 个 tracked 文件发生变化；
- 新增 10 个文件；
- 修改 5 个已有文件；
- `1684 insertions(+), 5 deletions(-)`；
- 容器、测试框架、G0/L1 插桩都被压在同一个提交中。

因此，`CVA6-DFZ-0001/0002/0003` 是为了审计而建立的逻辑拆分。不能仅凭
Git 历史断言这些阶段分别由哪个独立提交引入。

## 推荐复核命令

```bash
cd /home/lzq/cva6/cva6-deepflowfuzz

git status --short --branch
git log --oneline --decorate --graph -5
git diff --stat cva6-baseline-6cb2001..HEAD
git diff --name-status cva6-baseline-6cb2001..HEAD
git diff cva6-baseline-6cb2001..HEAD -- <path>
```

查看某一稳定符号附近的修改，优先使用：

```bash
rg -n 'i_dfz_trace_monitor|v_dfz_trace_emit|ACT_ISSUE_TO_FU' \
  core corev_apu/tb
```

## 当前工作树说明

2026-08-24 盘点时，tracked 工作树是干净的，只有 `dfwfuzz_note/` 尚未跟踪。
本笔记本身不属于 `90f3cfc1e`，需要后续单独 review 和提交。

`dfwfuzz_note/ca.txt` 是用户创建的空文件。本次不移动、不删除它；后续正式
记录应写入 `cva6-src-notes/` 的子目录。

## 已知源码卫生项

对基线到当前提交执行 `git diff --check` 会报告：

```text
container/Dockerfile:47: trailing whitespace
```

这不影响容器功能，但应在后续独立的小提交中清理，避免把文档整理和源码
行为修改混在一起。

