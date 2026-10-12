# Novel Agent Lab

面向小说作者的知识库与写作工作台。作者主导创作，Agent 辅助续写和改稿。采用 Flutter Web、Dart Agent、Genkit Dart 1.0.0 与 DeepSeek 插件。0.2.0 的基础资料服务已可独立运行，工作台仍为单作品原型。

软件版本以 [VERSION](VERSION) 为准；当前原型登记为 0.1.0，下一阶段 0.2.0 的需求与推进计划见 [SPEC.md](SPEC.md#020-推进计划)。版本规则见 [版本管理](docs/versioning.md)，已实现变更见 [CHANGELOG](CHANGELOG.md)。

M1 契约与 M2 持久化、事务去重及无模型资料服务见 [架构说明](docs/architecture.md#020-m1多作品与知识契约)。新服务使用格式 2，从空数据开始；正文、资料采用、讨论及界面接入继续按 SPEC 推进。

## 本地运行

已验证工具环境：Flutter 3.44.1、Dart 3.12.1。Genkit 相关依赖固定为 1.0.0，并提交根目录 `pubspec.lock`。

仓库根目录安装依赖：

```sh
flutter pub get
```

启动 M2 资料服务，无需 API 密钥：

```sh
dart run agent/bin/novel_agent.dart
```

首次创建空 `library-workspace.json`，不会读取或迁移旧 `workspace.json`。使用启动时显示的会话令牌调用 `GET /libraryWorkspace` 与 `POST /libraryAction`；响应报告模型配置状态。基础操作为创建、命名作品和知识库，以及新增／更新资料版本，资料保存不调用模型。协议与结果结构见 [M2 入口说明](docs/architecture.md#m2-新格式持久化与启动)。

以下例子创建一部作品；`$NOVEL_SESSION_TOKEN` 是本次启动的会话令牌：

```sh
curl http://127.0.0.1:4100/libraryAction \
  -H "Authorization: Bearer $NOVEL_SESSION_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"data":{"apiVersion":2,"requestId":"create-first-work","expectedRevision":0,"target":{"kind":"catalog"},"operation":"createWork","payload":{"id":"first-work","title":"第一部作品"}}}'
```

保存知识库与资料时，使用当前 revision、明确目标、未使用的请求 ID 和资料新版本 ID。结果未知时重试原请求；服务先检查已提交回执。数据目录默认 `.local/novel-data`，由 `NOVEL_DATA_DIR` 指定；同一目录只允许一个 Agent 进程。已有新快照格式错误会拒绝启动，不会重置为空库。

M2 的 `--fixture` 或供应商密钥仅配置模型，格式 2 的正文／讨论模型操作尚未开放；无配置时报告不可用，有配置时报告操作尚未接入。当前工作台尚未消费新接口，请用下面的独立原型入口体验正文闭环。

终端一，在仓库根目录启动单作品演示原型：

```sh
dart run agent/bin/prototype_agent.dart --fixture
```

终端二启动工作台：

```sh
cd viewer
flutter run -d web-server --web-hostname localhost --web-port 4300
```

打开 `http://localhost:4300`，填写 Agent 启动时显示的**工作台会话令牌**。Agent 地址默认 `http://127.0.0.1:4100`。令牌仅保存在页面内存中；刷新页面后重新填写。

初始作品“雨夜来信”包含两章自写样稿、设定、未来计划、参考资料和记忆。演示模型只返回固定的局部修改或续写样稿，用于检查工作台流程，不用于评判模型写作质量。

原型的真实 DeepSeek 模式，在终端一设置 `DEEPSEEK_API_KEY` 后运行：

```sh
dart run agent/bin/prototype_agent.dart
```

默认模型为 `deepseek-flash`，可通过 `DEEPSEEK_MODEL` 切换。不要将 API 密钥传给 Flutter 或写入已跟踪文件；本地配置放在 `.local/`。示例字段见 [.env.example](.env.example)，程序读取进程环境，不会自动加载该文件。

已在本机配置 `.local/deepseek.env` 时，也可在仓库根目录直接启动：

```sh
tool/run_deepseek.sh
```

该脚本在进程没有 `DEEPSEEK_API_KEY` 时加载本地配置，默认使用独立 `.local/deepseek-data`；端口仍为 `4100`。工作台连接方法同上。当前固定样例的真实续写、记忆提取与选段改写已通过，详见 [真实接口烟测记录](docs/research/2026-10-10-deepseek-live-smoke.md)，尚未完成正式写作质量评测。

| 环境变量 | 默认值／用途 |
| --- | --- |
| `DEEPSEEK_API_KEY` | 真实模型配置必需；M2 资料服务可不设置，仅 Agent 读取 |
| `DEEPSEEK_MODEL` | `deepseek-flash` |
| `NOVEL_AGENT_PORT` | `4100`，服务仅绑定本机回环地址 |
| `NOVEL_VIEWER_ORIGIN` | `http://localhost:4300`，精确匹配浏览器来源 |
| `NOVEL_DATA_DIR` | 仓库根目录启动时为 `.local/novel-data` |

原型的正文、版本、提案、上下文、记忆和回执保存在该目录的 `workspace.json`，重启继续现有作品；演示模式与真实模式默认共用同一目录。两个入口使用不同快照文件但共用目录锁；同时运行时指定不同的 `NOVEL_DATA_DIR` 和端口。没有旧数据互转。

## 体验闭环

1. 在第一章选中“信纸上写着……”一段，点击“改写选段”。查看提案的修改前后正文，接受或拒绝。
2. 接受后，旧记忆失效，第二章标记待复查；第二章正文仍保留原样。
3. 检查第二章，手工修正它仍沿用的知情信息并保存，或者在核对后明确选择“已复查，无需改动”。
4. 点击“重建记忆”，查看每条事实对应的章节版本与原文证据，再起草下一章。续写也先成为提案。
5. 从“历史版本”恢复第一章；只有全部当前章节版本与历史记忆快照匹配时，旧记忆才重新可用，否则需要重建。

未保存的章节草稿在切换章节和调整窗口布局时保留；刷新冲突时不会覆盖本地草稿。保存等待期间继续输入的正文会保留，成功后仍可继续保存。资料表单在保存确认成功后关闭，失败或结果未知时保留输入并提供刷新／重试入口。上次操作响应不确定时，使用“重试上次操作”复用同一请求，或刷新确认回执。

## 验证

仓库根目录：

```sh
dart run tool/version.dart --check
dart analyze
dart test agent/test packages/novel_contracts/test
```

工作台目录：

```sh
flutter test --no-pub
flutter build web --no-pub
```

Agent／契约测试覆盖 M1 契约，M2 资料历史、目标隔离、事务去重、存储失败和无模型进程 HTTP／重启，以及原型正文闭环和 Genkit DeepSeek 模拟 HTTP 请求。工作台测试验证原型交互；M2 不修改工作台。模拟响应不代表真实 DeepSeek 调用成功，写作质量需要另外评测。

## 阅读入口

| 文档 | 内容 |
| --- | --- |
| [SPEC.md](SPEC.md) | 已确认需求、实现范围、待决事项与验收 |
| [版本管理](docs/versioning.md) | 版本来源、同步检查、数据版本与发布标签规则 |
| [CHANGELOG.md](CHANGELOG.md) | 已实现变更、版本基线与验证依据 |
| [架构说明](docs/architecture.md) | 包边界、状态事务、JSON 契约与限制 |
| [小说 Agent 调研索引](docs/research/README.md) | 模型、写作评测与后续调研 |
| [InkOS 学习笔记](docs/references/inkos-learning.md) | 固定上游快照的机制与限制 |
| [AGENTS.md](AGENTS.md) | 执行规则 |
