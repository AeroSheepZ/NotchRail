# 0016. 胶囊点击恒为展开/收起切换，模式门禁收敛为唯一定义

> **状态：现行** —— 本 ADR **取代 ADR 0015 决议 4**（该决议要求「紧凑胶囊的点击语义维持『仅展开』」，正文保持原样不改写，仅在其顶部加状态横幅）。
>
> 触发背景：ADR 0015 落地后用户复测反馈「灵动岛多个唤出方式设置还是有问题」——「灵动岛打开方式」三档中，点击这条路只实现了一半。

### 背景

ADR 0015 决议 4 基于一条**错误的技术前提**放弃了兑现文案：

> 「**不得**为兑现文案而把点击改成切换 —— 该手势与图标、设置齿轮的点击同层并发，改成切换会连带劫持这些交互。」

该判断成立的前提是容器手势用了 `simultaneousGesture(TapGesture())`。`simultaneousGesture` 的语义恰恰是**与子视图手势并列同时触发**，因此「点图标」会同时命中图标 `Button` 与容器手势。但这**不是** SwiftUI 手势仲裁的必然结果，而是选错原语的后果：换成普通手势（`.onTapGesture`）后，仲裁规则变为**子视图优先** —— 命中图标时由 `Button` 消费事件，容器手势不触发；只有落在岛内空白处（底座、分隔线旁、空状态区）才归容器。**「点胶囊」的语义恰好就是后者。**

于是 ADR 0015 的三处修补方向在此处反了：那处**实现不足、文案正确**，应当改实现，而不是改文案。

事实核对（v0.0.10 工作区）：

1. **点击只能展开、不能收起。** `IslandRootView.handleTap` 原为 `if !stateMachine.currentState.isExpanded { triggerExpand }` —— 展开态下点击**完全无反应**。而设置面板两档文案分别写着「点击顶部胶囊时展开**或收起**」「点击胶囊立即**切换**展开或收起」，且 `TriggerMode` 档名为「仅鼠标点击 / 悬停或点击」。用户在 `.click` 档下点第二次胶囊想收起，得到的是死区。
2. **外接平直屏同理且更隐蔽。** `MouseMonitor.handleClick` 的热区展开分支同样带 `if !extSM.currentState.isExpanded` 门禁；而该屏折叠态 100% 隐形，用户没有任何可见的「第二次点击」参照物。
3. **「仅鼠标悬停」档点击无反应**是**正确**行为（档名含「仅」），但文案未写明，用户会当作 bug 反馈 —— 属于同一次误判的次生问题。
4. **同一枚举存在多处口径。** `triggerMode` 的比较散落在 5 个文件共 6 处（`IslandStateMachine` 2 处、`IslandRootView` 2 处、`MouseMonitor` 2 处），其中 `MouseMonitor` 的 `prefs.triggerMode != .click` 与 `IslandStateMachine.handleMouseLeave` 内部的同一判断**完全重复**。这正是 ADR 0015 背景第 1 条（"同一枚举、两处相反口径"）的同类隐患，只是尚未显形。

### 决议

1. **紧凑胶囊点击在 `.click` 与 `.hoverAndClick` 两档下恒为「切换展开/收起」。** 点第一次展开、点第二次收起，兑现文案。实现手段是把容器手势由 `simultaneousGesture(TapGesture())` 改为 **`.onTapGesture`**，借 SwiftUI「子视图优先」仲裁让图标与设置齿轮的 `Button` 继续独占自己的点击；**不得**再用 `simultaneousGesture` 承载此语义。
2. **`.hover` 档不响应胶囊点击。** 该档语义是「**仅**鼠标悬停」；若此处也响应点击，`.hover` 与 `.hoverAndClick` 将退化为两个可观察行为完全相同的选项 —— 即 ADR 0015 决议 1 刚刚删除的那类**假选择**。三档必须两两可区分。
3. **模式门禁收敛为唯一定义，调用点只引用谓词。** 三档语义只在 `TriggerMode.respondsToHover` / `TriggerMode.respondsToCapsuleTap` 两个计算属性里定义一次；视图层、状态机、鼠标监听一律引用它们，**不得**再各自书写 `== .click` / `!= .click` 式比较。
4. **点击语义的唯一裁决入口是 `IslandStateMachine.handleCapsuleTap(overflowCount:)`。** 视图层不再自读 `triggerMode`，只负责把手势转成一次调用；模式判断与状态流转全部发生在状态机内，使其可被单元测试直接覆盖（SwiftUI 视图私有方法不可测）。
5. **文案必须写明「该档不响应什么」，而不只写「响应什么」。** `.hover` 档须显式声明点击不会有任何反应；三档共同补充「外接平直屏折叠态完全隐形，故该屏的『点击』对应顶部中央热区而非可见胶囊」。

