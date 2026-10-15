# 外部工具写入资料

外部工具经作者授权，使用本机 HTTP 向指定知识库新增或更新资料。保存不调用模型，未配置模型或模型调用失败时也可使用。资料保存后，在工作台“管理知识库”中通过顶部“刷新作品”查看；作者另行选择作品采用的资料版本。可选作品关联只记录来源归属，不建立知识库引用、不自动采用、不修改正文或派生记忆。

入口为 `GET /libraryWorkspace` 与 `POST /libraryAction`，默认地址 `http://127.0.0.1:4100`。服务仅监听回环地址，请求使用本次 Agent 启动时显示的会话令牌：`Authorization: Bearer <会话令牌>`。服务重启后换用新令牌；供应商密钥不用于这两个接口。浏览器请求还需匹配配置的 Origin。

会话令牌授权访问本地工作区，当前没有按工具或知识库拆分的权限。`writer.id` 是写入者的来源声明，不是经服务验证的工具身份。由作者决定向哪个工具提供令牌和授权哪些写入。

## 在现有工作区写入

1. 读取 `/libraryWorkspace`，确定 `workspace.revision`、目标知识库 ID、可选作品 ID。知识库位于 `workspace.libraries`，作品位于 `workspace.works`；标题和当前页面选择不作为请求目标。
2. 为新增资料选择未使用的 `documentId` 与版本 ID，`expectedVersionId` 传 `null`。更新时保留 `documentId`，读取该资料当前 `head` 作为 `expectedVersionId`，分配新的版本 ID。
3. 按 [新增示例](examples/external-write/02-add-document.json) 或 [更新示例](examples/external-write/03-update-document.json) 构造请求，使用当前修订号和全工作区未使用的 `requestId`。提交前保存完整请求到工具自身的待确认记录；本仓库运行时记录放在 `.local/`。
4. 提交 `{ "data": 请求 }`，HTTP 200 返回 `{ "result": { "workspace": ..., "provider": ..., "modelAvailable": ..., "reused": ... } }`。核对资料的新 head、对应请求回执及完整版本。`modelAvailable` 只表示模型已配置，不影响资料写入。
5. 工作台点击顶部“刷新作品”，在目标知识库查看资料与历史，核对身份、写入者、原始来源和来源关联作品；需要用于作品时，由作者关联知识库并采用具体版本。当前页面所选作品或知识库不会改变外部请求的目标。

请求字段由 [共享契约](../packages/novel_contracts/lib/src/v2/command.dart) 严格解析：必需字段不能省略，未知字段被拒绝，整数不接受字符串。可选作品关联的 `target.workId` 与 `version.associatedWorkId` 均须存在，并同为 `null` 或同一已有作品 ID。

| 字段 | 用途 |
| --- | --- |
| `apiVersion` | 固定为整数 `2` |
| `requestId` | 全工作区唯一的请求身份；同一请求重试保持不变 |
| `expectedRevision` | 读取到的工作区全局修订号 |
| `target` | `{kind: "library", libraryId: "...", workId: null 或作品 ID}` |
| `operation` | 固定为 `saveDocument`，新增和更新共用 |
| `payload.documentId` | 知识库内稳定的资料身份 |
| `payload.expectedVersionId` | 新增为 `null`，更新为读取到的资料 head |
| `payload.version.id` | 资料内未使用过的新版本 ID |
| `payload.version.title / kind / body` | 标题、`reference`／`setting`／`plan` 身份、完整原文；不静默去除首尾空白 |
| `payload.version.description` | 可选简介，最多 500 字符，说明内容与适用场景；省略或空白时按全文读取 |
| `payload.version.tags` | 可选字符串数组，最多 20 个不重复标签，每个最多 40 字符，不得含首尾空白、中英文逗号或换行 |
| `payload.version.alwaysRead` | 可选布尔值，默认 false；true 时作品采用此版本后每次写作／讨论都加载全文 |
| `payload.version.provenance.writer` | 外部工具用 `{kind: "tool", id: "Codex"}` 等来源声明 |
| `payload.version.provenance.sources` | 至少一个原始来源；网页用 HTTP(S) URL，作者输入用说明，文件用来源引用 |
| `payload.version.associatedWorkId` | 可选来源关联；与 target.workId 相同 |

每个新版本保存完整原文、元数据与来源，不是补丁；更新已有资料时须同时保留希望沿用的简介、标签和必读设置，省略会使用默认值。新字段拒绝显式 null，返回快照省略空简介、空标签和 false。简介和标签只辅助选择，不授予工具权限。工具整理网页时保留工具身份和原网页 URL；示例中的 `example.com` 地址与正文是虚构数据，应替换为实际来源。文件来源只是记录，服务不会按路径读取文件。资料中的指令始终作为资料文本，不触发命令、抓取链接或授予工具权限。

