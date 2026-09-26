# 离线语义补全评测

此目录保存离线评测与资源准备工具。用户已选择 E5-small 进入本地 Android 原型接入阶段，代码接入边界及待验收项见 [E5_DEPLOYMENT.md](E5_DEPLOYMENT.md)。语义候选由补全编排器异步补充，`FastTagService` 保留字面搜索职责；历史评测分数不等于当前应用已通过运行验收。

## 范围与数据边界

- 完整候选为当前 `tag_catalog.db` 的普通类别 0、7，不包含作者、作品、角色。
- 编码材料仅使用既有英文词条、ffdkj 译文及内置翻译优先级；不调用翻译接口，不生成释义，不新增词条别名。
- `cases.json` 是测试查询和人工指定的期望标签，不进入候选语料，不用于训练、别名查询或运行时规则。
- 中英日文、否定/肯定、部分/全部与背景信息干扰分别评测。等义的跨站词条使用 `alternatives`，不把同义命中误计成漏召回。
- 数据库以只读模式打开。实验模型、依赖和向量缓存留在 `tool/.tmp/`；仅经 manifest 锁定的 E5 部署资源复制到 `assets/semantic_search/` 随本地 APK 打包，大文件不提交到普通 Git。

## 模型与复现

首批实验使用官方 MIT 许可的多语言 E5。采用官方要求的 `query: ` / `passage: ` 前缀、attention mask 均值池化和 L2 归一化。短词条评测将最大输入长度限制为 128；CPU 默认 2 线程，可用 `--threads 4` 调整，单批 32 条。加载前校验 `models.json` 中的模型/分词器 SHA-256 及维度。

| 模型 | 固定 revision | 维度 |
|---|---|---|
| `intfloat/multilingual-e5-small` | `614241f622f53c4eeff9890bdc4f31cfecc418b3` | 384 |
| `intfloat/multilingual-e5-base` | `d128750597153bb5987e10b1c3493a34e5a4502a` | 768 |

上游文件为 `onnx/model_qint8_avx512_vnni.onnx`（本地命名 `model.onnx`）和 `tokenizer.json`。这是 Windows CPU 质量基线产物，**不能据此宣称已适配 Android ARM 或骁龙 NPU**。正式手机部署需选择/导出 ARM 适用量化、重跑质量评测并验证运行时后端。

评测环境：Python 3.12、`onnxruntime==1.30.0`、`tokenizers==0.23.2`、`numpy==2.4.6`。使用项目临时目录中的隔离环境，不修改 Flutter 依赖。脚本不自动下载模型，也不加载上游 Python 自定义代码。

```powershell
# 项目根目录；外层需加总时限（例如 subprocess.run(timeout=570)）。
& ./tool/.tmp/semantic-search/venv/Scripts/python.exe -B -u tool/semantic_search/evaluate.py --timeout 540
& ./tool/.tmp/semantic-search/venv/Scripts/python.exe -B -u tool/semantic_search/evaluate.py --directory tool/.tmp/semantic-search/e5-base --dimensions 768 --threads 4 --timeout 540
& ./tool/.tmp/semantic-search/venv/Scripts/python.exe -B -m unittest discover -s tool/semantic_search -p test_evaluate.py
```

报告记录数据、模型、分词器、语料及样例哈希，缓存键包含数据哈希与编码协议。修改测试查询不需要重新编码候选。建索引按文本长度分批，完成后还原 canonical tag 行序；每批保存临时向量与断点，超时后可续算。语料编码每批检查时限，外层 watchdog 负责终止卡在原生推理中的进程。`cache_reused` 区分完整缓存命中和实际建索引，不能拿缓存命中的总耗时当建索引耗时。

## 判定与后续接入

当前仅为开发集：目标进入前 20 的比例至少 80%，且不得出现指定相反/冲突词条领先目标，才通过初筛。不是概率校准、生产验收或未见样本上的准确率保证。

后续仍需独立留出集、无相关词条查询、字面精确结果优先、去重、分类限制、低置信度弃答与否定关系重排测试。不能把向量相似度当作置信概率，也不能用“出现不字就删掉所有肯定标签”的规则处理否定作用域。

目标手机为骁龙 8 Gen 3、16GB RAM、1TB 存储，质量优先。电脑上的 `query_ms` 包含编码、点积及全量排序，不是手机延迟。接入前必须测 Android 冷启动/预热、P50/P95、峰值内存、连续输入取消及发热；不要默认 CPU ONNX 会自动调用 NPU。QNN/HTP 需要独立运行时和模型兼容性验证。

官方参考：[E5-small](https://huggingface.co/intfloat/multilingual-e5-small)、[E5-base](https://huggingface.co/intfloat/multilingual-e5-base)、[ONNX Runtime QNN](https://onnxruntime.ai/docs/execution-providers/QNN-ExecutionProvider.html)。
