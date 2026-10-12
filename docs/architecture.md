# 本地原型架构

更新日期：2026-10-12。产品范围与行为要求由 [SPEC.md](../SPEC.md) 维护；前文记录当前 0.1.0 运行边界，末节记录已实现的 0.2.0 M1 契约及待接入的服务规则。软件版本与发布规则见 [版本管理](versioning.md)，其版本号独立于下文的数据格式与正文版本。参考本机 `harrypet_flutter/labs/story-pet-agent` 的包分工，未修改该项目或复制其宠物／世界模板业务。

## 包与权威状态

```text
Flutter viewer -> HTTP + 本地会话令牌 -> Genkit novelAction Flow
                                          |
                                     NovelService
                                     /          \
                             DeepSeek 插件     原子 JSON 快照
```

- `packages/novel_contracts`：正文版本、资料身份、提案、派生记忆、请求与工作区契约。纯 Dart，不依赖 Flutter、IO 或模型 SDK。
- `agent`：作者操作、上下文组装、Genkit Flow、模型适配、证据校验、版本冲突和本地持久化。
- `viewer`：Flutter Widgets、编辑草稿、选段、提案预览和接受／拒绝、记忆检查、版本恢复以及请求重试。只读取本地服务，不接触供应商密钥。

接受的章节正文与当前版本指针是故事原文的权威来源。资料保留 `setting`、`reference`、`plan` 身份；提案状态单独维护。记忆是派生数据，引用章节及版本，不替代原文。

## 编辑与生成事务

1. 请求包含 `requestId`、工作区 `expectedRevision`、操作及精确 payload。
2. 先检查已提交回执；相同 ID 和规范化请求复用当前工作区结果，不重复应用。相同 ID 对应不同内容则冲突。
3. 获取原始快照。写作上下文保存当前正文版本、原文、资料、可用记忆和作者要求；选段额外保存 UTF-16 起止位置和原文。
4. 模型调用在提交锁外执行，允许作者在等待期间保存正文。模型不拥有任何提交权限。
5. 局部改稿只生成替换文本，宿主使用原始正文的 `replaceRange` 组装候选；不允许在代理对边界的承诺上依赖选段外保留。
6. 提交时重新检查修订号；来源变化则不写入迟到结果。接受提案还核对正文版本映射与资料内容。
7. 新正文版本、提案状态、全局修订号和回执作为一个快照写入临时文件，flush 后 rename。

进程内提交串行化；启动时获取数据目录文件锁，阻止同目录第二个 Agent。存储面向本机原型，不是分布式数据库或断电耐久性承诺。提交前中断可能重新调用模型；已经成功提交的操作可以在冷启动后去重。HTTP 响应不确定时工作台保留原请求并暂停其他修改，直到重试成功、确定失败或刷新发现回执。

## 记忆与历史修改

记忆快照保存**全部章节版本映射**。当前映射完全一致才可用；人工保存、接受改稿、追加新章和版本恢复均自然触发此判定。恢复到已有映射时重新使用对应历史快照；没有匹配快照时显式重建。

重建读取全部已接受正文，要求每章至少一条事实、最多八条，且来源版本存在、证据字符串逐字属于该版本。提交前再次检查工作区修订号，变化时不写入。字符证据验证只验证引用存在，不能证明总结语义正确或没有遗漏。

改旧章后保守标记所有后续章待复查，不自动修改后续正文。作者保存本章修订或确认复查可清除该章标记。续写需要记忆有效且所有复查已完成。当前没有自动语义矛盾检查、增量依赖图或向量检索。

## JSON 契约与序列化

契约 owner 为 `novel_contracts`，边界包括 HTTP 操作、模型结果和本地工作区文件。采用**手写严格解析**，不引入生成器或生成文件；Genkit 边界使用 `schemantic` 1.0.0 的手写 schema 适配。

