# Issue Tracker

本仓库的**需求规格与任务追踪唯一来源是 GitHub Issues**，而非 `docs/` 目录。

`docs/SPEC.md` 是**已闭环版本的规格归档**（滞后于 issue 关闭时间）；`docs/DEVELOPMENT_PLAN.md` 是**版本演进总表**。二者都不是需求原始来源。做 Spec 轴审查、需求追溯或验收核对时，必须以 GitHub Issues 为准。

- **仓库**：`AeroSheepZ/NotchRail`
- **工具**：`gh` CLI（需已 `gh auth login`）

## 版本 Spec 结构

每个版本由 **1 个 Spec issue + N 个 Ticket issue** 组成，Ticket 通过正文 `## Parent` 段落指向其 Spec。

| 版本 | Spec issue | Ticket issues |
| :--- | :--- | :--- |
| v0.0.9 | #50 | #51 (Ticket 1) / #52 (Ticket 2) / #53 (Ticket 3) / #54 (Ticket 4) |
| v0.0.8 | #39 | #40 – #49 |
| v0.0.5 | #33 | #34 – #38 |
| v0.0.4 | #32 | #26 – #31 |
| Phase 2 | #19 | #20 – #25 |
| 初始版本 | #1 | #2 – #18 |

统一标签为 `ready-for-agent`。

## 查询命令

### 读取单个 issue（含正文与全部评论）

```bash
gh issue view <number> --json number,title,body,state,closedAt,comments
```

### 列出全部已关闭 issue（按关闭时间倒序）

```bash
gh issue list --state closed --limit 60 --json number,title,closedAt,labels
```

### 定位某版本的 Spec 与 Ticket

```bash
# 1. 找 Spec 主 issue（标题以 [Spec] 开头）
gh issue list --state all --search "[Spec] v0.0.9 in:title" --json number,title,state

# 2. 找该版本的 Ticket（标题以 [Ticket N] 开头）
gh issue list --state all --search "[Ticket in:title" --limit 100 --json number,title,state

# 3. 由 Ticket 回读 Spec：查看其 Parent 段落
gh issue view 53 --json body --jq '.body' | sed -n '1,6p'
```

## 审查时的硬性约定

1. **不得仅凭 Acceptance criteria 的 `[x]` 判定已完成**：复选框是人工勾选的声明，必须回到代码验证。
2. **必须核对 issue 关闭留言与最终 HEAD 的一致性**：issue 可能在关闭后仍有后续提交修改或删除其声称的能力。核对顺序为 `closedAt` 与版本范围内提交时间线。
3. **Ticket 的 `## Blocked by` 决定依赖顺序**（例如 #52 依赖 #51，#53 依赖 #51，#54 依赖 #53），审查时按该顺序组织结论。
4. **Spec 的 `## Out of Scope` 同样是契约**：需要同时验证「没有做范围外的事」与「Out of Scope 条目未与已交付能力冲突」。
5. **发现 issue 描述与代码不符时**：以代码为准，并回填 issue 评论澄清，不要静默修正 issue 正文（会破坏历史追溯）。
