# 项目架构

更新日期：2026-10-12。产品范围与行为要求由 [SPEC.md](../SPEC.md) 维护；前文记录 `prototype_agent.dart` 的 0.1.0 运行边界，后文记录 0.2.0 M1 契约、M2 资料服务、M3 多作品正文和工作台，M4 知识库与资料版本采用，以及 M5 持续讨论与成果采用。软件版本与发布规则见 [版本管理](versioning.md)，其版本号独立于下文的数据格式与正文版本。参考本机 `harrypet_flutter/labs/story-pet-agent` 的包分工，未修改该项目或复制其宠物／世界模板业务。

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

状态：共享包已实现以下格式 2 的模型、严格解析、关联校验和请求规范化，入口为 [library.dart](../packages/novel_contracts/lib/src/library.dart)。默认 Agent 与工作台使用格式 2；M2 接入资料服务，M3 接入多作品正文与界面，M4 接入资料采用，M5 接入持续讨论与成果采用；导入按 M6 推进。

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

### M2 新格式持久化与启动

已实现：[FileLibraryRepository](../agent/lib/src/library_repository.dart)、[LibraryService](../agent/lib/src/library_service.dart)、[LibraryRuntime](../agent/lib/src/library_runtime.dart) 由默认 [novel_agent.dart](../agent/bin/novel_agent.dart) 启动。依照 SPEC 的未正式使用前提，从新工作区开始，不迁移格式 1 数据、不保留旧请求回执或设置旧 ID 兼容例外。数据目录下的 `library-workspace.json` 存储格式 2，首次启动从 revision 0、空作品、空知识库与空回执初始化，不读取原型的 `workspace.json`。软件 VERSION 暂保持当前基线。

- 启动先锁住数据目录；已有新快照必须完整校验，损坏、旧格式和未知格式明确拒绝，不能用空数据静默覆盖。
- 基础操作在同一服务队列内读取、先查回执、检查全局 revision 与资料 head、构造完整快照，校验后 flush 临时文件并 rename；失败保留已提交快照。回执与资料一起提交，不另存索引。重启忽略未提交 `.tmp`，读取已提交内容和回执；同内容重试返回当前快照及 `reused: true`。没有模型调用，无需单独维护在途请求表。仓库的修订检查是单服务、目录独占前提下的保护，不是跨进程数据库 CAS；不承诺断电耐久性。
- 资料服务启动不以模型密钥为前提，无密钥也开放读写。真实模型仅在环境中有密钥时配置，fixture 仅由 `--fixture` 配置；未配置模型的生成请求报告 `model_unavailable`。正文模型操作已由 M3 接入；讨论由 M5 接入，其模型状态与重试规则见下文。资料保存始终不调用模型。
- 默认入口与独立 [prototype_agent.dart](../agent/bin/prototype_agent.dart) 共享 [本地 HTTP 鉴权边界](../agent/lib/src/local_http.dart)：回环绑定、每次启动随机会话令牌、精确 Origin 与关闭 Genkit 反射服务。当前界面使用格式 2 服务；独立原型保留用于工程回归，不在格式 2 服务注册旧路由，不兼容当前工作台。

已开放的 M2 操作：

| operation | target | 行为 |
| --- | --- | --- |
| `createWork` / `createLibrary` | `catalog` | 客户端提供未使用 ID 与标题／名称，创建空目标 |
| `renameWork` | `work` | 仅更改指定作品名称，保留其余状态 |
| `renameLibrary` | `library`，workId 为 null | 仅更改指定知识库名称 |
| `saveDocument` | `library`，workId 显式可空 | 新增传 expectedVersionId 为 null；更新匹配 head 并使用新版本 ID，追加完整版本，保留历史与结构化来源 |

资料的 associatedWorkId 必须与请求 target.workId 相同且关联作品存在；关联只表达来源归属，不更新作品采用映射。讨论来源须能在快照中定位；创建讨论和主动采用成果由 M5 接入。对象 ID 冲突、缺失目标、非法引用或版本冲突均不提交，回执检查仍优先于这些前置条件。

`GET /libraryWorkspace` 直接返回 `{workspace, provider, modelAvailable, reused}`；`POST /libraryAction` 输入 `{data: LibraryCommand}`，成功输出 `{result: 同一结果结构}`。provider 未配置时为 null；modelAvailable 只表明已配置模型，不表示后续模型流程已经开放。HTTP 操作错误沿用 Genkit 1.0.0 的 `{code, status, message}`：输入无效与前置条件为 400，冲突为 409，无法确认存储结果为 500；服务错误码属于 Dart 边界，SDK 不把 exception.details 输出为 HTTP 字段。鉴权与路由错误沿用本地 `{error: {message}}`。结果不确定时保留原请求重试。