### 理由与权衡

**为何此处改实现而不是改文案**：ADR 0015 立下的判据是「哪一侧才是真实意图」。文案写「展开或收起」、档名写「仅鼠标点击」、`TriggerMode` 的三值结构本身也在表达「点击是一等唤出方式」——**三处独立表达共同指向真实意图是切换**，实现才是落下的那一侧。与之相对，ADR 0015 第 3 处（无遮挡静默）是实现正确、文案不准，故那次改文案。同一条判据，两次相反的结论。

**为何仅靠「改手势原语」就足够**：`IslandIconCell` 的点击是 `Button`（`SpringIconButtonStyle`），设置齿轮也是 `Button`，右键由 `IslandHostingView.rightMouseDown` + `IslandIconHitZone` 几何锚点独立裁决（不经 SwiftUI 手势）。即**只有容器这一个手势会与图标竞争**，改掉它即可，无需触碰图标侧任何代码。即使仲裁真的失效（容器手势也触发），后果也只是「点图标后岛收起」—— 而派发成功后本就恒定收起（ADR 0015 决议 2），**可观察结果完全相同**，故本决议不引入新的失败模式。

**代价**：

1. 展开态下点击岛内空白会收起。这是「点胶囊 = 切换」的定义本身，对 `.click` / `.hoverAndClick` 两档是预期行为。
2. `.hoverAndClick` 档下会出现一处轻微不连贯：鼠标停留在岛上时点击空白收起后，指针未离开岛区，AppKit 不会重新投递 `mouseEntered`，需移出再移入才会重新悬停展开。可接受 —— 只有「用户主动收起又立刻想让悬停再展开」这一狭窄场景会感知到。
3. `.hover` 档的点击彻底无声。以「档名含『仅』」为正当性来源，并以文案显式声明来消除误判。
4. 三档之间仍两两可区分：`.hover` 与 `.hoverAndClick` 差在点击，`.click` 与 `.hoverAndClick` 差在悬停。

### 影响

- `IslandStateMachine` 新增 `handleCapsuleTap(overflowCount:)` 作为点击语义唯一入口；`handleMouseEnter` / `handleMouseLeave` 的门禁改引 `TriggerMode.respondsToHover`。
- `IslandRootView` 的容器手势由 `simultaneousGesture` 改为 `onTapGesture`，`handleTap` 退化为一次转发（不再自读 `triggerMode`）。
- `MouseMonitor` 删除两处与状态机重复的 `triggerMode != .click` 门禁（行为等价，`handleMouseLeave` 内部已早退），悬停/点击门禁改引两个谓词。
- `TriggerMode` 新增 `respondsToHover` / `respondsToCapsuleTap`，成为三档语义的唯一定义处。
- 设置面板「灵动岛打开方式」三档说明重写，并补充外接平直屏热区口径。
- 单元测试须覆盖：点击档两次点击为展开→收起、「仅悬停」档点击后仍为 compact、三档谓词两两互异。
- 诊断运行器 Test 12 改走生产入口 `handleCapsuleTap` 并补「仅悬停档忽略点击」断言。
- 文档侧：`AGENTS.md` §3.3 记录点击语义与门禁收敛；`docs/DOMAIN_MODEL.md` §6 矩阵登记本文；`CONTEXT.md` 无需新增词条（未引入新领域术语）。
