# 中文长篇小说 Agent 模型选型

调研日期与价格快照日期：2026-10-10。状态：候选方案，尚未完成小说样稿实测。

首轮模型调研面向中文长篇与网文连载，关注持续写章节、人物和伏笔一致性、改写服从度、工具调用与成本。建议先以 Qwen3.7-Plus 验证写作流程，并以 DeepSeek V4-Pro、Claude Sonnet 5.5 对照正文质量。最终模型仍需通过固定中文样稿、连续章节和人工偏好测试确定。

产品范围、作者接受提案和正文与记忆一致性的要求以 [SPEC.md](../../SPEC.md) 为准。模型候选及批量连写试验不改变作者主导的产品方向。

## 模型候选与官方价格快照

以下是每百万 token 的普通输入与输出价格。人民币和美元分别标明；不含缓存、工具、税费或活动优惠。不同模型的 tokenizer 不同，实际成稿成本需要读取 API usage，不能用相同汉字数直接推断 token 数。

| 模型 | 输入价格 | 输出价格 | 建议测试的用途 | 来源 |
| --- | --- | --- | --- | --- |
| Qwen3.7-Plus | ¥2，输入不超过 256K | ¥8，输入不超过 256K | 第一版主模型，覆盖大纲、正文、改写和审稿 | [模型文档](https://help.aliyun.com/zh/model-studio/qwen3-7-plus) |
| DeepSeek V4-Pro | $0.66 谷时，$1.32 峰时 | $1.98 谷时，$3.96 峰时 | 主模型对照、剧情规划与审稿候选 | [模型与价格](https://api-docs.deepseek.com/quick_start/pricing/) |
| DeepSeek V4.1-Flash | $0.15 谷时，$0.30 峰时 | $0.60 谷时，$1.20 峰时 | 章节摘要、事实提取及低成本草稿 | [模型与价格](https://api-docs.deepseek.com/quick_start/pricing/) |
| Claude Sonnet 5.5 | $2 | $10 | 正文与改写的重点盲测候选 | [模型总览](https://platform.claude.com/docs/en/models/overview)、[价格](https://platform.claude.com/docs/en/about-claude/pricing) |
| Claude Opus 5.5 | $4 | $20 | 关键章节和全卷审稿的升级候选 | [模型总览](https://platform.claude.com/docs/en/models/overview)、[价格](https://platform.claude.com/docs/en/about-claude/pricing) |
| GPT-6.1 Sol | $2，输入不超过 272K | $10，输入不超过 272K | Agent 调度、复杂规划和设定检查候选 | [模型文档](https://developers.openai.com/api/docs/models/gpt-6.1-sol)、[价格](https://developers.openai.com/api/docs/pricing) |
| Gemini 3.8 Flash | $0.75，至 2026-12-31 | $3.75，至 2026-12-31 | 前文处理、摘要、批量审稿候选 | [模型文档](https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash)、[价格](https://ai.google.dev/gemini-api/docs/pricing) |

Qwen 价格页当时对部分别名版本标注限时八折；表中采用原价。输入超过 256K 后，Qwen3.7-Plus 的输入和输出原价分别为 ¥6 与 ¥24。[价格说明](https://help.aliyun.com/zh/model-studio/model-pricing)

DeepSeek 表中区间对应谷时和峰时，当前 Flash 的 API 名称是 `deepseek-flash`，对应 DeepSeek-V4.1-Flash。峰时与公共假期条件以官方价格页为准。GPT-6.1 Sol 的输入超过 272K 后，输入与输出费率分别变为 $4 和 $15。Gemini 官方已公告从 2027-01-01 起，上表普通输入和输出价格分别变为 $1.50 和 $7.50。

## 功能与接入考虑

- Qwen3.7-Plus 支持约百万 token 上下文、Function Calling、结构化输出、前缀续写、缓存及部分地域的批量推理。它是功能与成本较完整的起点，不代表中文文笔已胜过其他候选。
- DeepSeek 的两个候选均支持百万上下文、思考与非思考模式、工具调用和 JSON 输出。Flash 的低价适合测试记忆整理，但事实提取准确率仍需单独验证。
- Claude Sonnet 5.5 与 Opus 5.5 支持百万上下文和工具使用。是否改善对白、情绪、节奏与改写，交由小说盲测判断；是否使用 Opus，取决于相对 Sonnet 的质量增益与额外成本。
- GPT-6.1 Sol 支持约百万上下文、结构化输出、检索与函数调用；工具调用需使用 Responses API。不能仅因其他服务支持 OpenAI 兼容格式，就假设工具与推理参数完全一致。
- Gemini 3.8 Flash 支持约百万输入 token。其价格快照适合初期预算比较，长期预算需采用已公告的后续价格。

功能依据见上表的官方模型文档。模型接入条件、价格和限制在实际选型或升级时重新核对。

## 建议的任务分工

第一版可用同一模型的多次调用完成工作流，待固定样例跑通后再替换某个环节。任务角色不要求第一版实现复杂自主多 Agent。

| 工作 | 初期安排 | 后续对照候选 |
| --- | --- | --- |
| 世界观、分卷大纲、章节目标 | Qwen3.7-Plus | DeepSeek V4-Pro、GPT-6.1 Sol |
| 正文、对白、局部改写 | Qwen3.7-Plus | Claude Sonnet 5.5 |
| 章节摘要、人物状态与事件提取 | 先沿用主模型 | DeepSeek Flash |
| 时间线、设定冲突与伏笔检查 | 主模型单独审稿一轮 | 更强模型检查关键章节 |

作者接受后的正文事实需要保存在独立、带来源的记忆中；未来大纲、未接受草稿和角色猜测不能直接成为已确认事实。记忆的接受、失效与恢复机制由项目定义维护。

写作上下文重点包含人物状态、角色已知信息、事件时间线、伏笔状态，以及视角、人物语言习惯和题材约束。每章装入相关记录与近期正文，减少仅靠反复读取全部前文来维持故事状态的依赖。

## 调用成本示例

假设写 100 章，每章仅一次调用，输入 20,000 token、计费输出 8,000 token。总输入为 200 万 token，总输出为 80 万 token。以下按原价计算，不含其他调用或缓存；8,000 token 不等于 8,000 汉字。

| 模型 | 示例费用 | 计算 |
| --- | --- | --- |
| Qwen3.7-Plus | ¥10.40 | 2 × ¥2 + 0.8 × ¥8 |
| DeepSeek V4-Pro 谷时 | $2.904，约 $2.90 | 2 × $0.66 + 0.8 × $1.98 |
| DeepSeek V4-Pro 峰时 | $5.808，约 $5.81 | 2 × $1.32 + 0.8 × $3.96 |
| Claude Sonnet 5.5 | $12 | 2 × $2 + 0.8 × $10 |

实际预算还包括大纲、审稿、重写、失败与重试、计费思考输出、缓存写入及读取。跨模型比较应记录达到同一成稿要求的总费用与人工修改时间。

## 选型需要解决的问题

先比较 Qwen3.7-Plus、DeepSeek V4-Pro、Claude Sonnet 5.5，并使用相同题材、设定与可比的上下文。

1. 正文与对白是否吸引目标题材读者，是否有持续推进的冲突与章末期待。
2. 角色知情、伤势、道具和能力是否保持一致，人物变化是否有合理过程。
3. 指定伏笔能否按阶段自然回收。
4. 局部修改是否服从作者要求，并保留不应改变的内容。
5. 每章可用成本、废稿、重试及人工修改时间是否符合预算。

测试标准、评委校准和首轮样例规模见 [中文长篇小说写作能力评测](2026-10-10-writing-evaluation.md)。最终选择优先依据可用成稿、读者偏好和修改成本，不以通用推理或编码榜单替代小说测试。