### 外部入口与文件导入决策

M2 已注册上述本地鉴权 HTTP 入口；M6 的导入与工具调用复用此入口及资料事务。CLI、MCP 作为后续适配，不是 0.2.0 的前提。原型入口的 `/workspace`、`/novelAction` 仍按格式 1 运行。

M6 首轮导入 `.txt` 和 `.md`，每文件上限 1 MiB，严格 UTF-8 解码，失败不保存。Markdown 保留原文；导入流程不执行指令、不自动抓取链接或调用模型。由工作台／外部客户端读取文件并提交资料内容和文件来源，服务不按客户端传入的路径读取本机文件。文件导入和外部新增都经过同一资料操作和去重规则，更新显式提供预期旧版本；相同内容是否另存一份由作者决定，不做隐式内容合并。

### M1 验证依据

[library_test.dart](../packages/novel_contracts/test/library_test.dart) 验证空工作区冷加载，并以两部作品、两个知识库、独立正文、共享资料的不同采用版本和三种讨论状态验证关联、历史来源、作者事实边界及非法数据拒绝；[library_command_test.dart](../packages/novel_contracts/test/library_command_test.dart) 验证目标、版本前置条件、采用身份和规范化指纹。格式 2 拒绝旧格式与兼容字段；原型 Agent 的格式 1 另行回归。

### M2 验证依据

