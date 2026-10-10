# InkOS 学习笔记

更新日期：2026-10-10。

为实现小说知识库与写作工作台，优先学透小说记忆、上下文编译和作者控制的改稿事务，再学习 Agent 执行、恢复机制和写作评测。InkOS 提供了有价值的工程构件；人工编辑与记忆同步的缺口需要在我们的设计中解决。

本项目的产品范围和验收约束由 [SPEC.md](../../SPEC.md) 维护。本文是上游参考和学习安排，不代表本项目已实现这些能力。

## 源码范围

- 上游仓库：[Narcooo/inkos](https://github.com/Narcooo/inkos)。
- 固定快照：[`8fc2ae57080b9821257dee3e37cc677e2b6f389a`](https://github.com/Narcooo/inkos/tree/8fc2ae57080b9821257dee3e37cc677e2b6f389a)。
- 该快照是 master 的 2.0 开发代码；发布版本对照为 [v1.8.0](https://github.com/Narcooo/inkos/releases/tag/v1.8.0)。开发快照的能力不能全部视为发布版本能力。
- 范围：长篇小说的数据、上下文、编辑、写作执行和版本恢复，以及相关 Studio 入口。

## 六项学习重点

| 顺序 | 内容 | 必须掌握的机制 | 学习结果 |
| --- | --- | --- | --- |
| 1 | 小说的数据模型 | 区分作者意图、未来计划、已确认设定、正文事实和外部参考；事实有来源和生效范围，伏笔有生命周期 | 设计出能解释事实来源和变化的作品模型 |
| 2 | 上下文编译 | 围绕当前任务选择人物、状态、伏笔和参考；保护关键约束，压缩历史，记录选择理由和来源 | 构造可核对的写作上下文包 |
| 3 | 作者控制的编辑事务 | 修改绑定原文版本和允许范围；候选、差异、接受、拒绝、撤销与记忆更新相互连接 | 完成作者改稿后正文与记忆一致的闭环 |
| 4 | 可控的 Agent 执行 | 模型提交结构化结果；程序校验并执行；读写权限、作品范围和取消信号由宿主控制 | 将模型判断限制在明确的动作契约内 |
| 5 | 版本与失败恢复 | 正文、状态、索引的写入一致性；保留已完成结果；重试基线与可重建的派生数据 | 中断和恢复后不丢稿、不混用版本 |
| 6 | 写作方法与有证据的审稿 | 大纲、续写、润色、重构采用不同方法；审稿定位原文和原因，保留作者文风与视角 | 建立工程验证和写作质量评测两套依据 |

### 小说的数据模型

小说知识库要表达哪些内容成立。“大纲计划让配角死亡”“AI 草稿写了配角死亡”“作者接受了这段正文”属于不同状态。

InkOS 的状态事实包含 subject、predicate、object、validFromChapter、validUntilChapter 和 sourceChapter。状态变更使用 upsert 与 expire；伏笔可以推进、延期、解决或被替代。Reducer 校验章节顺序、重复摘要和未知伏笔操作。

学习时先画清事实、状态、摘要与正文的关系，再决定存储方式。我们的设计还需要考虑正文版本引用，以及修改历史章节后哪些派生记忆失效；这些不是仅有 sourceChapter 就能解决的问题。

源码入口：

- [models/runtime-state.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/models/runtime-state.ts)：事实、伏笔、章节摘要和状态增量。
- [state/state-reducer.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/state/state-reducer.ts)：确定性的状态应用和校验。
- [harness/contracts.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/contracts.ts)：作品、产物和候选／当前／被替代版本。

### 上下文编译

每次写作都围绕一个明确任务组装上下文。作者意图和关键约束有保护级别，历史资料可以压缩；受保护内容超预算时明确报错。上下文包和 trace 记录来源、选择原因、预算和压缩信息。

InkOS 的检索链并不完全相同：

| 内容 | 该快照的实现 | 学习重点 |
| --- | --- | --- |
| 故事记忆 | SQLite FTS5/BM25 排序，加模型语义选择；未命中关键词的候选也可参与选择；预算充足时可直接装入完整上下文 | 召回、选择与预算是不同步骤；资料增长后要测量调用成本 |
| 绑定到作品的参考资料 | 根据标题、段落标题、用途和备注选择段落，再读取内容 | 参考资料要有用途，不能混作故事事实 |
| 通用素材库 | 网页、文本、PDF 导入；按段落建立词法索引，返回来源及字符位置 | 引用可核对，索引可重建；扫描 PDF 的 OCR 不在该实现内 |

源码入口：

- [agents/composer.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/agents/composer.ts)：章节上下文的收集、选择、预算与 trace。
- [harness/context-compiler.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/context-compiler.ts)：protected／compressible 内容的编译契约。
- [utils/memory-retrieval.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/utils/memory-retrieval.ts)：故事记忆候选与语义选择。
- [references/reference-context.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/references/reference-context.ts)：作品绑定参考资料。
- [materials/retrieve.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/materials/retrieve.ts)与[materials/ingest.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/materials/ingest.ts)：素材搜索与导入。

### 作者控制的编辑事务

作者选段并提出要求后，系统应该基于明确的原文版本生成提案，展示差异，再由作者决定是否接受。拒绝不能改变正文或故事事实；接受和恢复版本都要处理相关记忆。

例如修改第二章，删除“主角得知凶手身份”的情节：相关记忆应该失效，第三章可能需要复查，但后续正文的修改仍由作者决定。

InkOS 的版本、精确选段修改和状态结算可以作为参考构件。人工保存、接受 AI 改稿和恢复旧版本需要走统一的状态更新路径，不能只依赖提示词要求 Agent 自觉同步。

源码入口：

- [harness/artifact-revisions.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/artifact-revisions.ts)：创建、提升和恢复产物版本。
- [interaction/edit-controller.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/interaction/edit-controller.ts)：精确选段和整章编辑。
- [harness/tools/longform-edits.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/tools/longform-edits.ts)：长篇领域的编辑工具。
- [pipeline/runner.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/pipeline/runner.ts)：修订、状态同步及旧章处理。

### 可控的 Agent 执行

将起草、事实结算和审稿拆成明确操作。模型提交结构化参数或结果，程序校验后应用；事实与权限的正确性不能仅靠自然语言承诺。

先理解单次动作的输入、输出、作用范围、确认策略、错误和取消，再增加专业角色。多个角色不要求第一版就实现复杂的自主多 Agent 系统。

源码入口：

- [harness/runtime.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/runtime.ts)：权限、作品锁和动作记录。
- [agent/worker-agent.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/agent/worker-agent.ts)：模型提交结构化结果及宿主验证。
- [agents/writer.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/agents/writer.ts)：正文起草与事实结算分离。

### 版本与失败恢复

把正文、状态和索引的变化作为有边界的写入操作，保留可恢复的版本与执行结果。失败后需要知道哪些工作已完成、哪些输出仍是候选，以及重试应使用哪个原始基线。

源码入口：

- [utils/atomic-file-set.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/utils/atomic-file-set.ts)：多文件事务日志与恢复。
- [harness/source-sync.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/source-sync.ts)：产物发现、快照和接受范围。
- [harness/episode-store.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/episode-store.ts)：执行事件与中断恢复。
- [harness/artifact-reader.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/artifact-reader.ts)：读取指定版本并校验内容。

### 写作方法与有证据的审稿

写作方法应与程序执行机制分开维护。大纲设计、续写、润色和剧情重构需要不同的目标与修改边界；作者的文风、视角和禁忌应成为明确的约束。

审稿结论要对应具体原文与版本。工程测试验证不丢稿、修改范围和状态一致；固定小说样例与人工判断验证人物动机、视角、节奏、文风、信息释放和连续性。

源码入口：

- [长篇写作 Skill](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/skills/inkos-long-writing/SKILL.md)及其 references：场景、人物因果、信息释放与节奏。
- [models/observation.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/models/observation.ts)：审稿观察、来源引用与原文核验。
- [author-edit-scope.flow.test.ts](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/__tests__/author-edit-scope.flow.test.ts)：改稿范围与周围内容保留的测试参考。

## 该快照的限制与设计启示

| 观察 | 证据状态 | 设计启示 |
| --- | --- | --- |
| 内置 Profile 默认允许 Agent 执行部分可恢复修改 | 源码核对，并调用 isActionAuthorized 验证默认策略 | 有恢复版本不等于作者先接受；改稿提案与确认流程需要单独设计 |
| write_truth_file 修改 current_state.md 后，运行时 JSON 不随之更新 | 临时样例复现：Markdown 改成角色在医院，JSON 仍为角色在档案馆；Writer 读取 JSON | 状态投影应只读，或所有编辑都经过结构化状态更新 |
| 人工保存正文会保留旧版本并记录审查标记，但不自动重建运行时状态 | 临时样例复现：正文地点已改，JSON 事实仍旧；下一章编号仍可推进 | 保存、记忆更新与失效处理要组成闭环 |
| 专门的 resync 入口只支持最新章；AI 修订旧章给后续章留下检查提示 | 源码核对 | 历史章节修改需要明确的依赖失效和重建策略 |
| 检查的章节编辑入口以 textarea、手动保存和版本恢复为主 | 章节编辑器源码核对 | 正文内选段操作、差异预览和逐项接受需要另行设计 |

限制依据：[默认 Profile](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/builtin-profiles.ts)、[编辑工具登记](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/core/src/harness/production-capabilities.ts)、[章节编辑器](https://github.com/Narcooo/inkos/blob/8fc2ae57080b9821257dee3e37cc677e2b6f389a/packages/studio/src/pages/ChapterReader.tsx)，以及上文列出的编辑控制器、Writer 和 Pipeline。

## 工程核验范围

在该快照上核验了 16 个相关测试文件，共 55 项测试：Core 45 项、Studio 10 项。Core 的 `tsc --noEmit` 与 `tsc` 均通过。

覆盖素材与参考资料、运行时状态、Reducer、状态投影、文件事务、长篇流程、上下文压缩、章节版本、改稿范围，以及部分 Studio API 与修订重试流程。需要回环地址的测试使用本地模拟模型服务。

核验环境为 Node 26.4.0、pnpm 9.15.9。结果不代表全量测试、真实中文小说质量或发布版本验收；上游测试结果也不代表本项目已有实现。

## 学习顺序与首个练习

先读数据模型和 Reducer，再读 Composer 与检索，接着追踪编辑、版本接受和状态更新，最后补齐执行恢复与审稿。

首个练习按 [SPEC.md 的验证闭环](../../SPEC.md#首个验证闭环) 执行：导入设定、起草两章、改第一章、处理记忆、续写、撤销。使用固定样例验证以下行为：

- 拒绝提案后，正文和已确认事实保持原样。
- 修改选段后，范围外内容保留。
- 修改旧章后，引用旧事实的记忆和后续章节能被标记。
- 续写使用的事实与作者接受的正文版本一致。
- 撤销后，正文与记忆恢复一致。
- 来源版本发生变化时，旧提案不能静默覆盖新稿。
- 中断和重试不重复应用已完成的状态变化。

可以暂缓多体裁、封面、互动影游、CLI/TUI、广泛供应商适配及复杂自主多 Agent。首先把作者的这一个写作闭环做完整。

