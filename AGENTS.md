# Project Guidelines

## 修改前阅读

- 先读 [SPEC.md](SPEC.md)，确认项目阶段、已确认需求与待决事项。
- 调研 InkOS 或选择写作内核时，读 [InkOS 学习笔记](docs/references/inkos-learning.md)；其中的上游实现和核验结论只适用于标注的快照。
- 模型选型或写作质量评测前，读 [调研索引](docs/research/README.md) 和对应专题，区分价格快照、候选建议与实际测试结果。后续小说 Agent 调研按索引约定在本仓库归档。
- [README.md](README.md) 是阅读入口。产品范围与验收由 SPEC.md 维护，外部方案的学习记录由学习笔记维护，避免重复维护同一事实。
- 软件升版或维护变更记录前，读 [版本管理](docs/versioning.md)；根目录 `VERSION` 为软件版本来源，未来计划留在 SPEC.md，已实现变更登记到 CHANGELOG.md。

## 项目边界

- 本目录是独立项目，改动限定在本仓库；无需更新其他 workspace 的配置或文档。
- 当前为 Flutter Web + Dart Genkit 本地原型；包边界、事务与 JSON 契约见 [架构说明](docs/architecture.md)。新增实现时，根据实际代码补充运行和验证命令，不把上游命令写成本项目命令。
- 将已确认需求、待验证设计、上游实现和已实现行为明确区分。不能把 InkOS 的功能或测试结论当作本项目已具备的能力。
- 作者对正文和设定的控制、正文版本与记忆的一致性是实现和评审的重点；具体产品约束以 SPEC.md 为准。
- 保留源码链接与版本依据。学习外部设计不等于已经决定复制源码或 fork；发生这一决策时更新 SPEC.md。
- 密钥和机器本地配置不得写入版本化文档或源码；本地临时内容放入 `.local/`。

## 修改与验证

- 修改人工维护源代码后超过 3000 行时，在文件头部合适位置用该语言的注释语法添加 `TODO 待拆分`。生成代码、第三方代码和构建产物除外；不为此扫描无关文件，也不顺带重构。
- 文档修改检查事实归属、链接、阶段和能力声明；有实现后，按改动风险执行相应的行为验证。
- 版本相关修改后运行 `dart run tool/version.dart --check`；新增 workspace 包时同时纳入版本检查。
- 关键验证包括选段外内容保留、拒绝与撤销、修改后的记忆同步、版本冲突，以及中断和重试；具体场景以 SPEC.md 为准。
- 本项目测试与上游测试分别报告；演示模型和模拟 HTTP 测试不能描述为真实 DeepSeek 或中文写作质量测试通过。

## 实现与命令

- `packages/novel_contracts` 为 Agent 和工作台共享的手写 JSON 契约，不引入 Flutter 或 `dart:io`。
- `agent` 管理 Genkit、DeepSeek、版本校验、记忆重建和本地持久化；`viewer` 管理 Flutter 界面与本地服务网关。供应商密钥仅在 Agent 环境中读取。
- 仓库根目录：`flutter pub get`、`dart analyze`、`dart test agent/test packages/novel_contracts/test`。
- 工作台目录：`flutter test --no-pub`、`flutter build web --no-pub`。
