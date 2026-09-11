# Issue Tracker

本仓库的**需求规格与任务追踪唯一来源是 GitHub Issues**，而非 `docs/` 目录。

`docs/SPEC.md` 是**已闭环版本的规格归档**（滞后于 issue 关闭时间）；`docs/DEVELOPMENT_PLAN.md` 是**版本演进总表**。二者都不是需求原始来源。做 Spec 轴审查、需求追溯或验收核对时，必须以 GitHub Issues 为准。

- **仓库**：`AeroSheepZ/NotchRail`
- **工具**：`gh` CLI（需已 `gh auth login`）

## 版本 Spec 结构

每个版本由 **1 个 Spec issue + N 个 Ticket issue** 组成，Ticket 通过正文 `## Parent` 段落指向其 Spec。

**本文件不维护版本清单，也不硬编码任何 Issue 编号**：版本清单的唯一权威是 `docs/DEVELOPMENT_PLAN.md` §5「演进路线图」；版本与 Issue 编号的对应关系一律**由 `gh` 现查**（见下方「列出全部版本 Spec」与「定位某版本的 Spec 与 Ticket」）。手写映射会随时间漂移，历史上已因此产生过「某版本在清单中缺失」的不一致。

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

### 列出全部版本 Spec（版本 → Issue 映射的唯一取法）

```bash
gh issue list --state all --search "[Spec] in:title" --limit 100 --json number,title,state,closedAt
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
