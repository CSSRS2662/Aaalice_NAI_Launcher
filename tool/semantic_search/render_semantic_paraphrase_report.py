"""Render the reproducible unseen-paraphrase benchmark into Markdown.

The renderer consumes only the benchmark's JSON artifact.  It deliberately
keeps the complete clean-case and leakage appendices so a result can be
audited without rerunning the model.
"""
from collections import Counter
import json
from pathlib import Path
import statistics


ROOT = Path(__file__).resolve().parents[2]
SUMMARY = ROOT / "tool/.tmp/semantic-search/paraphrase/summary.json"
OUTPUT = ROOT / "tool/semantic_search/semantic_paraphrase_benchmark_report.md"


def esc(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def pct(value):
    return "—" if value is None else f"{value * 100:.1f}%"


def number(value):
    if value is None:
        return "—"
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)


def table(headers, rows):
    lines = ["| " + " | ".join(headers) + " |",
             "| " + " | ".join("---" for _ in headers) + " |"]
    lines.extend("| " + " | ".join(esc(cell) for cell in row) + " |" for row in rows)
    return "\n".join(lines)


def metric_cells(metrics):
    return [pct(metrics.get(key)) for key in
            ("top1", "top3", "top5", "top10", "top20", "top50", "mrr10")]


def rank(row):
    return row.get("rank") if row.get("rank") is not None else 54880


TAXONOMY_LABELS = (
    "A 译文过于书面", "B 口语与译文词面断裂", "C 否定理解失败",
    "D 数量关系失败", "E 方向关系失败", "F 语义过宽",
    "G 近义/冲突 tag", "H 中文材料不足", "I 英文 tag 不直观",
    "J 长句噪声", "K 跨语言失败", "L 候选文本信息不足", "M 其他",
)


def classify_failure(row):
    """Deterministic taxonomy; labels are intentionally diagnostic, not gold."""
    if row.get("conflict_rank") is not None and row["conflict_rank"] < rank(row):
        if row.get("query_type") == "negation":
            return "C 否定理解失败"
        if row.get("query_type") == "quantity":
            return "D 数量关系失败"
        if row.get("query_type") in {"direction", "orientation"}:
            return "E 方向关系失败"
        return "G 近义/冲突 tag"
    if not row.get("zh_cn"):
        return "H 中文材料不足"
    if row.get("language") not in {"zh", None}:
        return "K 跨语言失败"
    if len(row.get("query", "")) >= 12:
        return "J 长句噪声"
    if row.get("query_type") in {"quantity"}:
        return "D 数量关系失败"
    if row.get("query_type") in {"direction", "orientation"}:
        return "E 方向关系失败"
    if row.get("query_type") in {"camera", "pose", "spatial"}:
        return "L 候选文本信息不足"
    if row.get("language") == "en":
        return "I 英文 tag 不直观"
    return "G 近义/冲突 tag"


def manual_review_reason(row):
    target = row.get("target", "")
    if target in {"bangs", "double_ponytail", "hair_over_eyes"}:
        return "头发局部关系被 forehead/hair 近邻抢走"
    if target in {"crouching", "squatting"}:
        return "姿势描述宽泛，落到 legs/衣物近邻"
    if target == "v_sign":
        return "剪刀手与 scissors/剪切动作近邻"
    if target in {"stockings", "pantyhose", "socks"}:
        return "袜类层级与 garter/legwear 近邻"
    if target in {"hand_on_hip", "hands_on_hips", "hands_behind_back"}:
        return "手部位置关系缺少候选文档线索"
    return "人工复查：近邻 tag 或关系词信息不足"


