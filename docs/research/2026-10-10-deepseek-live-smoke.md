# DeepSeek 真实接口烟测

日期：2026-10-10。状态：真实接口联通与三项应用操作通过；不是模型选型或写作质量评测。

## 样例与配置

使用本会话中由助手创建的固定虚构样例“雨夜来信”，对应 [demo.dart](../../packages/novel_contracts/lib/src/demo.dart)：两章正文、作者设定、未来计划和自写参考素材。试验前确认独立数据目录与该 fixture 完全一致；未使用用户的其他稿件或生产数据。

服务为 Dart Genkit Flow，官方 `genkit_openai` 插件访问 DeepSeek Chat Completions。Genkit、genkit_openai 与 schemantic 均为 1.0.0。模型名称 `deepseek-flash`，非流式 JSON 输出，`maxTokens: 8192`，`reasoningEffort: none`，应用层截止时间 90 秒。接口依据见 [插件说明](https://pub.dev/packages/genkit_openai#deepseek)与 [DeepSeek API](https://api-docs.deepseek.com/)。供应商别名对应的底层模型版本由供应商控制，本次未获得不可变版本 ID。

## 结果

| 操作 | 本地 HTTP 往返耗时 | 观察 |
| --- | --- | --- |
| 下一章起草 | 7.25 秒 | 返回《第三章 · 邮戳的缺口》，正文 1445 字符（含标点和空白），其中 U+4E00–U+9FFF 汉字 1155 个；提案为 pending，原两章未改变 |
| 记忆重建 | 1.54 秒 | 返回 7 条事实，绑定 seed-1 与 seed-2；每条原文证据均通过宿主校验 |
| 选段改写 | 0.83 秒 | 返回含糊线索、没有姓名且林舟仍未知凶手的替换文本；宿主组装候选后逐字核对选段外保留，原两章未改变 |

写作调用 usage：输入 893、输出 1044、合计 1937 token。改写调用 usage：输入 1122、输出 50、合计 1172 token。记忆接口当前未向操作结果传递 usage，不能从这两项 usage 推断三次调用的总费用。

这次只验证密钥可用、真实插件接入、结构化结果能进入提案／记忆流程，以及正文未被自动覆盖。没有进行多次采样、人工盲评、自动评委评分、跨章连续性评测或质量比较；不据此宣称 DeepSeek 的整体中文小说能力已通过验收。

## 可复核记录

- [写作记录](runs/2026-10-10-deepseek-smoke/write.json)：应用配置、系统提示词、上下文、作者要求、模型正文与 usage。
- [记忆记录](runs/2026-10-10-deepseek-smoke/memory.json)：输入章节、提取任务源码位置和事实／证据输出。
- [改写记录](runs/2026-10-10-deepseek-smoke/edit.json)：原选段、上下文、要求、宿主组装后的候选正文和 usage。

记录为应用层输入与解析后的模型结果，不是完整供应商 HTTP 报文。评分结果为“未进行”。试验数据含虚构样例与模型生成文本，不含供应商密钥或本地会话令牌；本地密钥与运行状态留在 Git 忽略的 `.local/`。