[library_service_test.dart](../agent/test/library_service_test.dart) 验证目标隔离、历史追加、来源保留、去重优先级、并发冲突和模型解耦；[library_repository_test.dart](../agent/test/library_repository_test.dart) 验证空初始化、冷启动、旧／损坏格式拒绝、临时写入失败和未提交临时快照；[library_server_test.dart](../agent/test/library_server_test.dart) 启动真实本机进程，验证无密钥鉴权 HTTP、强制重启去重、单写锁、存储失败恢复和关闭调试反射。完整命令见 [README 验证](../README.md#验证)。这些是工程与本地进程证据，不包含断电测试、格式 2 模型写作、UI 接入或真实 DeepSeek 质量验证。


### M3 多作品与目标隔离

已实现：[LibraryWorkbench](../viewer/lib/src/library_workbench.dart) 与 [LibraryController](../viewer/lib/src/library_controller.dart) 使用格式 2 网关，支持创建、命名、列出和切换作品。默认 Agent 与 `tool/run_deepseek.sh` 服务当前工作台；格式 1 独立入口保留用于原型回归。新服务仍从空数据开始，不迁移旧原型。

- 每部作品有独立的编辑与请求控制器，工作台按作品保持页面实例，章节仍按 ID 保持编辑实例。即使不同作品使用相同章节 ID，草稿、选区、章节选择、正文保存确认、错误与未知结果也不混用。草稿仅保存在页面内存中，切换和宽窄布局变化不丢失，刷新页面不恢复未保存内容。
- 正文状态、历史菜单、记忆证据和提案上下文中的正文版本，按该章节 `versions` 的追加顺序显示“第 N 版”；记忆及提案的来源标签包含章节 number 和标题，以区分同名章节。恢复只切换 head，原序号保持；之后保存继续追加。内部 versionId 仍供恢复与来源校验使用，原快照无需改写，全局 revision 继续用于并发提交。
- 每个作品网关创建时固定 workId；发起操作、生成要求对话框、历史操作和原请求重试都使用该目标，不读取提交时的界面选择。后台状态提供返回原作品的入口。响应更新目录和各作品视图，但不改变当前选择；修订号较旧的响应不会回退已有快照。刷新已读到成功回执后，原连接的迟到失败仍按成功处理，不重新阻断写入。
- [LibraryService](../agent/lib/src/library_service.dart) 接入 `createChapter`、`saveChapter`、`proposeChapter`、`proposeEdit`、`acceptProposal`、`rejectProposal`、`restoreVersion`、`rebuildMemory`、`confirmReview`。它对一个作品的纯领域视图复用已有正文事务引擎，再将目标作品、全局修订号与带目标的回执提交为一个格式 2 快照；领域视图不作为格式 1 HTTP 或存储入口。
- `createChapter` 使用作品目标与 `{chapterId, title}`，在末尾追加具名空白章节和空正文初始版本，不调用模型；重复章节 ID 被拒绝，原请求重试复用回执。空正文版本可序列化并恢复，已有非空版本仍兼容。宽窄界面均提供手动入口，创建确认后选中新章，其他章节草稿保持；响应丢失时标题保留并允许核对或原请求重试。空白章节先填写保存，再重建记忆或续写，防止空章产生事实。AI 新章 ID 避开已有手动章节。
- 生成与记忆重建在提交队列外调用模型，同请求的在途生成合并；提交前重新检查全局 revision，任何其他提交都会使迟到生成冲突。手工正文与目录操作不调用模型，无密钥仍可新建章节、保存正文、命名、复查与恢复。已提交回执先于修订号和模型可用性检查，重启或响应丢失后可复用原请求。
- 上下文只含目标作品正文、当前记忆与明确采用的资料版本，并保存 workId 和来源清单。接受提案时再次核对正文 heads 与采用版本；同文资料换版也不能绕过冲突。改旧章、历史恢复、记忆重建及后续复查只影响目标作品，原有选段外保留与作者接受／拒绝边界沿用。

M3 不为新作品隐式创建或采用知识库；正文资料区只读展示已采用资料。知识库管理与采用在 M4 接入，讨论由 M5 接入，文件导入待 M6。模型未配置时，调用生成显式失败，作品管理仍可用。

验证入口：[library_body_test.dart](../agent/test/library_body_test.dart) 覆盖正文与历史隔离、拒绝与选段外保留、旧章复查、记忆恢复、无模型手工操作、在途重复、失败重试及正文／资料来源冲突；[library_server_test.dart](../agent/test/library_server_test.dart) 以真实本机 HTTP 进程保存两作品，再强制重启核对名称、正文历史、提案、记忆与回执。[library_workbench_test.dart](../viewer/test/library_workbench_test.dart) 覆盖同章节 ID 的草稿与选区隔离、作品命名、宽窄布局、切换后的保存／生成响应、失败、原请求重试与刷新确认回执；[library_gateway_test.dart](../viewer/test/library_gateway_test.dart) 覆盖格式 2 路由、鉴权头、请求目标与确定／未知失败；[library_controller_test.dart](../viewer/test/library_controller_test.dart) 核对较旧的 A 响应不能回退刷新及 B 保存后的目录，并覆盖刷新先确认回执、原连接后失败的交错；没有原请求回执时仍保持结果未知。以上属于工程、测试模型与演示验证，没有执行本轮真实 DeepSeek 调用或中文写作质量评测。

2026-10-12 验证结果：168 项 Agent／契约回归通过；补充手动章节入口及章节版本显示后，56 项工作台测试、`dart analyze`、`dart run tool/version.dart --check`、`flutter build web --no-pub` 通过。新增验证覆盖空白章节的无模型 HTTP 创建、强制重启与手写保存、重复请求、空章记忆阻断、章节 ID 冲突及宽窄界面的手动创建、标题校验和旧章草稿保留。版本显示的 4 项组件回归在各自修复前失败、修复后通过，覆盖跨作品／章节序号、目录命名、恢复请求的原 ID、恢复后保存、记忆／提案中的来源版本及同名章节的事实与原文证据归属；见 [workbench_test.dart](../viewer/test/workbench_test.dart) 与 [library_workbench_test.dart](../viewer/test/library_workbench_test.dart)。此前审核发现的迟到失败覆盖成功回执问题已修复，对应控制器与组件回归在修复前失败、修复后通过。浏览器核对已显示章节加号、标题对话框与两作品各自的第 2 版，历史菜单显示本章序号；原作品及正文保持可读。

同日补充同名章节的浏览器完整流程：在独立验收作品中手动创建、保存两章“重逢”，两章均为第 2 版时，重建记忆后的事实及原文证据、选段改稿提案上下文均可通过“第 1 章／第 2 章”区分。拒绝提案保留原文；接受第二章改稿后仅该章升为第 3 版，记忆失效并阻止续写。重建后，记忆证据和新续写提案分别引用第一章第 2 版、第二章第 3 版；拒绝续写不新增章节，刷新后正文及记忆来源仍一致。保存快照中的章节身份、原文证据、提案来源和状态也已核对。本次使用 `fixture/local` 本地演示模式，未执行真实 DeepSeek 调用或中文写作质量评测。

### M4 独立知识库与明确版本采用

已实现：`LibraryService` 的 `setKnowledgeLinks` 操作以作品为目标，在完整快照事务内替换知识库关联与整份资料版本映射，保留正文、提案、讨论和记忆。关联库、资料和版本不存在时返回 `invalid_reference`，不产生回执或半条关联；旧全局修订号返回 `version_conflict`。创建／命名知识库和资料版本保存复用 M2 的 head 校验、原子提交及全局请求去重，无需模型。

工作台 [KnowledgePanel](../viewer/lib/src/knowledge_panel.dart) 提供独立知识库创建／命名、作品关联／取消关联、逐份采用最新版／停止采用，以及历史版选择；没有作品也能管理资料。[资料编辑器](../viewer/lib/src/knowledge_editor.dart) 保留原文、资料身份、多个结构化原始来源和可选来源关联作品，手动修改的写入者为 author；旧版本保留原写入者与来源。可选作品关联只作来源归属，不自动采用。编辑时捕获目标库、资料 ID 和原 head；冲突保留草稿，加载新版需作者明确放弃本地编辑。未知结果保留原请求并阻断其他写入，刷新回执或同请求重试后继续。管理界面与正文持续挂载，往返与作品切换保留正文草稿、选区和章节选择。

共享发布只推进资料 head。各作品继续使用采用映射中的固定版本，新增资料或空库关联不会进入上下文。采用清单在作品正文视图中按知识库／资料 ID 固定排序，改变清单排列而不改变版本不会让提案失效。模型的 `knowledgeDocuments` 同时保存知识库／资料／版本 ID、库名称，以及对应 `KnowledgeVersion` 的标题、身份、原文、写入者、原始来源和可选作品关联；`basis.documents` 是来源当前性校验依据。提案预览展示生成时的这份清单，历史仍可追溯到保留的资料版本。

接受提案按作品当前正文与实际采用清单检查；仅发布共享新版不使已保存提案失效，作品改用其他版本、停止采用或取消引用则拒绝接受旧来源提案。模型调用在途期间任何快照提交仍保守触发全局修订冲突，包括仅发布共享新版。资料及采用操作不改正文、不产生故事事实、不重建或使现有正文记忆失效；记忆继续只取已接受正文。M4 不包含自动追随新版、资料历史删除、向量检索、讨论成果采用或文件导入；讨论成果采用由 M5 接入。

M4 验证依据（2026-10-12）：

- [领域测试](../agent/test/library_knowledge_test.dart) 覆盖 A 引用 K1/K2、B 引用 K1、C 未关联，固定版本及完整来源进入上下文、历史提案追溯、发布与采用的独立性、接受冲突、采用排列不变性、非法引用、重试和在途生成冲突。M2 的资料旧 head 更新与请求冲突回归继续通过。
- [HTTP 验收](../agent/test/library_knowledge_server_test.dart) 在无模型进程保存多个库及多作品引用，发布／采用后强制终止并重启，核对完整快照、来源、历史、作品旧引用和去重回执；旧资料版本更新返回可见冲突并保留新版。
- [工作台验证](../viewer/test/knowledge_workbench_test.dart) 覆盖无作品／无模型管理、历史版采用、共享新版提示、工具和原始来源展示、正文往返草稿／选区／章节选择保留、编辑冲突与显式加载、未知结果原请求重试、切换作品／库的迟到目标绑定，以及 390 宽度和 1.5 倍字号。草稿丢失和采用清单重排两个回归均在修复前失败、修复后通过。
- 仓库 175 项 Agent／契约测试、67 项工作台测试、静态分析、版本检查及 Web 构建通过。独立复审核对核心服务、HTTP 和界面，发现的草稿问题已修复；无模型 UI 测试夹具也明确设为不可用。浏览器用隔离数据目录与 fixture 演示模型核对共享资料、计划身份、各作品采用和提案来源。工程与演示验证不代表真实 DeepSeek 调用或中文成稿质量评测通过。


### M5 持续讨论与作者选择采用成果

已实现：[讨论事务](../agent/lib/src/library_discussion.dart) 与 [讨论界面](../viewer/lib/src/discussion_panel.dart) 提供具名作品讨论、可选章节关联、多轮记录和逐轮正文／资料版本查看。消息只追加，未采用的讨论、参考或计划均不修改正文和派生记忆。输入按作品和讨论保存在当前页面，浏览器页面重载不恢复未发送草稿；保存的记录随格式 2 快照持久化。作者在等待回复期间仍可编辑下一轮草稿，迟到响应仅确认原请求，不清空后续输入。

| operation | target | 行为 |
| --- | --- | --- |
| `createDiscussion` | `work` | 新建空讨论；客户端指定 id、title 和显式可空 chapterId，关联章必须属于该作品 |
| `sendDiscussionMessage` | `discussion` | 指定 messageId、body；先提交作者消息、来源、pending 与回执，再在提交锁外调用模型并提交 completed／failed |
| `adoptDiscussionMessage` | `library` | source 定位不可变消息；资料版本保存其讨论来源，明确参考／设定／计划身份、目标库与预期旧 head，不调用模型、不自动采用到作品 |
| `adoptDiscussionMessage` | `work` | 仅同作品 pending 改稿提案；宿主检查来源、选段及替换文本并重新组装候选，后续接受／拒绝沿用正文引擎 |

讨论完成或失败是另一笔完整快照提交，保持首笔请求回执，不改 fingerprint。HTTP 成功返回快照也可能包含 failed；客户端检查轮次状态，pending 回执只确认作者消息已保存。稳定错误码为 model_unavailable、model_failed、version_conflict、interrupted，不保存供应商原始错误。并发同请求合并；completed 重试直接复用，pending／failed 的显式重试复用原消息与来源。服务初始化把遗留 pending 原子改为 interrupted，等待显式重试。较早失败轮次之后已有新轮时禁止补写旧回复，作者发起新一轮；来源已变的原请求仅保留冲突状态，不以当前资料重解释旧请求。

网络响应丢失后，刷新仍为 pending 时保留原请求；读到终态时解除待确认状态，completed 清除旧网络错误，failed 展示稳定失败原因。

[共享上下文与选段组装](../packages/novel_contracts/lib/src/discussion_context.dart) 按保存的 basis 读取历史正文、资料版本和该作者消息之前的讨论记录。模型上下文使用稳定资料 ID 与版本，省略可变库名称，改名后的原请求重试仍保持上下文一致；界面可显示当前库名称并核对稳定 ID。资料与讨论文本只作为数据进入讨论提示，不授予系统或工具权限。调用期间任何其他快照提交仍保守拒绝迟到回复；失败状态写入原讨论，保留其他作品的提交。保存成果或接受提案时则重新核对正文 heads 与实际采用资料版本，不相关提交不使既有来源失效。

[成果采用表单](../viewer/lib/src/discussion_dialogs.dart) 捕获所选消息和原目标，保留编辑内容、冲突与未知结果的原请求。资料可保存在任意明确目标库，讨论来源保留源作品／讨论／消息 ID；作品采用资料版本仍是另一操作。改稿表单选择非空目标章与原文片段，显式提供 replacement；服务验证 UTF-16 字符边界、非空选段、长度、版本、选段原文和候选全文，拒绝伪造选段外修改。持久提案保留原轮 basis、discussionSource、引用资料与选段；资料保存和提案创建均不调用模型。原文只在作者接受后改变，旧章变更使后续章待复查、记忆失效；恢复旧版本可复用匹配的历史记忆。

M5 验证依据（2026-10-12）：

| SPEC 验收 | 行为验证 |
| --- | --- |
| 三轮交互、切换隔离、重启回看 | [11 项领域测试](../agent/test/library_discussion_test.dart)、[HTTP 进程验收](../agent/test/library_discussion_server_test.dart)、[12 项界面测试](../viewer/test/discussion_workbench_test.dart)；三轮历史输入长度为 1／3／5，A／B 讨论不串用 |
| 未采用不改事实；明确采用及选段边界 | 无模型保存参考／设定／计划且不自动采用；宿主组装选段，拒绝保持原文、接受失效记忆并标记后续复查、恢复回到一致基线；伪造整章和跨作品提案被拒绝 |
| 去重、来源冲突、迟到结果原目标 | 并发同请求、完成与采用回执复用；旧资料 head、正文和采用版本冲突；切换作品、待完成回执、刷新确认后的迟到网络失败，以及响应丢失后刷新同步 completed／failed 的错误提示 |
| 无模型读取／采用、失败和中断显式重试 | HTTP 三轮后 SIGKILL 重启到无模型服务回看并保存计划；真实文件仓库与服务的隔离 worker 在模型等待时 SIGKILL，默认 Agent 启动标记 interrupted，原请求重试仅追加一条回复 |

189 项 Agent／契约测试、79 项工作台测试、静态分析、版本检查与 Web 构建通过。模拟 DeepSeek HTTP 核对多轮内容与资料指令仅进入用户数据；属于模拟供应商验证。独立复审核对事务、来源、作者采用与界面，已确认问题均有修复前失败／修复后通过的回归；复核者另行运行领域、HTTP／中断恢复、模拟供应商与界面测试。HTTP 进程测试在允许本机回环监听的环境运行。浏览器验收使用独立 `.local/` 数据目录和 fixture 演示模型，完成连续三轮讨论、保存计划、核对来源与未自动采用，并验证首轮后的输入仍可继续编辑；真实讨论接口烟测与中文写作质量仍未执行，按 M7 和独立质量评测推进。没有新增数据字段或格式迁移，软件版本仍为 0.1.0。