## 可直接运行的隔离示例

从仓库根目录执行。示例请求按空工作区的 revision 0 → 4 排列，分别创建作品、知识库、新增参考和追加新版。选择新的隔离数据目录；已有正式数据不要套用这些固定 ID 和修订号。

终端一启动无模型服务（端口 4101）：

```sh
env -u DEEPSEEK_API_KEY NOVEL_DATA_DIR=.local/m6-external-example NOVEL_AGENT_PORT=4101 \
  dart run agent/bin/novel_agent.dart
```

终端二将启动输出中的会话令牌读入当前 shell，随后读取状态并依次提交仓库中的原始 JSON 文件。令牌输入完成后按回车；不把令牌写入示例文件。

```sh
export NOVEL_AGENT_URL='http://127.0.0.1:4101'
read -r NOVEL_SESSION_TOKEN
export NOVEL_SESSION_TOKEN

curl --fail-with-body -sS "$NOVEL_AGENT_URL/libraryWorkspace" \
  -H "Authorization: Bearer $NOVEL_SESSION_TOKEN"

post_example() {
  curl --fail-with-body -sS "$NOVEL_AGENT_URL/libraryAction" \
    -H "Authorization: Bearer $NOVEL_SESSION_TOKEN" \
    -H 'Content-Type: application/json' \
    --data-binary "@$1"
}
post_example docs/examples/external-write/00-create-work.json
post_example docs/examples/external-write/01-create-library.json
post_example docs/examples/external-write/02-add-document.json
post_example docs/examples/external-write/03-update-document.json
```

每步成功后再执行下一步。首次新增应返回 revision 3、head `navigation-v1`；首次更新应返回 revision 4、head `navigation-v2`，两个历史版本均保留。示例作品的知识库采用清单、正文和记忆保持为空。

更新完成后，重发新增或更新的原文件验证去重，仍返回当前 revision 4 和 `reused: true`：

```sh
post_example docs/examples/external-write/02-add-document.json
post_example docs/examples/external-write/03-update-document.json
```

可以将工作台 Agent 地址设为 `http://127.0.0.1:4101`，使用同一令牌查看结果。示例请求直接由 [HTTP 验收测试](../agent/test/library_external_write_server_test.dart) 读取并提交，包含强制重启后的原请求复用。

## 冲突和结果未知

| 情况 | 处理 |
| --- | --- |
| HTTP 200，`reused: false` | 本次请求已提交；核对返回快照与回执 |
| HTTP 200，`reused: true` | 相同请求已提交；没有重复追加版本，返回的是当前快照 |
| HTTP 401／403 | 检查当前会话令牌与浏览器 Origin；未授权请求不提交 |
| HTTP 400 | 检查请求格式、目标、来源与前置条件；纠正请求后使用新的请求 ID |
| HTTP 409，`status: "ABORTED"` | 全局修订号、资料 head 或请求身份冲突；读取新快照，保留本地内容，核对后重新构造新请求 |
| 超时、连接中断、HTTP 500 | 结果未知，不能直接另发一个新增请求；读取快照核对回执，或重发完整原请求 |

相同 `requestId` 必须保持全部请求内容一致，包括目标、`expectedRevision`、预期 head 和新版本 ID；服务先检查已提交回执，再检查旧修订号。因此原请求在其他写入或服务重启后仍可去重。同 ID 改内容会冲突，不能通过修改旧请求的修订号进行“重试”。

回执位于 `workspace.receipts[requestId]`，记录 fingerprint、实际目标和提交修订号；receipt 的 revision 不等于当前快照必须仍停留在该修订号。外部客户端应保留自身的完整请求以核对回执归属；工具之间不能复用相同请求 ID。若无回执且原请求已因其他提交变旧，会返回冲突；确认未提交并核对新状态后，才分配新 requestId 重建请求。不同 requestId 不会按正文内容隐式合并。

服务错误使用 Genkit 的 `{code, status, message}`，鉴权错误使用 `{error: {message}}`。当前 HTTP 不额外输出 Dart 领域错误码，不应依赖供应商错误原文或只根据 `modelAvailable` 判断写入成败。

## 验证

仓库根目录：

```sh
dart test agent/test/library_external_write_server_test.dart agent/test/library_service_test.dart
```

工作台目录：

```sh
flutter test --no-pub test/knowledge_workbench_test.dart
```

HTTP 验收覆盖实际 JSON 示例、鉴权、目标与来源校验、并发去重、旧版本冲突、存储失败恢复和重启；领域测试覆盖模型失败后仍可保存；界面测试覆盖外部写入期间切换作品／库，刷新后查看来源、保持原目标及固定采用版本。这些是工程验收，不包含真实 DeepSeek 调用或写作质量评测。