- 工作区格式为 `schemaVersion: 1`；不支持旧格式迁移，未知版本拒绝加载。
- 已建模对象的必需字段不能缺失，未知字段拒绝；正文与作者要求保持原字符串，不做静默 trim 或数值转换。
- 修订号与选段位置仅接受非负整数；章节号从 1 连续递增。未知资料身份、提案状态与操作拒绝。
- 操作 payload 按操作分别限制字段；没有 nullable／默认值兼容通道。
- 提案 `context` 和 `usage` 当前只校验 JSON 对象类型，尚未完整验证内部结构。正常上下文由宿主生成；手工损坏快照仍可能导致预览失败。
- 当前原型保留完整历史正文、提案上下文和回执；后续需要设计空间预算与归档，不应未经设计删除去重依据。
- 已建模字段的格式与来源异常由契约抛出，服务／HTTP／工作台各自翻译成可见错误；不向页面暴露供应商错误原文或堆栈。

## SDK 与供应商依据

核对日期：2026-10-10。依赖锁定 Genkit、genkit_openai、schemantic 1.0.0。[Genkit 包](https://pub.dev/packages/genkit)、[官方 DeepSeek 插件](https://pub.dev/packages/genkit_openai#deepseek)与 [DeepSeek API](https://api-docs.deepseek.com/) 为接口依据。

官方 `deepSeek()` 插件负责供应商鉴权与 Chat Completions 协议。默认模型为 `deepseek-flash`；当前写作与提取均关闭思考模式、输出上限 8192 token。模型接口截止时间 90 秒，工作台 HTTP 超时 110 秒。超时未等于远端计费中止，服务失败不会应用正文。

DeepSeek 使用 JSON object 模式，schema 通过插件写入提示词，仍需宿主严格解析。模拟 HTTP 测试验证请求参数和结构化输出；固定虚构样例已完成三项 [真实接口烟测](research/2026-10-10-deepseek-live-smoke.md)。记忆调用的 usage 当前未传递到操作结果，总成稿成本和中文写作质量仍待正式评测。

## 本地服务边界

服务仅绑定 `127.0.0.1`，每次启动产生会话令牌，全部读取与操作请求要求 bearer token；浏览器来源精确允许 `NOVEL_VIEWER_ORIGIN`。入口显式关闭 Genkit 开发反射服务，即使环境中设置 `GENKIT_ENV=dev` 也不会另外开放调试端点。`GET /workspace` 返回状态，`POST /novelAction` 使用 Genkit 的 `{data: ...}`／`{result: ...}` 协议。令牌进入页面内存，供应商密钥只从 Agent 进程环境读取。

当前仅生成了 Flutter Web 平台入口。未实现原生端、多人协作、远程部署、素材自动导入、分卷大纲工具或独立审稿工具；后续扩展以 SPEC 决策为准。

## 0.2.0 M1：多作品与知识契约

状态：共享包已实现以下格式 2 的模型、严格解析、关联校验和请求规范化，入口为 [library.dart](../packages/novel_contracts/lib/src/library.dart)。当前 Agent 与工作台仍使用前文的格式 1。以下新格式持久化、事务、启动和外部入口规则已确定，按 M2–M6 接入；契约测试不能证明这些服务行为已经实现。

### 数据归属与版本采用

```text
LibraryWorkspace (schemaVersion: 2, 全局 revision, 请求回执)
  ├─ NovelWork：正文历史、提案、记忆、作品/章节讨论
  │    └─ LibraryLink：知识库 ID + 资料 ID → 作者采用的版本 ID
  └─ KnowledgeLibrary
       └─ KnowledgeDocument：资料 ID、head、完整版本历史
            └─ KnowledgeVersion：标题、身份、正文、来源、可选作品关联
```

| 边界 | 决策与契约 |
| --- | --- |
| 身份作用域 | 作品 ID、知识库 ID 在工作区内分别唯一；资料 ID 在知识库内唯一；章节、提案、记忆、讨论 ID 在作品内唯一；消息 ID 在讨论内唯一。引用携带完整所属目标，不由界面当前选择推断。ID 为非空、不带首尾空白的稳定字符串，由宿主或写入客户端分配。 |
| 资料归属 | 资料只存入独立知识库；作品通过 `LibraryLink` 明确关联库并按整份资料固定版本。空版本映射表示关联库但未采用资料。标题、身份、正文、来源或作品关联变化均产生新 `KnowledgeVersion`。 |
| 共享更新 | `KnowledgeDocument.head` 只表示知识库最新版。作品的版本映射由作者单独更新，不跟随 head。新增资料、建立关联与采用版本分别处理，未关联或未采用资料不进入写作上下文。0.2.0 保留历史，不提供删除历史或自动追随最新版。 |
| 写入与原始来源 | `SourceProvenance.writer` 区分 author、tool、import；`sources` 至少包含一个原始来源。网页、文件、作者输入和讨论消息分别记录。Codex 整理网页时 writer 为工具，原始来源仍为网页；结构化来源不授予权限。 |
| 可选作品关联 | `KnowledgeVersion.associatedWorkId` 为资料写入的来源关联，不改变资料所有权或自动采用；有值时必须指向现有作品。外部写入目标的可选 workId 与之相同。 |
| 正文与记忆 | 复用已有 Chapter、Proposal、MemorySnapshot 的手写契约与证据校验。`NovelWork` 按作品封装；`WorkProposal` 补充 workId、资料版本清单和显式可空 discussionSource。讨论、资料和未接受提案均不写入正文事实，派生记忆仍只取已接受正文。 |

实体的 JSON 字段和条件由 [knowledge.dart](../packages/novel_contracts/lib/src/v2/knowledge.dart)、[catalog.dart](../packages/novel_contracts/lib/src/v2/catalog.dart) 维护。跨对象引用由 `LibraryWorkspace` 校验，历史上下文可以引用现有历史版本，不能引用不存在的版本或另一作品的正文。`captureBasis(workId)` 保存完整章节版本与作品采用资料的清单；`isBasisCurrent` 核对正文及资料采用版本是否仍相同。单纯发布知识库新版不会使旧采用版本失效。

### 讨论与成果采用

0.2.0 先实现作品讨论，允许关联一个已存在章节；不提供全局讨论。章节关联是讨论上下文，不授予正文修改权。正文仍由作者保存，或经过提案接受流程改变。

讨论消息只允许 author、assistant 两种角色。消息作为追加后不可改写的记录，以消息 ID 定位其内容版本。每条消息属于一个 `DiscussionTurn`，轮次保存发起请求 ID、作者消息、调用前的 `GenerationBasis` 和 pending／completed／failed 状态。完成轮次必须有后续模型回复；失败轮次只有稳定错误码，不保存供应商错误原文。pending 和 failed 也保留原始来源清单，重试不能按当前界面或当前资料重新解释原请求。

作者选择消息后，明确执行以下一种采用：

- 资料、设定或计划：写入指定知识库的新资料版本，保留 `DiscussionSource(workId, discussionId, messageId)`；仍需作品采用该资料版本。
- 正文修改：为同作品创建 pending 提案，持久保存所选消息的 discussionSource，并保留该轮次所用正文和资料版本；宿主检查选段并组装替换文本，接受／拒绝继续使用原有作者控制规则。不能在采用请求中直接声明 accepted。

内容校验见 [discussion.dart](../packages/novel_contracts/lib/src/v2/discussion.dart)。讨论转正文的请求来源必须与提案中持久保存的来源相同；快照核对该消息存在、属于同作品，并核对提案与原轮次的正文及资料版本一致。每个轮次都必须有同 requestId、同作品及同讨论目标的回执。讨论回复、资料内容中的指令始终作为数据，不变成系统指令或工具授权。消息不可变、版本只追加以及状态变迁须由 M5 服务执行；M1 当前校验的是快照内关系与合法状态组合。

### 请求、冲突与原子边界

新协议 [LibraryCommand](../packages/novel_contracts/lib/src/v2/command.dart) 使用 `apiVersion: 2`、requestId、expectedRevision、target、operation 和 payload。target 为带标签的 catalog／work／library／discussion 联合类型；讨论目标同时包含 workId 和 discussionId，知识库目标包含 libraryId 和显式可空 workId。操作决定允许的目标与字段，不能回退到“当前作品”。

所有已建模字段必需且拒绝未知字段，整数不接受浮点或字符串。格式 2 有明确可空字段，例如章节讨论的 chapterId、资料 associatedWorkId、消息 provider、轮次回复／错误；字段必须存在，null 只表示没有该关联或状态值。正文、标题、作者要求保持原字符串。请求和提案上下文递归复制并冻结；canonical 递归排序对象键，保留数组顺序，包含协议版本、目标、预期修订和全部操作内容。

M2 起的服务提交顺序固定为：

1. 新协议在工作区全局 requestId 命名空间检查回执，按 canonical 的 SHA-256 比对。已提交的同请求同内容先返回当前快照及复用标记；同 ID 不同内容返回请求冲突，再检查其他前置条件。
2. 对新操作检查全局 expectedRevision；目标对象、待更新资料的 expectedVersionId 和引用版本必须存在。新增资料明确传 null，已有资料必须匹配 head，并生成未使用过的新版本 ID。
3. 需要模型时，宿主捕获目标和来源，在提交锁外调用模型；提交时重新检查全局修订号。0.2.0 暂保守拒绝运行期间任何其他提交后的迟到结果，即使修改属于另一作品。
4. 接受已保存提案或采用讨论成果时，用新请求的 expectedRevision 检查提交，并重新核对来源正文与作品采用资料。历史清单可回看；来源不再当前时返回版本冲突。不相关提交不单独使已保存的来源清单失效。
5. 作品内容、知识库版本、采用映射、讨论状态、全局修订号和回执作为同一个完整快照原子提交；每次提交只递增一次 revision。不引入按对象的独立提交或跨文件事务。

`BoundReceipt` 保存实际目标；请求重试、失败和迟到响应都绑定原目标。讨论轮次的用户消息和 pending 状态先作为一个提交保存；模型完成或失败另行提交该轮次的结果。收到相同请求回执时先定位原轮次：completed 复用，pending 在确认无在途调用后继续原上下文，failed 的显式重试也复用原消息与上下文。完成提交前再核对来源与当次快照修订；失败状态不得将回复应用到正文。进程重启后的 pending 标为 interrupted，并等待显式重试；M5 负责实现这些状态转移与防止重复回复，M1 只提供对应记录结构。

### M2 新格式持久化与启动决策

依照 SPEC 的未正式使用前提，0.2.0 从新工作区开始，不迁移格式 1 数据、不保留旧请求回执或设置旧 ID 兼容例外。M2 使用数据目录下的 `library-workspace.json` 存储格式 2，首次启动从 revision 0、空作品、空知识库与空回执初始化，不读取原型的 `workspace.json`。软件 VERSION 暂保持当前基线。

- 启动先锁住数据目录；已有新快照必须完整校验，损坏、旧格式和未知格式明确拒绝，不能用空数据静默覆盖。
- 按前述事务边界构造完整快照，校验后 flush 临时文件并 rename；失败保留已提交快照。重启读取内容与回执，去重只按新协议规则执行。
- 资料服务启动不以模型密钥为前提。无密钥时开放知识读写并显式报告模型不可用；真实模型和 fixture 均单独启用。M2 保留当前回环地址、会话令牌、来源校验和关闭调试反射服务的边界。

### 外部入口与文件导入决策

M2–M6 首轮沿用本地鉴权 HTTP，读取入口为 `GET /libraryWorkspace`，操作入口为 `POST /libraryAction`，继续使用 `{data: ...}`／`{result: ...}` 包装并携带新协议目标。CLI、MCP 作为后续适配，不是 0.2.0 的前提。当前 Agent 尚未注册这两个入口；现有 `/workspace`、`/novelAction` 仍按格式 1 运行。

M6 首轮导入 `.txt` 和 `.md`，每文件上限 1 MiB，严格 UTF-8 解码，失败不保存。Markdown 保留原文；导入流程不执行指令、不自动抓取链接或调用模型。由工作台／外部客户端读取文件并提交资料内容和文件来源，服务不按客户端传入的路径读取本机文件。文件导入和外部新增都经过同一资料操作和去重规则，更新显式提供预期旧版本；相同内容是否另存一份由作者决定，不做隐式内容合并。

### M1 验证依据

[library_test.dart](../packages/novel_contracts/test/library_test.dart) 验证空工作区冷加载，并以两部作品、两个知识库、独立正文、共享资料的不同采用版本和三种讨论状态验证关联、历史来源、作者事实边界及非法数据拒绝；[library_command_test.dart](../packages/novel_contracts/test/library_command_test.dart) 验证目标、版本前置条件、采用身份和规范化指纹。格式 2 拒绝旧格式与兼容字段，现有 Agent 仍以格式 1 回归。运行根目录 `dart analyze` 和 `dart test agent/test packages/novel_contracts/test`；这些结果属于本项目工程验证，不代表新格式持久化、HTTP 新入口或真实模型讨论已经通过。