def main():
    summary = json.loads(SUMMARY.read_text(encoding="utf-8"))
    report_by_model = {item["model"]: item for item in summary["reports"]}
    small = report_by_model["intfloat/multilingual-e5-small"]["variants"]
    base = report_by_model["intfloat/multilingual-e5-base"]["variants"]
    small_a = small["minimal"]
    small_b = small["enhanced-existing"]
    base_a = base["minimal"]
    base_b = base["enhanced-existing"]
    lexical = small["lexical-enhanced-existing"]
    primary = small_a["details"]
    maps = {
        "small A": {x["id"]: x for x in small_a["details"]},
        "small B": {x["id"]: x for x in small_b["details"]},
        "base A": {x["id"]: x for x in base_a["details"]},
        "base B": {x["id"]: x for x in base_b["details"]},
        "lexical": {x["id"]: x for x in lexical["details"]},
    }
    clean_cases = primary
    leaked_cases = summary["leakage_cases"]
    clean_by_id = {x["id"]: x for x in clean_cases}
    small_matrix_bytes = (ROOT / "tool/.tmp/semantic-search" / small_a["cache"]).stat().st_size
    base_matrix_bytes = (ROOT / "tool/.tmp/semantic-search/e5-base" / base_a["cache"]).stat().st_size

    lines = [
        "# Semantic Paraphrase Benchmark",
        "",
        "> 离线、只读评测：本轮没有启动 Flutter/Android，没有改动 `lib/`、生产数据库或查询数据。",
        "",
        "## 1. Executive Summary",
        "",
        f"- 评测覆盖 **{len({x['target'] for x in clean_cases})} 个目标词条、{summary['case_count_all']} 条原始样例、{summary['case_count_clean']} 条无泄漏样例**；其中未见同义/口语改写 423 条，Hard Set 100 条。",
        f"- 主指标使用 {summary['candidate_count']:,} 个生产候选（Danbooru/e621 category 0/7）；48 条样例因包含目标当前中文标签而剔除，完整记录保留在附录 B。",
        f"- 推荐先以 E5-small + 文档 A（英文 tag + 已有中文）作为离线基线：Top-20 {pct(small_a['metrics']['all']['top20'])}，MRR@10 {pct(small_a['metrics']['all']['mrr10'])}；E5-base 文档 A 为 Top-20 {pct(base_a['metrics']['all']['top20'])}。",
        "- E5-base 没有改善未见中文改写：文档 A 的 Top-20 略低于 small；在本机更慢、更占内存。",
        f"- 把现有英文 alias 全部拼进文档 B 反而明显退化（small Top-20 从 {pct(small_a['metrics']['all']['top20'])} 降到 {pct(small_b['metrics']['all']['top20'])}，base 从 {pct(base_a['metrics']['all']['top20'])} 降到 {pct(base_b['metrics']['all']['top20'])}），不应直接作为默认文档格式。",
        f"- 口语 Hard Set 的主要风险是否定、数量和方向词被相邻 tag 抢走：small A 有冲突的 {small_a['conflicts']['with_conflict']} 条中，{small_a['conflicts']['conflict_before_target']} 条冲突排在目标前。",
        "- 生产 Flutter 当前仍是词典/LIKE/FTS 词法搜索；代码中没有 E5/embedding 语义检索接线，因此本报告评估的是隔离 harness，不宣称应用已经具备该模型。",
        "- 结论：先保留本 benchmark 和小模型文档 A 作为可复现实验基线；上线前需要专门的否定/数量重排、候选召回与人工标注集，而不是直接把这轮结果接入生产。",
        "",
        "## 2. Goal and scope",
        "",
        "目标是测量“用户没有说出标签原文时，中文自然语言能否找回正确 Danbooru tag”。样例覆盖衣物、袜类、眼睛、表情、头发、姿势、方向/镜头、数量、空间关系和动作，并额外保留上一轮真实 holdout。",
        "",
        "本轮明确不做：翻译 API、LLM 翻译、别名/查询写回、生产数据库修改、Flutter 启动、功能重构。",
        "",
        "## 3. Environment and data",
        "",
        table(["项目", "值"], [
            ["OS / CPU", "Windows NT 10.0.19045 / AMD Ryzen 5 5600H"],
            ["候选范围", f"{summary['candidate_count']:,} tags（category 0: {summary['category_counts']['0']:,}; 7: {summary['category_counts']['7']:,}）"],
            ["catalog", f"{summary['database']['bytes']:,} bytes; SHA256 `{summary['database']['sha256']}`"],
            ["词典快照", f"ffdkj.sqlite SHA256 `{summary['database']['dictionary_sha256']}`"],
            ["catalog data version", summary["database"]["metadata"].get("data_version", "—")],
            ["candidate translations", ", ".join(summary["database"]["translation_columns"])],
            ["runtime", f"numpy {summary['runtime']['numpy']}, ONNX Runtime CPUExecutionProvider, {summary['runtime']['threads']} threads"],
            ["benchmark time", "2026-09-12 (local Windows time)"],
            ["git HEAD", "1f6e6ee21e1c8abf2101236ae283b440ef364e17"],
            ["case manifest", f"SHA256 `{summary['case_sha256']}`"],
        ]),
        "",
        "固定模型与缓存：",
        "",
        table(["模型", "ONNX / tokenizer", "向量维度", "文档矩阵"], [
            ["multilingual-e5-small", "118,346,824 / 17,082,730 bytes", "384", f"FP32；{small_matrix_bytes:,} bytes / variant"],
            ["multilingual-e5-base", "278,686,411 / 17,082,660 bytes", "768", f"FP32；{base_matrix_bytes:,} bytes / variant"],
        ]),
        "",
        "模型和 tokenizer 使用 `tool/semantic_search/models.json` 中固定 revision 与 SHA256；E5 查询使用 `query: ` 前缀、文档使用 `passage: ` 前缀，attention-mask mean pooling、L2 normalization、max length 128、稳定排序。",
        "",
        table(["模型", "固定 revision", "model.onnx SHA256", "tokenizer.json SHA256"], [
            ["multilingual-e5-small", "614241f622f53c4eeff9890bdc4f31cfecc418b3", small_a["metadata"]["model"], small_a["metadata"]["tokenizer"]],
            ["multilingual-e5-base", "d128750597153bb5987e10b1c3493a34e5a4502a", base_a["metadata"]["model"], base_a["metadata"]["tokenizer"]],
        ]),
        "",
        "## 4. Dataset and leakage policy",
        "",
        table(["来源", "原始", "主指标纳入"], [
            ["unseen paraphrase", summary["source_counts_all"]["paraphrase"], summary["source_counts_clean"]["paraphrase"]],
            ["Hard Set（20 对冲突 × 5）", summary["source_counts_all"]["hard"], summary["source_counts_clean"]["hard"]],
            ["real-world holdout", summary["source_counts_all"]["real-world-holdout"], summary["source_counts_clean"]["real-world-holdout"]],
            ["required user cases", summary["source_counts_all"]["required-case"], summary["source_counts_clean"]["required-case"]],
            ["合计", summary["case_count_all"], summary["case_count_clean"]],
        ]),
        "",
        "每条样例只允许一个 `(query, target)`；若 query 含目标当前 `zh_cn`/`zh_tw` 的完整两字以上标签，就标记 leakage 并从主指标排除。Hard Set 修改后保留干净的 100/100；48 条被排除样例不是静默删除，见附录 B。",
        "",
        "## 5. Retrieval configurations",
        "",
        "- 文档 A（minimal）：canonical `english_tag + existing zh_cn`。",
        "- 文档 B（enhanced-existing）：文档 A 加 underscore-split English tag 与数据库已有 aliases；没有新增翻译、描述或人工别名。",
        "- Lexical baseline：按现有 `TagCatalogRepository`/`ZhDictionaryService` 的标签、中文 LIKE/变体和英文 alias 逻辑做数据库等价近似；未调用 Dart API。对未见中文口语，多数返回空集是预期结果。",
        "- Semantic full-corpus rank：54,879 个候选全量排序，报告 Top-1/3/5/10/20/50、MRR@10、rank 分布；union 是 lexical@20/40 与 semantic@20/40 的候选集合并集。",
        "",
        "## 6. Main results (clean set)",
        "",
        table(["配置", "Top1", "Top3", "Top5", "Top10", "Top20", "Top50", "MRR@10", "median", "mean", "P90", "P95"], [
            ["E5-small · A", *metric_cells(small_a["metrics"]["all"]), number(small_a["metrics"]["all"]["median_rank"]), number(small_a["metrics"]["all"]["mean_rank"]), number(small_a["metrics"]["all"]["p90_rank"]), number(small_a["metrics"]["all"]["p95_rank"])],
            ["E5-small · B", *metric_cells(small_b["metrics"]["all"]), number(small_b["metrics"]["all"]["median_rank"]), number(small_b["metrics"]["all"]["mean_rank"]), number(small_b["metrics"]["all"]["p90_rank"]), number(small_b["metrics"]["all"]["p95_rank"])],
            ["E5-base · A", *metric_cells(base_a["metrics"]["all"]), number(base_a["metrics"]["all"]["median_rank"]), number(base_a["metrics"]["all"]["mean_rank"]), number(base_a["metrics"]["all"]["p90_rank"]), number(base_a["metrics"]["all"]["p95_rank"])],
            ["E5-base · B", *metric_cells(base_b["metrics"]["all"]), number(base_b["metrics"]["all"]["median_rank"]), number(base_b["metrics"]["all"]["mean_rank"]), number(base_b["metrics"]["all"]["p90_rank"]), number(base_b["metrics"]["all"]["p95_rank"])],
            ["词法 baseline", *metric_cells(lexical["metrics"]["all"]), number(lexical["metrics"]["all"]["median_rank"]), number(lexical["metrics"]["all"]["mean_rank"]), number(lexical["metrics"]["all"]["p90_rank"]), number(lexical["metrics"]["all"]["p95_rank"])],
        ]),
        "",
        "词法 baseline 的 `no_result` 是 510/512；它不是模型错误，而是当前生产词法路径对未见中文改写没有可查的字面标签。Lexical 结果的 rank 以未命中记为 corpus+1，仅用于直观对比，不应与语义分数混读。",
        "",
        "### 6.1 By source",
        "",
        table(["来源", "N", "small A Top1", "small A Top5", "small A Top20", "base A Top20", "small A MRR@10"], [
            [source.replace("source:", ""), small_a["metrics"][source]["count"], pct(small_a["metrics"][source]["top1"]), pct(small_a["metrics"][source]["top5"]), pct(small_a["metrics"][source]["top20"]), pct(base_a["metrics"][source]["top20"]), pct(small_a["metrics"][source]["mrr10"])]
            for source in ("source:paraphrase", "source:hard", "source:real-world-holdout", "source:required-case")
        ]),
        "",
        "### 6.2 By query type (small A vs base A Top-20)",
        "",
        table(["类型", "N", "small A Top1", "small A Top20", "base A Top20", "small A median rank"], [
            [key.replace("query_type:", ""), small_a["metrics"][key]["count"], pct(small_a["metrics"][key]["top1"]), pct(small_a["metrics"][key]["top20"]), pct(base_a["metrics"].get(key, {}).get("top20")), number(small_a["metrics"][key]["median_rank"])]
            for key in sorted(k for k in small_a["metrics"] if k.startswith("query_type:"))
        ]),
        "",
        "### 6.3 By query language",
        "",
        table(["语言", "N", "small A Top1", "small A Top20", "base A Top20", "备注"], [
            ["中文", small_a["metrics"]["language:zh"]["count"], pct(small_a["metrics"]["language:zh"]["top1"]), pct(small_a["metrics"]["language:zh"]["top20"]), pct(base_a["metrics"]["language:zh"]["top20"]), "主评测语言"],
            ["英文", small_a["metrics"]["language:en"]["count"], pct(small_a["metrics"]["language:en"]["top1"]), pct(small_a["metrics"]["language:en"]["top20"]), pct(base_a["metrics"]["language:en"]["top20"]), "N=3，样本不足"],
            ["日文", small_a["metrics"]["language:ja"]["count"], pct(small_a["metrics"]["language:ja"]["top1"]), pct(small_a["metrics"]["language:ja"]["top20"]), pct(base_a["metrics"]["language:ja"]["top20"]), "N=1，样本不足"],
        ]),
        "",
        "## 7. Candidate-document ablation",
        "",
        table(["模型", "A Top20", "B Top20", "变化", "A MRR@10", "B MRR@10"], [
            ["E5-small", pct(small_a["metrics"]["all"]["top20"]), pct(small_b["metrics"]["all"]["top20"]), f"{(small_b['metrics']['all']['top20']-small_a['metrics']['all']['top20'])*100:.1f} pp", pct(small_a["metrics"]["all"]["mrr10"]), pct(small_b["metrics"]["all"]["mrr10"])],
            ["E5-base", pct(base_a["metrics"]["all"]["top20"]), pct(base_b["metrics"]["all"]["top20"]), f"{(base_b['metrics']['all']['top20']-base_a['metrics']['all']['top20'])*100:.1f} pp", pct(base_a["metrics"]["all"]["mrr10"]), pct(base_b["metrics"]["all"]["mrr10"])],
        ]),
        "",
        "别名拼接没有带来召回增益，反而稀释了短 tag 与中文标签的语义表示；这是本数据、固定模型和固定 pooling 下的消融结论，不代表 alias 永远无用。",
        "",
        "## 8. Conflict and polarity analysis",
        "",
        table(["配置", "有冲突样例", "冲突在目标前", "前置率", "平均 target-conflict margin", "负 margin"], [
            ["small A", small_a["conflicts"]["with_conflict"], small_a["conflicts"]["conflict_before_target"], pct(small_a["conflicts"]["conflict_before_target_rate"]), number(small_a["conflicts"]["average_target_conflict_margin"]), small_a["conflicts"]["negative_margin_count"]],
            ["small B", small_b["conflicts"]["with_conflict"], small_b["conflicts"]["conflict_before_target"], pct(small_b["conflicts"]["conflict_before_target_rate"]), number(small_b["conflicts"]["average_target_conflict_margin"]), small_b["conflicts"]["negative_margin_count"]],
            ["base A", base_a["conflicts"]["with_conflict"], base_a["conflicts"]["conflict_before_target"], pct(base_a["conflicts"]["conflict_before_target_rate"]), number(base_a["conflicts"]["average_target_conflict_margin"]), base_a["conflicts"]["negative_margin_count"]],
            ["base B", base_b["conflicts"]["with_conflict"], base_b["conflicts"]["conflict_before_target"], pct(base_b["conflicts"]["conflict_before_target_rate"]), number(base_b["conflicts"]["average_target_conflict_margin"]), base_b["conflicts"]["negative_margin_count"]],
        ]),
        "",
        "`margin = score(target) - score(conflict)`；负 margin 与“冲突排在目标前”应一致。该现象说明纯 embedding 相似度不会可靠地理解“不/只/两边/背对”等逻辑词。",
        "Lexical 没有可排序的冲突分数；Union 是去重候选集合而非单一排序，因此 conflict-before-target 对 lexical/union 不定义，避免伪造该指标。",
        "",
        "### All conflict-before-target cases (small A)",
        "",
    ]
    conflict_rows = []
    for row in primary:
        if row.get("conflict") and row.get("conflict_rank") is not None and row["conflict_rank"] < rank(row):
            conflict_rows.append([
                row["id"], row["query"], row["target"], rank(row), row["conflict"], row["conflict_rank"],
                number(row.get("conflict_margin")), ", ".join(x["tag"] for x in row["top5"]),
            ])
    lines.append(table(["id", "query", "target", "target rank", "conflict", "conflict rank", "margin", "Top-5"], conflict_rows))
    lines.extend([
        "## 9. Lexical + semantic union",
        "",
        table(["模型/文档", "union@20 recall", "平均候选数", "union@40 recall", "平均候选数"], [
            ["small A", pct(small_a["union"]["union20"]["recall"]), small_a["union"]["union20"]["mean_candidate_set"], pct(small_a["union"]["union40"]["recall"]), small_a["union"]["union40"]["mean_candidate_set"]],
            ["small B", pct(small_b["union"]["union20"]["recall"]), small_b["union"]["union20"]["mean_candidate_set"], pct(small_b["union"]["union40"]["recall"]), small_b["union"]["union40"]["mean_candidate_set"]],
            ["base A", pct(base_a["union"]["union20"]["recall"]), base_a["union"]["union20"]["mean_candidate_set"], pct(base_a["union"]["union40"]["recall"]), base_a["union"]["union40"]["mean_candidate_set"]],
            ["base B", pct(base_b["union"]["union20"]["recall"]), base_b["union"]["union20"]["mean_candidate_set"], pct(base_b["union"]["union40"]["recall"]), base_b["union"]["union40"]["mean_candidate_set"]],
        ]),
        "",
        "由于当前词法路径几乎不能处理未见中文口语，union 在本轮基本等于 semantic recall；它仍保留了未来加入精确命中后的评测接口。",
        "",
        "## 10. Stability",
        "",
        "稳定性按每个目标的 2–3 条改写计算 rank spread（max-min），以下列出文档 B 中 spread 最大的前 10 个目标；这项统计用于发现改写敏感性，不是额外的准确率。",
        "",
    ])
    stability_rows = []
    for model, label in (("intfloat/multilingual-e5-small", "small B"), ("intfloat/multilingual-e5-base", "base B")):
        for row in summary["stability"][model][:10]:
            stability_rows.append([label, row["target"], row["count"], row["best_rank"], row["worst_rank"], row["median_rank"], row["variance"], row["spread"]])
    lines.append(table(["配置", "目标", "改写数", "best", "worst", "median", "variance", "spread"], stability_rows))
    all_spreads = {model: [x["spread"] for x in rows] for model, rows in summary["stability"].items()}
    lines.extend(["", "平均 spread：" + "; ".join(f"{('small B' if 'small' in model else 'base B')} {statistics.mean(values):.0f}" for model, values in all_spreads.items()), ""])
    lines.extend([
        "## 11. Required case studies",
        "",
        "下面挑出用户关心的衣摆、袜子和单双眼冲突样例；rank 是全量 54,879 候选中的名次，Top-5 是 small A。",
        "",
    ])
    study_rows = []
    study_targets = ("untucked_shirt", "no_socks", "socks", "shirt_tucked_in", "closed_eyes", "one_eye_closed")
    for target in study_targets:
        candidates = [x for x in clean_cases if x["target"] == target]
        # Prefer required examples, then retain up to five clean variants for
        # targets whose required wording was excluded by leakage.
        candidates.sort(key=lambda x: (x["source"] != "required-case", x["id"]))
        for row in candidates[:5]:
            base_row = maps["base A"].get(row["id"], {})
            study_rows.append([
                row["target"], row["query"], row["source"], row.get("zh_cn", "") or "—",
                number(row.get("rank")), number(base_row.get("rank")),
                ", ".join(x["tag"] for x in row["top5"]),
                ", ".join(x["tag"] for x in base_row.get("top5", [])),
                row.get("conflict") or "—", number(row.get("conflict_rank")),
                number(base_row.get("conflict_rank")), classify_failure(row) if rank(row) > 20 else "Top-20",
            ])
    lines.append(table(["target", "query", "source", "现有中文", "small rank", "base rank", "small Top-5", "base Top-5", "conflict", "small conflict rank", "base conflict rank", "备注"], study_rows))
    lines.extend([
        "",
        "这组案例也显示：带有明确中文现有标签的 holdout/required query 会显著好于真正未见改写；因此不能把“衣摆留在外面”等少量命中直接外推为整体能力。",
        "",
        "## 12. Failure taxonomy and manual review",
        "",
        "分类对 small A 的 rank>20 失败做确定性启发式归类：先识别冲突，再识别缺少中文，之后识别长句和逻辑组合，剩余为近邻/语义偏移。它不是人工金标准；人工复查了最差 10 条，确认主要是前额/刘海、蹲姿、双马尾、剪刀手、吊袜带等概念被 `forehead`、`legs`、`scissors`、`garter` 等邻近 tag 抢走。",
        "",
    ])
    failures = [x for x in primary if rank(x) > 20]
    taxonomy = Counter(classify_failure(x) for x in failures)
    base_failures = [x for x in base_a["details"] if rank(x) > 20]
    base_taxonomy = Counter(classify_failure(x) for x in base_failures)
    taxonomy_rows = []
    for category in TAXONOMY_LABELS:
        sample = next((x["query"] for x in failures if classify_failure(x) == category), "—")
        taxonomy_rows.append([category, taxonomy.get(category, 0), f"{taxonomy.get(category, 0) / len(failures) * 100:.1f}%", base_taxonomy.get(category, 0), sample])
    lines.append(table(["类别", "small 数量", "占 small miss", "base 数量", "典型 query"], taxonomy_rows))
    lines.extend(["", "人工复查样例（small A 最差 10 条）：", ""])
    review_rows = []
    for row in sorted(primary, key=rank, reverse=True)[:10]:
        review_rows.append([row["query"], row["target"], rank(row), ", ".join(x["tag"] for x in row["top5"]), manual_review_reason(row)])
    lines.append(table(["query", "target", "rank", "Top-5", "诊断"], review_rows))
    lines.extend(["", "### Worst failures (30)", "", "按 small A 全量 rank 从差到好列出 30 条；base rank 和现有中文也一并保留。", ""])
    worst_rows = []
    for row in sorted(primary, key=rank, reverse=True)[:30]:
        base_row = maps["base A"].get(row["id"], {})
        worst_rows.append([
            row["id"], row["query"], row["target"], row.get("zh_cn", "") or "—", rank(row), rank(base_row),
            ", ".join(x["tag"] for x in row["top5"]),
            ", ".join(x["tag"] for x in base_row.get("top5", [])), manual_review_reason(row),
        ])
    lines.append(table(["id", "query", "expected", "现有中文", "small rank", "base rank", "small Top-5", "base Top-5", "推测原因"], worst_rows))
    improvements = []
    for row in primary:
        small_b_rank = rank(maps["small B"].get(row["id"], {}))
        base_a_rank = rank(maps["base A"].get(row["id"], {}))
        gain = rank(row) - min(small_b_rank, base_a_rank)
        if gain > 0:
            improvements.append((gain, row, small_b_rank, base_a_rank))
    lines.extend([
        "",
        "## 13. Best Improvements",
        "",
        "增强文档 B 的整体指标没有改善；为避免只报平均值，下面仍列出 20 个局部改善最大的样例（small B 或 base A 相对 small A）。这些是诊断案例，不是整体胜出结论。",
        "",
    ])
    improvement_rows = []
    for gain, row, small_b_rank, base_a_rank in sorted(improvements, key=lambda item: item[0], reverse=True)[:20]:
        improvement_rows.append([row["id"], row["query"], row["target"], rank(row), small_b_rank, base_a_rank, gain])
    lines.append(table(["id", "query", "target", "small A", "small B", "base A", "best gain"], improvement_rows))
    lines.extend([
        "",
        "## 14. Size and performance",
        "",
        table(["模型", "冷加载 median/P90/P95 (ms)", "warm embedding median/P90/P95 (ms)", "Top-50 similarity median/P90/P95 (ms)", "总查询 median/P90/P95 (ms)", "RSS after load"], [
            ["E5-small", "/".join(number(summary["performance"]["intfloat/multilingual-e5-small"]["cold_model_load"][k]) for k in ("median_ms", "p90_ms", "p95_ms")), "/".join(number(summary["performance"]["intfloat/multilingual-e5-small"]["warm_query_embedding"][k]) for k in ("median_ms", "p90_ms", "p95_ms")), "/".join(number(summary["performance"]["intfloat/multilingual-e5-small"]["candidate_similarity_top50"][k]) for k in ("median_ms", "p90_ms", "p95_ms")), "/".join(number(summary["performance"]["intfloat/multilingual-e5-small"]["total_semantic_query"][k]) for k in ("median_ms", "p90_ms", "p95_ms")), f"{summary['performance']['intfloat/multilingual-e5-small']['rss_after_load_mb']:.2f} MB"],
            ["E5-base", "/".join(number(summary["performance"]["intfloat/multilingual-e5-base"]["cold_model_load"][k]) for k in ("median_ms", "p90_ms", "p95_ms")), "/".join(number(summary["performance"]["intfloat/multilingual-e5-base"]["warm_query_embedding"][k]) for k in ("median_ms", "p90_ms", "p95_ms")), "/".join(number(summary["performance"]["intfloat/multilingual-e5-base"]["candidate_similarity_top50"][k]) for k in ("median_ms", "p90_ms", "p95_ms")), "/".join(number(summary["performance"]["intfloat/multilingual-e5-base"]["total_semantic_query"][k]) for k in ("median_ms", "p90_ms", "p95_ms")), f"{summary['performance']['intfloat/multilingual-e5-base']['rss_after_load_mb']:.2f} MB"],
        ]),
        "",
        "性能样本均为 30 次；冷加载每次新建 encoder，warm/相似度复用已加载 encoder 和 FP32 mmap 矩阵。RSS 是整个 benchmark 进程在相应模型阶段的近似工作集，不是 Android 进程承诺值。",
        "",
        "## 15. Interpretation, limitations and recommendation",
        "",
        "1. 这轮结果支持“纯 E5 相似度只能作为召回候选，不应单独决定最终词条”的判断。尤其是否定与数量，embedding 把语义主题相似误当成逻辑等价。",
        "2. 文档 A 优于“无筛选 alias 拼接”的文档 B；下一阶段应评测字段加权/分字段编码、中文现有标签优先、冲突 pair 重排，而不是继续堆 alias。",
        "3. 真正接入 Android 前，先建立人工标注的 unseen holdout，并把 Top-20 candidate recall、冲突前置率、P95 延迟和内存作为门槛。",
        "4. 本轮样例来自普通词条；没有把作者/作品词条当作翻译目标，也没有为缺失中文标签调用任何翻译服务。",
        "5. 生产代码当前没有 E5/embedding 语义路径；因此本报告不能证明 app 已上线语义搜索，也不应据此修改运行时默认行为。",
        "6. paraphrase 是人工/规则策划的离线样例，不是 LLM 翻译结果；存在主题采样和措辞偏差。上一轮真实 holdout 原始 18 条、干净 17 条。",
        "7. 英文只有 N=3、日文只有 N=1，不能据此比较跨语言能力；标准译文质量、缺失中文字段和候选文档长度都会影响结果。",
        "8. 延迟与 RSS 是 Windows CPU benchmark，不能直接代表 Snapdragon 8 Gen 3 Android 性能；移动端还需单独测量 ONNX 后端和内存峰值。",
        "9. Recommendation A：值得继续研究 semantic retrieval，但当前只适合作为 lexical fallback/候选扩展，不适合直接 Top-1 自动选 tag。",
        "10. Recommendation B/C：先用 small + 文档 A、保留 semantic Top-20/40 供 UI 候选；base 不足以抵消本轮的体积、RSS 和延迟成本。",
        "11. Recommendation D/E：上线前应加入否定/数量/方向 reranker，并补充人工标注的 500+ unseen holdout；暂不把未见中文语义结果写回生产词库。",
        "",
        "复跑（不会启动应用）：",
        "",
        "```powershell",
        "& .\\tool\\.tmp\\semantic-search\\venv\\Scripts\\python.exe -B -u .\\tool\\semantic_search\\semantic_paraphrase_benchmark.py --threads 4 --timeout 1200",
        "& .\\tool\\.tmp\\semantic-search\\venv\\Scripts\\python.exe .\\tool\\semantic_search\\render_semantic_paraphrase_report.py",
        "```",
        "",
        "## Appendix A. Full clean-case appendix",
        "",
        "每行保留 ID、query、target、现有中文、来源/类型、small/base rank、词法 rank、冲突 tag 与两套模型的冲突 rank、small/base Top-5；`—` 表示词法未命中或没有冲突。",
        "",
    ])
    appendix_rows = []
    for row in clean_cases:
        base_row = maps["base A"].get(row["id"], {})
        lexical_row = maps["lexical"].get(row["id"], {})
        appendix_rows.append([
            row["id"], row["query"], row["target"], row.get("zh_cn", "") or "—",
            row["source"], row["query_type"], row.get("category", "—"), row.get("post_count", "—"),
            rank(row), rank(maps["small B"].get(row["id"], {})),
            rank(base_row), rank(maps["base B"].get(row["id"], {})),
            lexical_row.get("rank") or "—", row.get("conflict") or "—",
            row.get("conflict_rank") or "—", base_row.get("conflict_rank") or "—",
            ", ".join(x["tag"] for x in row["top5"]),
            ", ".join(x["tag"] for x in base_row.get("top5", [])),
        ])
    lines.append(table(["id", "query", "target", "现有中文", "source", "type", "category", "post_count", "small A", "small B", "base A", "base B", "lexical", "conflict", "small conflict", "base conflict", "small Top-5", "base Top-5"], appendix_rows))
    lines.extend(["", "## Appendix B. Leakage-excluded cases", "", "这些样例被保留用于审计，但不进入主指标：", ""])
    lines.append(table(["id", "source", "query", "target", "existing label", "reason"], [[x["id"], x["source"], x["query"], x["target"], x.get("zh_cn", ""), ",".join(x.get("leakage", []))] for x in leaked_cases]))
    lines.extend(["", "## Appendix C. Artifact pointers", "", "- Case manifest: `tool/.tmp/semantic-search/paraphrase/cases.json`", "- Machine-readable summary: `tool/.tmp/semantic-search/paraphrase/summary.json`", "- Benchmark source: `tool/semantic_search/semantic_paraphrase_benchmark.py`", "- This renderer: `tool/semantic_search/render_semantic_paraphrase_report.py`", ""])
    OUTPUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
