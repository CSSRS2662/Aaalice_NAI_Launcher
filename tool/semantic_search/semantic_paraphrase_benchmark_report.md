# Semantic Paraphrase Benchmark

> 离线、只读评测：本轮没有启动 Flutter/Android，没有改动 `lib/`、生产数据库或查询数据。

## 1. Executive Summary

- 评测覆盖 **141 个目标词条、560 条原始样例、512 条无泄漏样例**；其中未见同义/口语改写 423 条，Hard Set 100 条。
- 主指标使用 54,879 个生产候选（Danbooru/e621 category 0/7）；48 条样例因包含目标当前中文标签而剔除，完整记录保留在附录 B。
- 推荐先以 E5-small + 文档 A（英文 tag + 已有中文）作为离线基线：Top-20 35.4%，MRR@10 16.4%；E5-base 文档 A 为 Top-20 34.4%。
- E5-base 没有改善未见中文改写：文档 A 的 Top-20 略低于 small；在本机更慢、更占内存。
- 把现有英文 alias 全部拼进文档 B 反而明显退化（small Top-20 从 35.4% 降到 28.5%，base 从 34.4% 降到 18.9%），不应直接作为默认文档格式。
- 口语 Hard Set 的主要风险是否定、数量和方向词被相邻 tag 抢走：small A 有冲突的 134 条中，48 条冲突排在目标前。
- 生产 Flutter 当前仍是词典/LIKE/FTS 词法搜索；代码中没有 E5/embedding 语义检索接线，因此本报告评估的是隔离 harness，不宣称应用已经具备该模型。
- 结论：先保留本 benchmark 和小模型文档 A 作为可复现实验基线；上线前需要专门的否定/数量重排、候选召回与人工标注集，而不是直接把这轮结果接入生产。

## 2. Goal and scope

目标是测量“用户没有说出标签原文时，中文自然语言能否找回正确 Danbooru tag”。样例覆盖衣物、袜类、眼睛、表情、头发、姿势、方向/镜头、数量、空间关系和动作，并额外保留上一轮真实 holdout。

本轮明确不做：翻译 API、LLM 翻译、别名/查询写回、生产数据库修改、Flutter 启动、功能重构。

## 3. Environment and data

| 项目 | 值 |
| --- | --- |
| OS / CPU | Windows NT 10.0.19045 / AMD Ryzen 5 5600H |
| 候选范围 | 54,879 tags（category 0: 30,782; 7: 24,097） |
| catalog | 46,792,704 bytes; SHA256 `9b9693af5f6cfafda2ed8d85488b0a6c3741b0c589da935291b20dff439a2288` |
| 词典快照 | ffdkj.sqlite SHA256 `167b38430eaa230b8f19196471da11e87e1b4857947fb03e34256ba8feb83606` |
| catalog data version | 125148ac88dc |
| candidate translations | mode, tag, zh_cn |
| runtime | numpy 2.4.6, ONNX Runtime CPUExecutionProvider, 4 threads |
| benchmark time | 2026-09-12 (local Windows time) |
| git HEAD | 1f6e6ee21e1c8abf2101236ae283b440ef364e17 |
| case manifest | SHA256 `54ea1104ee0d1208107abb38650d66cadfbe9727422745a90f02fa57b978e79c` |

固定模型与缓存：

| 模型 | ONNX / tokenizer | 向量维度 | 文档矩阵 |
| --- | --- | --- | --- |
| multilingual-e5-small | 118,346,824 / 17,082,730 bytes | 384 | FP32；84,294,272 bytes / variant |
| multilingual-e5-base | 278,686,411 / 17,082,660 bytes | 768 | FP32；168,588,416 bytes / variant |

模型和 tokenizer 使用 `tool/semantic_search/models.json` 中固定 revision 与 SHA256；E5 查询使用 `query: ` 前缀、文档使用 `passage: ` 前缀，attention-mask mean pooling、L2 normalization、max length 128、稳定排序。

| 模型 | 固定 revision | model.onnx SHA256 | tokenizer.json SHA256 |
| --- | --- | --- | --- |
| multilingual-e5-small | 614241f622f53c4eeff9890bdc4f31cfecc418b3 | dd476dd0c2514e9b9be83aeb3853fac0763e0bdf4a71645407587d77c48a2d88 | 0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39 |
| multilingual-e5-base | d128750597153bb5987e10b1c3493a34e5a4502a | 2523551878658b305550d8759443822dbfda9ed9c8012ef2c354ba2c5b9de503 | 62c24cdc13d4c9952d63718d6c9fa4c287974249e16b7ade6d5a85e7bbb75626 |

## 4. Dataset and leakage policy

| 来源 | 原始 | 主指标纳入 |
| --- | --- | --- |
| unseen paraphrase | 423 | 378 |
| Hard Set（20 对冲突 × 5） | 100 | 100 |
| real-world holdout | 18 | 17 |
| required user cases | 19 | 17 |
| 合计 | 560 | 512 |

每条样例只允许一个 `(query, target)`；若 query 含目标当前 `zh_cn`/`zh_tw` 的完整两字以上标签，就标记 leakage 并从主指标排除。Hard Set 修改后保留干净的 100/100；48 条被排除样例不是静默删除，见附录 B。

## 5. Retrieval configurations

- 文档 A（minimal）：canonical `english_tag + existing zh_cn`。
- 文档 B（enhanced-existing）：文档 A 加 underscore-split English tag 与数据库已有 aliases；没有新增翻译、描述或人工别名。
- Lexical baseline：按现有 `TagCatalogRepository`/`ZhDictionaryService` 的标签、中文 LIKE/变体和英文 alias 逻辑做数据库等价近似；未调用 Dart API。对未见中文口语，多数返回空集是预期结果。
- Semantic full-corpus rank：54,879 个候选全量排序，报告 Top-1/3/5/10/20/50、MRR@10、rank 分布；union 是 lexical@20/40 与 semantic@20/40 的候选集合并集。

## 6. Main results (clean set)

| 配置 | Top1 | Top3 | Top5 | Top10 | Top20 | Top50 | MRR@10 | median | mean | P90 | P95 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| E5-small · A | 10.3% | 20.3% | 24.4% | 30.7% | 35.4% | 42.6% | 16.4% | 92 | 3576.81 | 11390.00 | 28237.10 |
| E5-small · B | 6.0% | 13.1% | 17.0% | 23.4% | 28.5% | 34.4% | 10.8% | 233 | 3128.36 | 9053.30 | 18070.70 |
| E5-base · A | 9.0% | 16.6% | 20.5% | 27.2% | 34.4% | 42.0% | 14.1% | 111 | 3070.84 | 11024.30 | 21051.70 |
| E5-base · B | 4.3% | 8.0% | 9.6% | 13.5% | 18.9% | 24.2% | 6.7% | 941 | 5739.90 | 19716.60 | 25133.00 |
| 词法 baseline | 0.4% | 0.4% | 0.4% | 0.4% | 0.4% | 0.4% | 0.4% | 54880 | 54665.63 | 54880.00 | 54880.00 |

词法 baseline 的 `no_result` 是 510/512；它不是模型错误，而是当前生产词法路径对未见中文改写没有可查的字面标签。Lexical 结果的 rank 以未命中记为 corpus+1，仅用于直观对比，不应与语义分数混读。

### 6.1 By source

| 来源 | N | small A Top1 | small A Top5 | small A Top20 | base A Top20 | small A MRR@10 |
| --- | --- | --- | --- | --- | --- | --- |
| paraphrase | 378 | 9.5% | 23.0% | 33.9% | 33.3% | 15.3% |
| hard | 100 | 8.0% | 19.0% | 28.0% | 31.0% | 13.1% |
| real-world-holdout | 17 | 23.5% | 70.6% | 94.1% | 70.6% | 44.2% |
| required-case | 17 | 29.4% | 41.2% | 52.9% | 41.2% | 33.8% |

### 6.2 By query type (small A vs base A Top-20)

| 类型 | N | small A Top1 | small A Top20 | base A Top20 | small A median rank |
| --- | --- | --- | --- | --- | --- |
| action | 32 | 9.4% | 31.2% | 53.1% | 60 |
| camera | 16 | 0.0% | 12.5% | 6.2% | 3850 |
| clothing | 64 | 10.9% | 31.2% | 17.2% | 100 |
| direction | 30 | 0.0% | 23.3% | 33.3% | 291 |
| expression | 13 | 15.4% | 46.2% | 46.2% | 40 |
| eyes | 41 | 12.2% | 36.6% | 31.7% | 61 |
| hair | 53 | 17.0% | 39.6% | 32.1% | 93 |
| holdout | 17 | 23.5% | 94.1% | 70.6% | 2 |
| legwear | 37 | 0.0% | 24.3% | 13.5% | 299 |
| mouth | 27 | 3.7% | 40.7% | 25.9% | 94 |
| negation | 21 | 19.1% | 42.9% | 33.3% | 41 |
| orientation | 11 | 18.2% | 36.4% | 63.6% | 81 |
| pose | 49 | 0.0% | 16.3% | 32.6% | 384 |
| quantity | 63 | 15.9% | 42.9% | 47.6% | 56 |
| spatial | 18 | 27.8% | 61.1% | 61.1% | 10 |
| state | 20 | 5.0% | 25.0% | 30.0% | 318 |

### 6.3 By query language

| 语言 | N | small A Top1 | small A Top20 | base A Top20 | 备注 |
| --- | --- | --- | --- | --- | --- |
| 中文 | 508 | 10.4% | 35.0% | 34.1% | 主评测语言 |
| 英文 | 3 | 0.0% | 100.0% | 100.0% | N=3，样本不足 |
| 日文 | 1 | 0.0% | 0.0% | 0.0% | N=1，样本不足 |

## 7. Candidate-document ablation

| 模型 | A Top20 | B Top20 | 变化 | A MRR@10 | B MRR@10 |
| --- | --- | --- | --- | --- | --- |
| E5-small | 35.4% | 28.5% | -6.8 pp | 16.4% | 10.8% |
| E5-base | 34.4% | 18.9% | -15.4 pp | 14.1% | 6.7% |

别名拼接没有带来召回增益，反而稀释了短 tag 与中文标签的语义表示；这是本数据、固定模型和固定 pooling 下的消融结论，不代表 alias 永远无用。

## 8. Conflict and polarity analysis

| 配置 | 有冲突样例 | 冲突在目标前 | 前置率 | 平均 target-conflict margin | 负 margin |
| --- | --- | --- | --- | --- | --- |
| small A | 134 | 48 | 35.8% | 0.01 | 48 |
| small B | 134 | 52 | 38.8% | 0.01 | 52 |
| base A | 134 | 54 | 40.3% | 0.01 | 54 |
| base B | 134 | 48 | 35.8% | 0.01 | 48 |

`margin = score(target) - score(conflict)`；负 margin 与“冲突排在目标前”应一致。该现象说明纯 embedding 相似度不会可靠地理解“不/只/两边/背对”等逻辑词。
Lexical 没有可排序的冲突分数；Union 是去重候选集合而非单一排序，因此 conflict-before-target 对 lexical/union 不定义，避免伪造该指标。

### All conflict-before-target cases (small A)

| id | query | target | target rank | conflict | conflict rank | margin | Top-5 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| hard-001-1 | 别把衣角收进裙头 | untucked_shirt | 210 | shirt_tucked_in | 50 | -0.01 | hand_under_dress, sideless_dress, impossible_dress, no_u-turn_sign, unworn_dress |
| hard-001-4 | 衣角留在外面别收进去 | untucked_shirt | 41 | shirt_tucked_in | 3 | -0.01 | clothing_aside, head_under_another's_clothes, shirt_tucked_in, no_pants, from_inside |
| hard-001-5 | 不要整理成塞进腰里的样子 | untucked_shirt | 1308 | shirt_tucked_in | 6 | -0.02 | no_detached_sleeves, sleeveless_blazer, jumpsuit_around_waist, see-through_midriff, yabuki_joe_in_a_chair_(meme) |
| hard-002-2 | 袜子拿掉 | no_socks | 48 | socks | 15 | -0.01 | single_sock_removed, pulling_off_legwear, legwear_cutout, removing_sock, unworn_socks |
| hard-003-2 | 上下嘴唇拉开一点 | open_mouth | 184 | closed_mouth | 171 | -0.00 | thick_lips, lower_lip_only, soul_patch, labret_piercing, side_labret_piercing |
| hard-004-1 | 双眼一起合上 | closed_eyes | 854 | one_eye_closed | 3 | -0.03 | mark_under_both_eyes, thighs_together, one_eye_closed, eyes_in_shadow, covering_another's_eye |
| hard-004-2 | 两边眼皮都落下来 | closed_eyes | 119 | one_eye_closed | 66 | -0.00 | mark_under_both_eyes, two-tone_skin, eye_injury, eye_drops, lowered_eyelids |
| hard-004-3 | 两只眼都别睁着 | closed_eyes | 24 | one_eye_closed | 3 | -0.01 | unusually_open_eyes, single_blank_eye, one_eye_closed, mark_under_both_eyes, covering_another's_eye |
| hard-004-4 | 像睡着一样闭住两眼 | closed_eyes | 7 | one_eye_closed | 5 | -0.00 | sleeping_with_eyes_open, unusually_open_eyes, half-closed_eye, closing_eyes, one_eye_closed |
| hard-004-5 | 不要只闭一边 | closed_eyes | 299 | one_eye_closed | 9 | -0.02 | bodystocking_only, closing, single_over-kneehigh, single_shoulder_pad, single_fingerless_glove |
| hard-005-3 | 把眼皮抬起来 | opening_eyes | 72 | closed_eyes | 67 | -0.00 | hands_up, blindfold_lift, glowing_pupils, glowing_eye, eye_piercing |
| hard-005-4 | 不要闭着眼 | opening_eyes | 49 | closed_eyes | 5 | -0.02 | no_sclera, closing_eyes, ;/, no_goggles, closed_eyes |
| hard-005-5 | 两边眼珠都露出来 | opening_eyes | 897 | closed_eyes | 238 | -0.01 | mark_under_both_eyes, eyes_visible_through_headwear, googly_eyes, eyes_in_shadow, covering_another's_eye |
| hard-007-2 | 脚上别有鞋 | barefoot | 435 | shoes | 168 | -0.01 | uneven_footwear, no_toes, unworn_shoes, unworn_sandals, no_shoes |
| hard-007-4 | 鞋子脱掉直接走 | barefoot | 6678 | shoes | 61 | -0.03 | removing_shoes, shoe_loss, unworn_shoes, straight-laced_footwear, removing_coat |
| hard-008-1 | 把鞋脱下来 | no_shoes | 227 | shoes | 55 | -0.01 | unworn_shoes, removing_shoes, shoe_loss, single_sock_removed, removing_coat |
| hard-009-5 | 发梢停在耳朵附近 | short_hair | 721 | long_hair | 548 | -0.00 | hair_around_ear, headphones_around_neck, hair_ears, hair_behind_ear, scar_on_ear |
| hard-010-1 | 发丝垂到腰 | long_hair | 943 | short_hair | 824 | -0.00 | tightrope, hair_between_eyes, fur-trimmed_belt, floating_hair, hair_scarf |
| hard-010-3 | 不要剪成短发 | long_hair | 567 | short_hair | 1 | -0.04 | short_hair, short_hair_with_long_locks, pixie_cut, no_hairclip, very_short_hair |
| hard-010-5 | 发尾超过肩膀很多 | long_hair | 462 | short_hair | 187 | -0.00 | too_many_hair_ornaments, impossible_hair, extra_limbs, hair_over_shoulder, curly_ends |
| hard-011-2 | 不要安排第二个人 | solo | 6798 | 2girls | 189 | -0.02 | trick_or_treat, trick-or-treating, hands_on_another's_chest, hand_on_another's_back, no_parking_sign |
| hard-011-4 | 不需要两位女生同框 | solo | 15572 | 2girls | 4 | -0.04 | finger_frame_duo, two-tone_eyewear, asymmetrical_dual_wielding, 2girls, multiple_others |
| hard-012-3 | 不要只放一个人 | 2girls | 7606 | solo | 21 | -0.03 | lower_lip_only, hand_on_another's_back, single_fingerless_glove, anal_only, hand_on_another's_crotch |
| hard-012-5 | 一人不够，要两个人 | 2girls | 590 | solo | 115 | -0.01 | heart_hands_duo, implied_double_penetration, single_mitten, double_amputee, couple |
| hard-013-1 | 只出现单眼 | one_eye_visible | 2212 | eyes_visible_through_hair | 121 | -0.02 | single_blank_eye, single_empty_eye, one_eye_covered, one_eye_closed, lower_eyelashes_only |
| hard-013-2 | 另一只眼不要入镜 | one_eye_visible | 5192 | eyes_visible_through_hair | 617 | -0.02 | no_goggles, no_eyewear, no_sclera, unworn_goggles, hand_over_another's_eyes |
| hard-013-3 | 画面只留一边眼睛 | one_eye_visible | 3579 | eyes_visible_through_hair | 99 | -0.02 | eyes_out_of_frame, one_eye_covered, one_eye_closed, veil_over_one_eye, covering_one_eye |
| hard-013-4 | 只能看到一只眼 | one_eye_visible | 683 | eyes_visible_through_hair | 54 | -0.02 | one_eye_covered, one-eyed, covering_one_eye, single_blank_eye, spiral-only_eyes |
| hard-013-5 | 不要把两只眼都画出来 | one_eye_visible | 27720 | eyes_visible_through_hair | 1008 | -0.04 | mark_under_both_eyes, drawn_on_eyes, single_blank_eye, multiple_style_parody, no_eyepatch |
| hard-015-1 | 两只手一起出现 | multiple_hands | 4044 | single_hand | 11 | -0.04 | hand_between_legs, two-handed, two-handed_handjob, hand_grabbing_both_breasts, two-sided_gloves |
| hard-015-2 | 两只手要同时出现在镜头里 | multiple_hands | 13551 | single_hand | 19 | -0.04 | hand_grabbing_both_breasts, hand_between_legs, double_handjob, finger_frame_duo, twin-lens_reflex_camera |
| hard-015-3 | 要看到两只手 | multiple_hands | 19722 | single_hand | 5 | -0.06 | hand_grabbing_both_breasts, two-handed, hand_between_legs, two-handed_handjob, single_hand |
| hard-015-4 | 不要只画一只手 | multiple_hands | 19745 | single_hand | 2 | -0.07 | single_mechanical_hand, single_hand, no_hands, single_fingerless_glove, artist's_hand_in_frame |
| hard-015-5 | 手的数量至少两个 | multiple_hands | 1120 | single_hand | 11 | -0.03 | two-handed, too_many_hands, two-sided_gloves, finger_counting, hand_between_legs |
| hard-016-2 | 胸口朝向画面 | facing_viewer | 1362 | from_behind | 255 | -0.01 | see-through_bra, chest_eye, head_on_chest, looking_at_breasts, heart_on_chest |
| hard-016-4 | 不要背对镜头 | facing_viewer | 2020 | from_behind | 5 | -0.03 | facing_back, facing_away, ass-to-ass_penetration, against_chalkboard, from_behind |
| hard-016-5 | 从正面拍摄 | facing_viewer | 92 | from_behind | 26 | -0.01 | facing_back, film_set, recording, frontal_wedgie, photorealistic |
| hard-018-4 | 不要把目光移开 | looking_at_viewer | 1396 | looking_away | 412 | -0.01 | averting_eyes, no_pupils, no_eyebrows, no_sclera, unusually_open_eyes |
| hard-019-3 | 视线避开观众 | looking_away | 1043 | looking_at_viewer | 6 | -0.04 | attacking_viewer, peeing_on_viewer, insulting_viewer, stepping_on_viewer, firing_at_viewer |
| hard-020-5 | 上衣剪掉袖筒 | sleeveless | 2033 | long_sleeves | 1072 | -0.01 | cutting_clothes, clothing_cutout, coat_partially_removed, arm_cutout, crotch_cutout |
| r-001 | 衣服不要塞进裙子 | untucked_shirt | 435 | shirt_tucked_in | 23 | -0.02 | sleeveless_dress, hand_under_dress, unworn_sleeves, no_detached_sleeves, sweater_under_dress |
| r-005 | 不把衣服塞进裤腰 | untucked_shirt | 387 | shirt_tucked_in | 30 | -0.02 | pants_tucked_in, no_male_underwear, sleeveless_tunic, hand_in_pants, no_detached_sleeves |
| r-010 | 袜子去掉 | no_socks | 48 | socks | 7 | -0.01 | single_sock_removed, pulling_off_legwear, removing_sock, legwear_cutout, unworn_socks |
| r-015 | 下摆全部收好别露在外面 | shirt_tucked_in | 4886 | untucked_shirt | 2 | -0.03 | off-shoulder_jacket, untucked_shirt, sideless_outfit, untucked, off-shoulder_shirt |
| r-016 | 两只眼睛都合上 | closed_eyes | 168 | one_eye_closed | 23 | -0.01 | mark_under_both_eyes, double_eyepatch, two_of_hearts, third_eye_on_chest, two-tone_eyes |
| r-019 | 双眼闭着 | closed_eyes | 4 | one_eye_closed | 2 | -0.00 | closing_eyes, one_eye_closed, third_eye_closed, closed_eyes, ;/ |
| h-002 | 衬衫不塞进裙子 | untucked_shirt | 17 | shirt_tucked_in | 12 | -0.00 | shirt_under_dress, shirt_over_dress, slip_showing, shirt_under_shirt, sweater_under_shirt |
| h-017 | 两只眼睛都闭上 | closed_eyes | 7 | one_eye_closed | 1 | -0.01 | one_eye_closed, third_eye_closed, closing_eyes, half-closed_eyes, unusually_open_eyes |
## 9. Lexical + semantic union

| 模型/文档 | union@20 recall | 平均候选数 | union@40 recall | 平均候选数 |
| --- | --- | --- | --- | --- |
| small A | 35.4% | 20 | 40.0% | 40 |
| small B | 28.5% | 20 | 32.6% | 40 |
| base A | 34.4% | 20 | 39.8% | 40 |
| base B | 18.9% | 20 | 23.1% | 40 |

由于当前词法路径几乎不能处理未见中文口语，union 在本轮基本等于 semantic recall；它仍保留了未来加入精确命中后的评测接口。

## 10. Stability

稳定性按每个目标的 2–3 条改写计算 rank spread（max-min），以下列出文档 B 中 spread 最大的前 10 个目标；这项统计用于发现改写敏感性，不是额外的准确率。

| 配置 | 目标 | 改写数 | best | worst | median | variance | spread |
| --- | --- | --- | --- | --- | --- | --- | --- |
| small B | crouching | 3 | 45111 | 51878 | 45160 | 10102912.67 | 6767 |
| small B | stockings | 3 | 42153 | 46077 | 45455 | 2965318.22 | 3924 |
| small B | v_sign | 3 | 1317 | 45433 | 10206 | 362908589.56 | 44116 |
| small B | bangs | 3 | 16206 | 41469 | 29984 | 106661964.22 | 25263 |
| small B | eyewear | 3 | 25114 | 34635 | 28621 | 15457409.56 | 9521 |
| small B | double_ponytail | 3 | 10103 | 28798 | 28044 | 74661224.67 | 18695 |
| small B | squatting | 3 | 359 | 28563 | 10220 | 136574509.56 | 28204 |
| small B | clothing_lift | 3 | 10031 | 27856 | 17071 | 53734272.22 | 17825 |
| small B | close-up | 2 | 23193 | 27028 | 25110 | 3676806.25 | 3835 |
| small B | hand_on_hip | 3 | 17978 | 25444 | 18184 | 12054576.89 | 7466 |
| base B | crouching | 3 | 40172 | 47392 | 42434 | 9091867.56 | 7220 |
| base B | double_ponytail | 3 | 24227 | 45657 | 27501 | 88844923.56 | 21430 |
| base B | eyewear | 3 | 27872 | 45495 | 39569 | 53611934.89 | 17623 |
| base B | v_sign | 3 | 19497 | 44975 | 22504 | 129235152.67 | 25478 |
| base B | stockings | 3 | 43787 | 44248 | 43837 | 42660.22 | 461 |
| base B | standing | 3 | 7620 | 44229 | 31919 | 231355153.56 | 36609 |
| base B | angry | 3 | 175 | 41011 | 12512 | 292441496.22 | 40836 |
| base B | smile | 3 | 15746 | 37453 | 30884 | 82611628.22 | 21707 |
| base B | bangs | 3 | 22420 | 35407 | 25166 | 31231196.22 | 12987 |
| base B | shoes | 3 | 438 | 29559 | 1695 | 180668354.0 | 29121 |

平均 spread：small B 3887; base B 5956

## 11. Required case studies

下面挑出用户关心的衣摆、袜子和单双眼冲突样例；rank 是全量 54,879 候选中的名次，Top-5 是 small A。

| target | query | source | 现有中文 | small rank | base rank | small Top-5 | base Top-5 | conflict | small conflict rank | base conflict rank | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| untucked_shirt | 衣服不要塞进裙子 | required-case | 衬衫下摆外露 | 435 | 425 | sleeveless_dress, hand_under_dress, unworn_sleeves, no_detached_sleeves, sweater_under_dress | unbuttoned_dress, side-tie_skirt, clothes_between_breasts, side-tie_dress, dress_pants | shirt_tucked_in | 23 | 148 | G 近义/冲突 tag |
| untucked_shirt | 让衬衣自然垂在裤子外面 | required-case | 衬衫下摆外露 | 26 | 35 | male_underwear_aside, panties_under_leotard, shirt_around_waist, shirt_overhang, panties_around_one_leg | vibrator_over_clothes, shirt_around_waist, shirt_over_dress, overshirt, shirttail | shirt_tucked_in | 1008 | 933 | G 近义/冲突 tag |
| untucked_shirt | 上衣别扎进去 | required-case | 衬衫下摆外露 | 12 | 689 | finger_under_clothes, head_under_another's_clothes, sweater_tucked_in, hand_under_clothes, bodysuit_under_clothes | sweater_tucked_in, bodysuit_under_clothes, hand_under_clothes, underwear, open_bodysuit | shirt_tucked_in | 188 | 422 | Top-20 |
| untucked_shirt | 衣摆留在外面 | required-case | 衬衫下摆外露 | 1 | 40 | untucked_shirt, untucked, clothing_aside, clothes_over_shoulder, clothes_on_shoulders | vibrator_over_clothes, untucked, vibrator_under_clothes, panties_over_clothes, fur-trimmed_dress | shirt_tucked_in | 540 | 389 | Top-20 |
| untucked_shirt | 不把衣服塞进裤腰 | required-case | 衬衫下摆外露 | 387 | 1016 | pants_tucked_in, no_male_underwear, sleeveless_tunic, hand_in_pants, no_detached_sleeves | vibrator_over_clothes, clothes_around_waist, used_condom_in_clothes, clothes_between_breasts, downpants | shirt_tucked_in | 30 | 220 | G 近义/冲突 tag |
| no_socks | 不穿袜子 | required-case | 未穿袜 | 1 | 1 | no_socks, unworn_legwear, unworn_socks, unworn_kneehighs, unworn_thighhighs | no_socks, wet_socks, no_scarf, no_bodystocking, socks | socks | 210 | 5 | Top-20 |
| no_socks | 腿上别有袜子 | required-case | 未穿袜 | 12 | 72 | unworn_legwear, putting_on_legwear, pants_around_one_leg, leg_belt, underwear_around_one_leg | alternate_legwear, cum_on_legwear, thighhigh_removed, towel_on_legs, loose_thighhigh | socks | 200 | 67 | Top-20 |
| no_socks | 不要给她穿袜 | required-case | 未穿袜 | 2 | 1 | unworn_legwear, no_socks, unworn_kneehighs, unworn_thighhighs, unworn_pantyhose | no_socks, sockjob, removing_sock, frilled_footwear, velcro_footwear | socks | 532 | 12 | Top-20 |
| no_socks | 脚上没有袜子 | required-case | 未穿袜 | 1 | 8 | no_socks, unworn_socks, unworn_kneehighs, unworn_legwear, panties_around_one_ankle | mismatched_thighhighs, thighhigh_dangle, censored_feet, disembodied_legs, unworn_thighhighs | socks | 84 | 47 | Top-20 |
| no_socks | 袜子去掉 | required-case | 未穿袜 | 48 | 68 | single_sock_removed, pulling_off_legwear, removing_sock, legwear_cutout, unworn_socks | single_sock_removed, removing_sock, sock_pull, adjusting_sock, pulling_off_legwear | socks | 7 | 9 | C 否定理解失败 |
| socks | 小腿下面有袜筒 | paraphrase | 袜子 | 377 | 175 | pants_around_one_leg, underwear_around_one_leg, putting_on_legwear, leg_cutout, gingham_legwear | cum_on_legwear, tube_socks, pantyhose_around_legs, vibrator_under_pantyhose, thighhighs_under_boots | — | — | — | G 近义/冲突 tag |
| socks | 不要让脚是光的 | paraphrase | 袜子 | 9744 | 6229 | censored_feet, light-skinned_soles, no_toes, unworn_sandals, feet_out_of_frame | censored_feet, blood_on_feet, foot_focus, ankle_ring, view_between_legs | — | — | — | G 近义/冲突 tag |
| shirt_tucked_in | 把上衣边缘收进腰里 | required-case | 塞衣角 | 46 | 621 | jumpsuit_around_waist, finger_under_clothes, sweater_tucked_in, hand_under_clothes, hand_in_underwear | clothes_around_waist, obi_bow, hand_under_clothes, obi_spin, shirt_around_waist | untucked_shirt | 538 | 1919 | G 近义/冲突 tag |
| shirt_tucked_in | 衣角整齐塞进裙腰 | required-case | 塞衣角 | 1 | 6 | shirt_tucked_in, jumpsuit_around_waist, clothes_around_waist, hand_under_dress, skirt_set | clothes_around_waist, adjusting_dress, side-tie_skirt, adjusting_skirt, tunic | untucked_shirt | 819 | 1809 | Top-20 |
| shirt_tucked_in | 下摆全部收好别露在外面 | required-case | 塞衣角 | 4886 | 12656 | off-shoulder_jacket, untucked_shirt, sideless_outfit, untucked, off-shoulder_shirt | untucked, backless_bikini_bottom, one_breast_out, bikini_bottom_pull, bikini_bottom_lift | untucked_shirt | 2 | 148 | G 近义/冲突 tag |
| shirt_tucked_in | 把衬衫塞进裙子里 | real-world-holdout | 塞衣角 | 5 | 107 | shirt_under_dress, shirt_over_dress, sweater_under_shirt, shirt_under_shirt, shirt_tucked_in | shirt_on_shoulders, shirt_over_dress, shirt_under_dress, shirt_under_shirt, shirt_under_sweater | untucked_shirt | 44 | 83 | Top-20 |
| shirt_tucked_in | shirt tucked into skirt | real-world-holdout | 塞衣角 | 7 | 15 | tucked_shirt, cum_through_shirt, cum_through_skirt, horizontal-striped_skirt, tight_t-shirt | tucked_shirt, tight_skirt, tight_coat, studded_clothing, striped_t-shirt | untucked_shirt | 41 | 1036 | Top-20 |
| closed_eyes | 两只眼睛都合上 | required-case | 闭眼 | 168 | 474 | mark_under_both_eyes, double_eyepatch, two_of_hearts, third_eye_on_chest, two-tone_eyes | two-tone_eyes, two-tone_eyewear, head_between_thighs, two-tone_vest, view_between_legs | one_eye_closed | 23 | 43 | D 数量关系失败 |
| closed_eyes | 不要睁眼 | required-case | 闭眼 | 137 | 11 | sleeping_with_eyes_open, unusually_open_eyes, no_sclera, opening_eyes, lowered_eyelids | ;/, blurry_vision, opening_eyes, no_blindfold, no_eyepatch | one_eye_closed | 202 | 8 | G 近义/冲突 tag |
| closed_eyes | 双眼闭着 | required-case | 闭眼 | 4 | 5 | closing_eyes, one_eye_closed, third_eye_closed, closed_eyes, ;/ | ;/, closing_eyes, blurry_vision, one_eye_closed, closed_eyes | one_eye_closed | 2 | 4 | Top-20 |
| closed_eyes | 两只眼睛都闭上 | real-world-holdout | 闭眼 | 7 | 3 | one_eye_closed, third_eye_closed, closing_eyes, half-closed_eyes, unusually_open_eyes | one_eye_closed, closing_eyes, closed_eyes, ;/, half-closed_eyes | one_eye_closed | 1 | 1 | Top-20 |
| closed_eyes | 双眼一起合上 | hard | 闭眼 | 854 | 644 | mark_under_both_eyes, thighs_together, one_eye_closed, eyes_in_shadow, covering_another's_eye | legs_together, thighs_together, soles_together, knees_apart_feet_together, compound_eyes | one_eye_closed | 3 | 49 | D 数量关系失败 |
| one_eye_closed | 只闭一只眼 | required-case | 单眼闭合 | 1 | 1 | one_eye_closed, one_eye_covered, unusually_open_eyes, closing_eyes, covering_one_eye | one_eye_closed, ;/, closing_eyes, single_blank_eye, covering_one_eye | closed_eyes | 7 | 9 | Top-20 |
| one_eye_closed | 只闭上一只眼睛 | real-world-holdout | 单眼闭合 | 1 | 1 | one_eye_closed, unusually_open_eyes, one_eye_covered, covering_one_eye, single_blank_eye | one_eye_closed, ;/, covering_one_eye, single_blank_eye, closing_eyes | closed_eyes | 10 | 10 | Top-20 |
| one_eye_closed | 只闭一边 | hard | 单眼闭合 | 2 | 1 | closing, one_eye_closed, single_gauntlet, single_mitten, single_over-kneehigh | one_eye_closed, side_drill, closing, ;/, single_loose_sock | closed_eyes | 95 | 43 | Top-20 |
| one_eye_closed | 一边睁着另一边合上 | hard | 单眼闭合 | 3 | 46 | knees_apart_feet_together, hand_on_another's_knee, one_eye_closed, hand_on_another's_ass, bound_together | looking_at_another, facing_back, facing_another, pouring_onto_another, looking_away | closed_eyes | 3124 | 2548 | Top-20 |
| one_eye_closed | 单眼眨着 | hard | 单眼闭合 | 4 | 2 | blinking, winking_(animated), one_eye_covered, one_eye_closed, single_blank_eye | single_blank_eye, one_eye_closed, ;/, tears_from_one_eye, blinking | closed_eyes | 61 | 83 | Top-20 |

这组案例也显示：带有明确中文现有标签的 holdout/required query 会显著好于真正未见改写；因此不能把“衣摆留在外面”等少量命中直接外推为整体能力。

## 12. Failure taxonomy and manual review

分类对 small A 的 rank>20 失败做确定性启发式归类：先识别冲突，再识别缺少中文，之后识别长句和逻辑组合，剩余为近邻/语义偏移。它不是人工金标准；人工复查了最差 10 条，确认主要是前额/刘海、蹲姿、双马尾、剪刀手、吊袜带等概念被 `forehead`、`legs`、`scissors`、`garter` 等邻近 tag 抢走。

| 类别 | small 数量 | 占 small miss | base 数量 | 典型 query |
| --- | --- | --- | --- | --- |
| A 译文过于书面 | 0 | 0.0% | 0 | — |
| B 口语与译文词面断裂 | 0 | 0.0% | 0 | — |
| C 否定理解失败 | 6 | 1.8% | 9 | 别把衣角收进裙头 |
| D 数量关系失败 | 30 | 9.1% | 25 | 画面只有一个人 |
| E 方向关系失败 | 30 | 9.1% | 24 | 身体正对着画面 |
| F 语义过宽 | 0 | 0.0% | 0 | — |
| G 近义/冲突 tag | 173 | 52.3% | 191 | 衣服别塞进裙腰 |
| H 中文材料不足 | 45 | 13.6% | 46 | 把衣服往上掀露出腰 |
| I 英文 tag 不直观 | 0 | 0.0% | 0 | — |
| J 长句噪声 | 2 | 0.6% | 4 | 从脖子到上臂之间露出皮肤 |
| K 跨语言失败 | 1 | 0.3% | 0 | シャツの裾を出す |
| L 候选文本信息不足 | 44 | 13.3% | 37 | 双脚踩地保持站姿 |
| M 其他 | 0 | 0.0% | 0 | — |

人工复查样例（small A 最差 10 条）：

| query | target | rank | Top-5 | 诊断 |
| --- | --- | --- | --- | --- |
| 做出剪刀手 | v_sign | 52228 | v, holding_scissors, scissor_blade_(kill_la_kill), rock_paper_scissors, hand_on_blade | 剪刀手与 scissors/剪切动作近邻 |
| 左右各扎一束 | double_ponytail | 50022 | one_side_up, two_side_up, single_hair_intake, scarf_on_head, alternate_sleeve_length | 头发局部关系被 forehead/hair 近邻抢走 |
| 像躲藏一样半蹲 | crouching | 45687 | jacket_partially_removed, shirt_partially_removed, coat_partially_removed, partially_underwater_shot, lower_body | 姿势描述宽泛，落到 legs/衣物近邻 |
| 额头前垂着刘海 | bangs | 45159 | center-flap_bangs, sideless_bangs, eyebrows_hidden_by_hair, arched_bangs, double-parted_bangs | 头发局部关系被 forehead/hair 近邻抢走 |
| 重心压在下方 | crouching | 44866 | yellow_tank_top, white_tank_top, tank_top, heart_hands_failure, breasts_on_another's_back | 姿势描述宽泛，落到 legs/衣物近邻 |
| 伸出食指和中指比出胜利手势 | v_sign | 43405 | index_fingers_raised, double_ok_sign, index_finger_raised, holding_cue_stick, index_fingers_together | 剪刀手与 scissors/剪切动作近邻 |
| 上衣被撩到胸口以上 | clothing_lift | 43052 | clothes_between_breasts, extended_upshirt, hand_on_another's_chest, arm_around_chest, erection_under_clothes | 人工复查：近邻 tag 或关系词信息不足 |
| 两条马尾对称垂下 | double_ponytail | 41132 | two_side_up, side_ponytail, twintails_with_braided_base, ponytail_over_shoulder, high_side_ponytail | 头发局部关系被 forehead/hair 近邻抢走 |
| 一只手撑着腰 | hand_on_hip | 38601 | hand_on_floor, hands_on_floor, glove_spread, hand_on_ground, hands_on_another's_waist | 手部位置关系缺少候选文档线索 |
| 单手扶住胯部 | hand_on_hip | 38556 | hand_on_another's_hip, hand_on_own_neck, hand_on_another's_neck, hand_on_own_opposite_hip, holding_behind_neck | 手部位置关系缺少候选文档线索 |

### Worst failures (30)

按 small A 全量 rank 从差到好列出 30 条；base rank 和现有中文也一并保留。

| id | query | expected | 现有中文 | small rank | base rank | small Top-5 | base Top-5 | 推测原因 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| p-102-3 | 做出剪刀手 | v_sign | — | 52228 | 38356 | v, holding_scissors, scissor_blade_(kill_la_kill), rock_paper_scissors, hand_on_blade | v, holding_scalpel, holding_cleaver, stitched_hand, holding_boxcutter | 剪刀手与 scissors/剪切动作近邻 |
| p-072-1 | 左右各扎一束 | double_ponytail | — | 50022 | 29601 | one_side_up, two_side_up, single_hair_intake, scarf_on_head, alternate_sleeve_length | tying_another's_hair, blunt_tresses, hair_behind_eyewear, multi-tied_hair, string_around_wrist | 头发局部关系被 forehead/hair 近邻抢走 |
| p-091-2 | 像躲藏一样半蹲 | crouching | — | 45687 | 42128 | jacket_partially_removed, shirt_partially_removed, coat_partially_removed, partially_underwater_shot, lower_body | side_sitting_split, squatting, squatting_v_pose_(han-0v0), taking_shelter, sitting_backwards | 姿势描述宽泛，落到 legs/衣物近邻 |
| p-077-1 | 额头前垂着刘海 | bangs | — | 45159 | 39425 | center-flap_bangs, sideless_bangs, eyebrows_hidden_by_hair, arched_bangs, double-parted_bangs | forehead_blush, loosely_tucked_bangs, scar_on_forehead, mole_on_forehead, forehead_tattoo | 头发局部关系被 forehead/hair 近邻抢走 |
| p-091-3 | 重心压在下方 | crouching | — | 44866 | 37745 | yellow_tank_top, white_tank_top, tank_top, heart_hands_failure, breasts_on_another's_back | pectoral_press, multiple_head_bumps, breast_press, breasts_on_another's_back, pectorals_on_glass | 姿势描述宽泛，落到 legs/衣物近邻 |
| p-102-1 | 伸出食指和中指比出胜利手势 | v_sign | — | 43405 | 24826 | index_fingers_raised, double_ok_sign, index_finger_raised, holding_cue_stick, index_fingers_together | index_fingers_raised, holding_trophy, holding_binoculars, bent_v, double_inward_v | 剪刀手与 scissors/剪切动作近邻 |
| p-010-2 | 上衣被撩到胸口以上 | clothing_lift | — | 43052 | 27208 | clothes_between_breasts, extended_upshirt, hand_on_another's_chest, arm_around_chest, erection_under_clothes | breast_clinging, front-tie_top, clothes_over_shoulder, multi-strapped_bikini_top, front-tie_bikini_top | 人工复查：近邻 tag 或关系词信息不足 |
| p-072-2 | 两条马尾对称垂下 | double_ponytail | — | 41132 | 17313 | two_side_up, side_ponytail, twintails_with_braided_base, ponytail_over_shoulder, high_side_ponytail | two_side_up, arms_at_sides, twin_drills, legs_on_another's_shoulders, legs_behind_head | 头发局部关系被 forehead/hair 近邻抢走 |
| p-127-1 | 一只手撑着腰 | hand_on_hip | — | 38601 | 27486 | hand_on_floor, hands_on_floor, glove_spread, hand_on_ground, hands_on_another's_waist | hand_on_another's_hip, hands_on_lap, hand_on_belt, hands_on_another's_hips, hand_on_another's_waist | 手部位置关系缺少候选文档线索 |
| p-127-2 | 单手扶住胯部 | hand_on_hip | — | 38556 | 32638 | hand_on_another's_hip, hand_on_own_neck, hand_on_another's_neck, hand_on_own_opposite_hip, holding_behind_neck | single_elbow_pad, one_arm_handstand, hand_on_own_knee, single_wrist_cuff, single_bracer | 手部位置关系缺少候选文档线索 |
| p-091-1 | 身体缩低弯着腿 | crouching | — | 38428 | 35293 | disembodied_legs, thin_calves, hanging_legs, legs_folded, leg_behind_shoulder | legs_back, leg_behind_shoulder, bikini_bottom_around_leg, hands_under_legs, arm_around_leg | 姿势描述宽泛，落到 legs/衣物近邻 |
| p-077-3 | 头发从发际线落下来 | bangs | — | 36444 | 30110 | receding_hairline, hair_spread_out, untying_hair, hair_tubes_removed, loose_hair_strand | receding_hairline, hair_flowing_over, fur-trimmed_hairband, hair_branch, hair_pulled_back | 头发局部关系被 forehead/hair 近邻抢走 |
| p-127-3 | 手掌贴在腰侧 | hand_on_hip | — | 36136 | 22335 | bandaid_on_neck, bandaid_on_hand, hand_on_another's_hip, heart-shaped_bandaid, bandaid_on_finger | hand_between_thighs, hand_on_belt, hand_on_another's_hip, hand_on_another's_waist, hands_on_lap | 手部位置关系缺少候选文档线索 |
| p-077-2 | 前额被一排头发遮住 | bangs | — | 35498 | 29764 | forehead_piercing, bandaid_on_forehead, hair_over_one_eye, scar_on_forehead, wiping_forehead | hair_over_face, hair_over_one_breast, hair_over_breasts, hair_behind_eyewear, hair_branch | 头发局部关系被 forehead/hair 近邻抢走 |
| p-033-2 | 袜子上方有袜带 | stockings | — | 34588 | 38903 | grey_garter_straps, legwear_garter, green_overalls, green_leggings, leg_belt | frilled_garter, holding_sock, legwear_garter, socks, wet_socks | 袜类层级与 garter/legwear 近邻 |
| p-072-3 | 双侧发束一起绑起 | double_ponytail | — | 34559 | 13958 | tail_belt, twintails_with_hair_base, bound_legs, single_hair_intake, one_side_up | multi-tied_hair, tied_to_pole, hair_behind_eyewear, bound_leg, bound_ankles | 头发局部关系被 forehead/hair 近邻抢走 |
| p-033-3 | 大腿袜配吊袜带 | stockings | — | 33758 | 36816 | leg_belt, gingham_legwear, o-ring_thigh_strap, red_garter_belt, white_leg_warmers | thighband_pantyhose, ankle_garter, studded_thigh_strap, white_garter_straps, o-ring_garter_belt | 袜类层级与 garter/legwear 近邻 |
| p-010-3 | 让衣摆向上卷起 | clothing_lift | — | 33727 | 19176 | sleeve_rolled_up, shirt_rolled_up, sleeves_rolled_up, rolling_sleeves_up, lifting_own_clothes | vibrator_over_clothes, upshirt, shirt_lift, lifting_own_clothes, lifting_another's_clothes | 人工复查：近邻 tag 或关系词信息不足 |
| p-010-1 | 把衣服往上掀露出腰 | clothing_lift | — | 33237 | 11580 | downpants, jumpsuit_around_waist, underwear_reveal_pose_(han-0v0), lifting_covers, vibrator_under_clothes | clothes_on_shoulders, clothes_around_waist, clothes_over_shoulder, clothes_lift, shirt_lift | 人工复查：近邻 tag 或关系词信息不足 |
| p-096-2 | 手掌撑着胯部 | hands_on_hips | — | 32839 | 21983 | glove_spread, hand_on_own_neck, hands_on_another's_crotch, hands_on_own_chest, crotch_rub | dorsiflexion_(wrist), hands_on_lap, hands_on_another's_crotch, crotch_rub, bursting_ass | 手部位置关系缺少候选文档线索 |
| p-033-1 | 穿吊带袜 | stockings | — | 32430 | 27412 | blue_garter_belt, white_garter, red_garter_belt, frilled_garter_belt, red_garter | bodystocking, pink_garter_straps, white_garter_straps, red_garter_straps, frilled_garter | 袜类层级与 garter/legwear 近邻 |
| p-097-3 | 正面看不到手掌 | hands_behind_back | — | 30441 | 7690 | blush_visible_through_hands, high-visibility_vest, v_over_eye, see-through_gloves, heart_hands_failure | looking_at_hand, blush_visible_through_hands, bad_hands, v_over_mouth, looking_at_hands | 手部位置关系缺少候选文档线索 |
| p-096-3 | 两只手放在腰侧 | hands_on_hips | — | 30309 | 12181 | hand_between_legs, two-handed, hand_on_another's_hip, hand_on_another's_thigh, hand_on_another's_leg | hand_between_thighs, hand_between_legs, hands_on_own_thighs, hands_on_lap, hands_on_another's_hips | 手部位置关系缺少候选文档线索 |
| p-096-1 | 双手叉在腰上 | hands_on_hips | — | 29758 | 7367 | hands_on_own_hips, hand_on_own_hip, hands_on_own_legs, hand_on_own_leg, hands_under_legs | hands_on_lap, hand_on_another's_hip, hands_on_another's_hips, hand_on_another's_waist, hand_on_belt | 手部位置关系缺少候选文档线索 |
| p-126-3 | 手臂绕到身后 | hand_behind_back | — | 28697 | 1141 | arms_behind_back, arm_around_chest, hands_on_own_back, arm_around_leg, arm_behind_back | arm_held_back, arm_behind_back, arms_behind_back, arm_around_back, arm_across_neck | 人工复查：近邻 tag 或关系词信息不足 |
| p-037-2 | 眼睛都没有睁开 | eyes_closed | — | 28313 | 9377 | unusually_open_eyes, sleeping_with_eyes_open, lowered_eyelids, opening_eyes, crying_with_eyes_open | blurry_vision, ;/, one_eye_closed, single_empty_eye, no_eyepatch | 人工复查：近邻 tag 或关系词信息不足 |
| p-037-3 | 睡着般合上双眼 | eyes_closed | — | 28175 | 22062 | mark_under_both_eyes, sleeping_with_eyes_open, white_pajamas, two-tone_pajamas, eyes_in_shadow | two-tone_pajamas, sleeping_upright, sleeping_with_eyes_open, frilled_pajamas, sleep_mask | 人工复查：近邻 tag 或关系词信息不足 |
| hard-013-5 | 不要把两只眼都画出来 | one_eye_visible | — | 27720 | 13364 | mark_under_both_eyes, drawn_on_eyes, single_blank_eye, multiple_style_parody, no_eyepatch | view_between_legs, blurry_vision, multiple_pov, one_eye_closed, two-tone_skin | 人工复查：近邻 tag 或关系词信息不足 |
| p-048-3 | 眼镜框清楚可见 | eyewear | — | 26698 | 34638 | eyes_visible_through_eyewear, eyewear_visible_through_hair, eyes_visible_through_headwear, orange-framed_eyewear, white-framed_eyewear | eyes_visible_through_eyewear, viewfinder, transparent_border, glowing_glasses, x-ray_glasses | 人工复查：近邻 tag 或关系词信息不足 |
| p-089-2 | 整个人平放在地面 | lying | 躺卧 | 24077 | 9594 | floor, hand_on_ground, equipment_layout, human_chair, hands_on_floor | focus_(horizon), through_ground, full_body, hands_on_ground, bikini_bottom_around_leg | 人工复查：近邻 tag 或关系词信息不足 |

## 13. Best Improvements

增强文档 B 的整体指标没有改善；为避免只报平均值，下面仍列出 20 个局部改善最大的样例（small B 或 base A 相对 small A）。这些是诊断案例，不是整体胜出结论。

| id | query | target | small A | small B | base A | best gain |
| --- | --- | --- | --- | --- | --- | --- |
| p-102-1 | 伸出食指和中指比出胜利手势 | v_sign | 43405 | 10206 | 24826 | 33199 |
| p-126-3 | 手臂绕到身后 | hand_behind_back | 28697 | 1150 | 1141 | 27556 |
| p-037-3 | 睡着般合上双眼 | eyes_closed | 28175 | 3190 | 22062 | 24985 |
| p-096-2 | 手掌撑着胯部 | hands_on_hips | 32839 | 8211 | 21983 | 24628 |
| p-072-3 | 双侧发束一起绑起 | double_ponytail | 34559 | 10103 | 13958 | 24456 |
| p-072-2 | 两条马尾对称垂下 | double_ponytail | 41132 | 28044 | 17313 | 23819 |
| p-096-1 | 双手叉在腰上 | hands_on_hips | 29758 | 6140 | 7367 | 23618 |
| p-010-1 | 把衣服往上掀露出腰 | clothing_lift | 33237 | 10031 | 11580 | 23206 |
| p-037-2 | 眼睛都没有睁开 | eyes_closed | 28313 | 5288 | 9377 | 23025 |
| p-097-3 | 正面看不到手掌 | hands_behind_back | 30441 | 13775 | 7690 | 22751 |
| p-072-1 | 左右各扎一束 | double_ponytail | 50022 | 28798 | 29601 | 21224 |
| p-127-2 | 单手扶住胯部 | hand_on_hip | 38556 | 18184 | 32638 | 20372 |
| p-077-3 | 头发从发际线落下来 | bangs | 36444 | 16206 | 30110 | 20238 |
| hard-015-4 | 不要只画一只手 | multiple_hands | 19745 | 1483 | 1993 | 18262 |
| p-127-3 | 手掌贴在腰侧 | hand_on_hip | 36136 | 17978 | 22335 | 18158 |
| p-096-3 | 两只手放在腰侧 | hands_on_hips | 30309 | 14623 | 12181 | 18128 |
| p-123-3 | 一只手不够 | multiple_hands | 22921 | 4947 | 11632 | 17974 |
| p-009-3 | 从脖子到上臂之间露出皮肤 | bare_shoulders | 18071 | 7220 | 790 | 17281 |
| hard-015-3 | 要看到两只手 | multiple_hands | 19722 | 2451 | 2736 | 17271 |
| p-010-3 | 让衣摆向上卷起 | clothing_lift | 33727 | 17071 | 19176 | 16656 |

## 14. Size and performance

| 模型 | 冷加载 median/P90/P95 (ms) | warm embedding median/P90/P95 (ms) | Top-50 similarity median/P90/P95 (ms) | 总查询 median/P90/P95 (ms) | RSS after load |
| --- | --- | --- | --- | --- | --- |
| E5-small | 831.52/880.62/882.98 | 3.38/3.58/3.65 | 7.11/7.58/7.95 | 10.62/10.99/11.06 | 874.45 MB |
| E5-base | 1047.29/1089.47/1100.44 | 7.88/8.45/8.81 | 9.74/10.18/10.54 | 17.33/18.21/18.30 | 1151.77 MB |

性能样本均为 30 次；冷加载每次新建 encoder，warm/相似度复用已加载 encoder 和 FP32 mmap 矩阵。RSS 是整个 benchmark 进程在相应模型阶段的近似工作集，不是 Android 进程承诺值。

## 15. Interpretation, limitations and recommendation

1. 这轮结果支持“纯 E5 相似度只能作为召回候选，不应单独决定最终词条”的判断。尤其是否定与数量，embedding 把语义主题相似误当成逻辑等价。
2. 文档 A 优于“无筛选 alias 拼接”的文档 B；下一阶段应评测字段加权/分字段编码、中文现有标签优先、冲突 pair 重排，而不是继续堆 alias。
3. 真正接入 Android 前，先建立人工标注的 unseen holdout，并把 Top-20 candidate recall、冲突前置率、P95 延迟和内存作为门槛。
4. 本轮样例来自普通词条；没有把作者/作品词条当作翻译目标，也没有为缺失中文标签调用任何翻译服务。
5. 生产代码当前没有 E5/embedding 语义路径；因此本报告不能证明 app 已上线语义搜索，也不应据此修改运行时默认行为。
6. paraphrase 是人工/规则策划的离线样例，不是 LLM 翻译结果；存在主题采样和措辞偏差。上一轮真实 holdout 原始 18 条、干净 17 条。
7. 英文只有 N=3、日文只有 N=1，不能据此比较跨语言能力；标准译文质量、缺失中文字段和候选文档长度都会影响结果。
8. 延迟与 RSS 是 Windows CPU benchmark，不能直接代表 Snapdragon 8 Gen 3 Android 性能；移动端还需单独测量 ONNX 后端和内存峰值。
9. Recommendation A：值得继续研究 semantic retrieval，但当前只适合作为 lexical fallback/候选扩展，不适合直接 Top-1 自动选 tag。
10. Recommendation B/C：先用 small + 文档 A、保留 semantic Top-20/40 供 UI 候选；base 不足以抵消本轮的体积、RSS 和延迟成本。
11. Recommendation D/E：上线前应加入否定/数量/方向 reranker，并补充人工标注的 500+ unseen holdout；暂不把未见中文语义结果写回生产词库。

复跑（不会启动应用）：

```powershell
& .\tool\.tmp\semantic-search\venv\Scripts\python.exe -B -u .\tool\semantic_search\semantic_paraphrase_benchmark.py --threads 4 --timeout 1200
& .\tool\.tmp\semantic-search\venv\Scripts\python.exe .\tool\semantic_search\render_semantic_paraphrase_report.py
```

## Appendix A. Full clean-case appendix

每行保留 ID、query、target、现有中文、来源/类型、small/base rank、词法 rank、冲突 tag 与两套模型的冲突 rank、small/base Top-5；`—` 表示词法未命中或没有冲突。

| id | query | target | 现有中文 | source | type | category | post_count | small A | small B | base A | base B | lexical | conflict | small conflict | base conflict | small Top-5 | base Top-5 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| p-001-1 | 衣服别塞进裙腰 | untucked_shirt | 衬衫下摆外露 | paraphrase | clothing | 0 | 2915 | 320 | 179 | 287 | 14 | — | — | — | — | jumpsuit_around_waist, sweater_tucked_in, hand_under_dress, shirt_tucked_in, clothes_around_waist | side-tie_skirt, clothes_between_thighs, side-tie_dress, clothes_between_breasts, tunic |
| p-001-2 | 让上衣自然垂在裤子外面 | untucked_shirt | 衬衫下摆外露 | paraphrase | clothing | 0 | 2915 | 305 | 322 | 347 | 10 | — | — | — | — | panties_around_one_leg, hand_in_pants, hand_in_another's_pants, dildo_under_panties, underwear_around_one_leg | vibrator_over_clothes, panties_over_clothes, pants_around_thighs, hand_under_clothes, handjob_over_clothes |
| p-001-3 | 上衣不要扎进腰里 | untucked_shirt | 衬衫下摆外露 | paraphrase | clothing | 0 | 2915 | 88 | 68 | 550 | 11 | — | — | — | — | sweater_tucked_in, jumpsuit_around_waist, head_under_another's_clothes, hand_under_clothes, sleeveless_tunic | bodysuit_under_clothes, sweater_tucked_in, no_bodystocking, used_condom_in_clothes, bandaid_on_clothes |
| p-002-1 | 把衣角收进裙腰 | shirt_tucked_in | 塞衣角 | paraphrase | clothing | 0 | 30535 | 2 | 15 | 62 | 1119 | — | — | — | — | hand_under_dress, shirt_tucked_in, hand_under_skirt, skirt_set, skirt_tied_over_head | side-tie_skirt, clothes_around_waist, side-tie_dress, tunic, hand_under_skirt |
| p-002-2 | 上衣边缘整齐塞进裤头 | shirt_tucked_in | 塞衣角 | paraphrase | clothing | 0 | 30535 | 57 | 181 | 449 | 2782 | — | — | — | — | pants_tucked_in, hand_in_pants, bodysuit_under_clothes, hand_in_own_panties, male_underwear_aside | hand_under_clothes, head_under_another's_clothes, cross-laced_top, pantyhose_under_pants, vibrator_over_clothes |
| p-002-3 | 衣服下摆全部收进去 | shirt_tucked_in | 塞衣角 | paraphrase | clothing | 0 | 30535 | 526 | 764 | 1094 | 3407 | — | — | — | — | clothes_on_shoulders, clothes_pull, clothing_aside, clothes_over_shoulder, untucked_shirt | clothes_on_shoulders, hand_under_clothes, shirttail, bikini_bottom_lift, clothes_pull |
| p-003-1 | 只把一侧衣角塞进去 | shirt_partially_tucked_in | 衬衫半扎 | paraphrase | clothing | 0 | 780 | 611 | 579 | 1754 | 6415 | — | — | — | — | shirt_tucked_in, single_sleeve_past_fingers, single_leg_warmer, single_detached_sleeve, sideless_dress | side-tie_bikini_bottom, side-tie_panties, side-tie_one-piece_swimsuit, bodystocking_only, side-tie_skirt |
| p-003-2 | 上衣前面半收半放 | shirt_partially_tucked_in | 衬衫半扎 | paraphrase | clothing | 0 | 780 | 5 | 6 | 275 | 739 | — | — | — | — | kimono_partially_removed, shirt_partially_removed, sweater_partially_tucked_in, coat_partially_removed, shirt_partially_tucked_in | front-tie_top, multi-strapped_bikini_top, hair_half_over_shoulder, front-tie_bikini_top, half-skirt |
| p-003-3 | 衣摆只收进去一小截 | shirt_partially_tucked_in | 衬衫半扎 | paraphrase | clothing | 0 | 780 | 87 | 307 | 2124 | 4657 | — | — | — | — | undersized_clothes, finger_under_clothes, untucked, partially_undressed, untucked_shirt | bodystocking_only, split_crop, layered_shorts, bikini_bottom_only, dress_pull |
| p-004-1 | 外套敞着露出里面 | open_shirt | 敞开的衬衫 | paraphrase | clothing | 0 | 116937 | 9 | 50 | 50 | 15 | — | — | — | — | open_coat, open_jacket, open_clothes, bra_visible_through_clothes, open_overalls | open_coat, open_clothes, open_jacket, open_onesie, covered_nipples |
| p-004-2 | 衬衫前襟打开别扣 | open_shirt | 敞开的衬衫 | paraphrase | clothing | 0 | 116937 | 2 | 2 | 98 | 11 | — | — | — | — | unbuttoned_shirt, open_shirt, shirttail, open_vest, open_leotard | flapper_shirt, unbuttoned_shirt, open_cardigan, shirt_on_shoulders, shirt_overhang |
| p-004-3 | 胸前留着敞开的衣襟 | open_shirt | 敞开的衬衫 | paraphrase | clothing | 0 | 116937 | 2 | 7 | 197 | 111 | — | — | — | — | open_bra, open_shirt, open-chest_sweater, open_clothes, clothes_between_breasts | flapper_shirt, open_bodysuit, bra_over_clothes, hair_over_breasts, panties_on_breasts |
| p-005-1 | 衬衫扣子解开几颗 | unbuttoned_shirt | 解开扣子的衬衫 | paraphrase | clothing | 0 | 5861 | 1 | 1 | 1 | 1 | — | — | — | — | unbuttoned_shirt, unbuttoned_sleeves, unbuttoning, shirt_partially_removed, unbuttoned | unbuttoned_shirt, unbuckled, flapper_shirt, fur-trimmed_cardigan, adjusting_shirt |
| p-005-2 | 不要把前襟扣严 | unbuttoned_shirt | 解开扣子的衬衫 | paraphrase | clothing | 0 | 5861 | 1 | 1 | 761 | 494 | — | — | — | — | unbuttoned_shirt, unbuttoned_sleeves, unworn_sleeves, no_leotard, no_headwear | vertical_foregrip, front-tie_top, front-tie_bra, angled_foregrip, front-hook_bra |
| p-005-3 | 让扣子处于解开的状态 | unbuttoned_shirt | 解开扣子的衬衫 | paraphrase | clothing | 0 | 5861 | 6 | 5 | 15 | 4 | — | — | — | — | unbuttoning, unbuttoned, unbuttoned_sleeves, unbuckled, standing_leg_lock | unbuckled, unbuttoned, unbuttoning, unbuttoned_jacket, unbuttoned_sleeves |
| p-006-1 | 手臂两边都露出来 | sleeveless | 无袖 | paraphrase | clothing | 0 | 426734 | 11419 | 6041 | 31048 | 7853 | — | — | — | — | breasts_out, arms_between_legs, arms_at_sides, arms_under_breasts, mark_under_both_eyes | arm_behind_back, arm_over_head, arm_on_thigh, arm_across_neck, asymmetrical_arms |
| p-006-2 | 上衣没有袖筒 | sleeveless | 无袖 | paraphrase | clothing | 0 | 426734 | 69 | 27 | 2666 | 199 | — | — | — | — | alternate_sleeve_length, unworn_sleeves, partially_undressed, no_detached_sleeves, sleeveless_coat | no_detached_sleeves, sleeveless_duster, crop_top_overhang, sleeveless_coat, sleeveless_tunic |
| p-006-3 | 肩膀到腋下不要有布料 | sleeveless | 无袖 | paraphrase | clothing | 0 | 426734 | 502 | 427 | 6936 | 1474 | — | — | — | — | carrying_under_arm, breastless_clothes, strapless_bodysuit, nippleless_clothes, arms_under_breasts | side-tie_bikini_bottom, no_bodystocking, bodystocking_only, bandaid_on_shoulder, bikini_bottom_around_leg |
| p-007-1 | 衣服滑到肩膀下面 | off_shoulder | 露肩 | paraphrase | clothing | 0 | 240729 | 3258 | 132 | 94 | 2644 | — | — | — | — | strap_slip, double_strap_slip, shirt_slip, clothes_on_shoulders, hang_gliding | clothes_over_shoulder, clothes_on_shoulders, clothes_between_thighs, strap_slip, breast_clinging |
| p-007-2 | 肩头露在衣领外 | off_shoulder | 露肩 | paraphrase | clothing | 0 | 240729 | 25 | 100 | 20 | 1911 | — | — | — | — | off-shoulder_shirt, off-shoulder_leotard, off-shoulder_coat, off-shoulder_jacket, off-shoulder_dress | clothes_over_shoulder, off-shoulder_shirt, clothes_on_shoulders, collared_shrug, necktie_between_pectorals |
| p-007-3 | 上衣领口挂在手臂上 | off_shoulder | 露肩 | paraphrase | clothing | 0 | 240729 | 6724 | 3567 | 724 | 7294 | — | — | — | — | hanging_on_arm, jacket_on_arm, bra_around_one_arm, umbrella_on_arm, arm_on_own_head | hands_on_headwear, arm_over_head, hair_tie_on_wrist, gym_shirt, hand_under_clothes |
| p-008-1 | 胸前没有肩带 | strapless | 无肩带 | paraphrase | clothing | 0 | 156110 | 6 | 1 | 2 | 7 | — | — | — | — | no_bra, breast_band, chest_strap, strapless_bra, unworn_bra | strapless_bra, strapless, chest_belt, neck_corset, bandaid_on_shoulder |
| p-008-2 | 这件衣服靠胸口固定没有吊带 | strapless | 无肩带 | paraphrase | clothing | 0 | 156110 | 5 | 3 | 369 | 460 | — | — | — | — | no_bra, unworn_bra, strapless_jumpsuit, strapless_bodysuit, strapless | clothes_between_breasts, breast_clinging, belt_bra, object_on_bulge, no_bodystocking |
| p-008-3 | 肩膀上别出现衣带 | strapless | 无肩带 | paraphrase | clothing | 0 | 156110 | 8 | 1 | 94 | 154 | — | — | — | — | dress_straps, shoulder_strap, double_strap_slip, shirt_straps, strap_slip | clothes_on_shoulders, bodysuit_aside, no_bodystocking, strapless_bodysuit, clothes_over_shoulder |
| p-009-1 | 两边肩膀都露着 | bare_shoulders | 露肩 | paraphrase | clothing | 0 | 974908 | 749 | 519 | 73 | 5602 | — | — | — | — | shoulder_blush, two-sided_scarf, two-handed_masturbation, bite_mark_on_shoulder, shoulder_cutout | legs_on_another's_shoulders, double_biceps_pose, hair_over_shoulder, two-tone_legwear, head_between_thighs |
| p-009-2 | 不要遮住肩头 | bare_shoulders | 露肩 | paraphrase | clothing | 0 | 974908 | 357 | 155 | 52 | 5726 | — | — | — | — | convenient_head, censored_nipples, no_u-turn_sign, no_headwear, censored_identity | covering_own_face, bandaid_on_shoulder, covering_navel, mask_on_shoulder, covering_ass |
| p-009-3 | 从脖子到上臂之间露出皮肤 | bare_shoulders | 露肩 | paraphrase | clothing | 0 | 974908 | 18071 | 7220 | 790 | 9028 | — | — | — | — | arms_around_neck, arm_across_neck, lipstick_mark_on_neck, arm_around_leg, goggles_around_arm | arm_across_neck, arm_over_head, arm_on_thigh, arms_under_breasts, thick_arm_hair |
| p-010-1 | 把衣服往上掀露出腰 | clothing_lift | — | paraphrase | clothing | 7 | 37717 | 33237 | 10031 | 11580 | 5288 | — | — | — | — | downpants, jumpsuit_around_waist, underwear_reveal_pose_(han-0v0), lifting_covers, vibrator_under_clothes | clothes_on_shoulders, clothes_around_waist, clothes_over_shoulder, clothes_lift, shirt_lift |
| p-010-2 | 上衣被撩到胸口以上 | clothing_lift | — | paraphrase | clothing | 7 | 37717 | 43052 | 27856 | 27208 | 18300 | — | — | — | — | clothes_between_breasts, extended_upshirt, hand_on_another's_chest, arm_around_chest, erection_under_clothes | breast_clinging, front-tie_top, clothes_over_shoulder, multi-strapped_bikini_top, front-tie_bikini_top |
| p-010-3 | 让衣摆向上卷起 | clothing_lift | — | paraphrase | clothing | 7 | 37717 | 33727 | 17071 | 19176 | 8249 | — | — | — | — | sleeve_rolled_up, shirt_rolled_up, sleeves_rolled_up, rolling_sleeves_up, lifting_own_clothes | vibrator_over_clothes, upshirt, shirt_lift, lifting_own_clothes, lifting_another's_clothes |
| p-011-1 | 用手把上衣往上扯 | shirt_pull | 拉下领口 | paraphrase | clothing | 0 | 8305 | 432 | 263 | 170 | 27 | — | — | — | — | putting_on_gloves, hand_on_headwear, hand_under_shirt, hands_on_headwear, hands_in_another's_pockets | hand_under_clothes, hand_under_shirt, finger_under_clothes, hand_in_clothes, upshirt |
| p-011-2 | 正在拉高衣服前襟 | shirt_pull | 拉下领口 | paraphrase | clothing | 0 | 8305 | 52 | 45 | 438 | 84 | — | — | — | — | top_pull, zipper_top, shirt_behind_neck, lace-up_top, clothes_pull | upshirt, shirt_lift, front-tie_top, clothes_over_shoulder, flapper_shirt |
| p-011-3 | 衣料被向上拽起 | shirt_pull | 拉下领口 | paraphrase | clothing | 0 | 8305 | 675 | 789 | 1402 | 479 | — | — | — | — | lifting_own_clothes, clothes_down, clothing_aside, head_under_another's_clothes, clothes_over_shoulder | upshirt, lifting_another's_clothes, lifting_own_clothes, sweater_vest_lift, pulling_own_clothes |
| p-012-1 | 衬衫穿在连衣裙外面 | shirt_over_dress | 裙外衬衫 | paraphrase | clothing | 0 | 52 | 1 | 6 | 2 | 45 | — | — | — | — | shirt_over_dress, shirt_under_dress, shirt_under_shirt, sweater_under_shirt, sideless_dress | overshirt, shirt_over_dress, layered_shirt, shirt_under_sweater, shirt_around_waist |
| p-012-2 | 外层是上衣内层是裙子 | shirt_over_dress | 裙外衬衫 | paraphrase | clothing | 0 | 52 | 10 | 30 | 18 | 946 | — | — | — | — | see-through_dress_layer, skirt_under_kimono, sweater_under_dress, shirt_under_dress, tail_under_clothes | torn_underwear, blue_tunic, vertical-striped_apron, panties_over_clothes, skirt_under_kimono |
| p-012-3 | 裙装外面再套一件衬衣 | shirt_over_dress | 裙外衬衫 | paraphrase | clothing | 0 | 52 | 1 | 3 | 1 | 95 | — | — | — | — | shirt_over_dress, shirt_under_dress, slip_showing, skirt_set, dress_slip | shirt_over_dress, overshirt, side-tie_skirt, flapper_shirt, shirt_aside |
| p-013-1 | 毛衣外面露出衬衫领子 | shirt_under_sweater | 毛衣内穿衬衫 | paraphrase | clothing | 0 | 319 | 1 | 2 | 6 | 6 | — | — | — | — | shirt_under_sweater, sweater_under_shirt, head_under_another's_clothes, see-through_hoodie, fur-trimmed_shirt | overshirt, shirt_tan, collared_shrug, slip_showing, frilled_shirt_collar |
| p-013-2 | 衬衣穿在针织衫里面 | shirt_under_sweater | 毛衣内穿衬衫 | paraphrase | clothing | 0 | 319 | 10 | 12 | 1 | 3 | — | — | — | — | shirt_on_shoulders, shirt_around_waist, shirt_under_shirt, sweater_under_shirt, see-through_shirt | shirt_under_sweater, sweater_under_shirt, layered_shirt, shirt_under_shirt, overshirt |
| p-013-3 | 领口下能看到内搭上衣 | shirt_under_sweater | 毛衣内穿衬衫 | paraphrase | clothing | 0 | 319 | 113 | 164 | 108 | 318 | — | — | — | — | see-through_hoodie, head_under_another's_clothes, male_underwear_peek, bra_visible_through_clothes, holding_underwear | bodysuit_under_clothes, front-tie_top, open_leotard, goggles_on_headwear, see-through_bodysuit |
| p-014-1 | 穿一件轻薄的女式上衣 | blouse | 女衬衫 | paraphrase | clothing | 0 | 45771 | 59 | 152 | 1295 | 1468 | — | — | — | — | microdress, undersized_clothes, medium_dress, pinstripe_dress, white_negligee | multi-strapped_bikini_top, high-low_dress, tunic, two-tone_bodysuit, red_crop_top |
| p-014-2 | 上身是有领的布料 | blouse | 女衬衫 | paraphrase | clothing | 0 | 45771 | 2193 | 3612 | 11009 | 11101 | — | — | — | — | holding_cloth, collared_bodysuit, collared_jumpsuit, holding_legwear, hand_on_headwear | front-tie_top, bandaid_on_clothes, turtleneck_leotard, turtleneck_bodysuit, turtleneck_dress |
| p-014-3 | 不要换成普通T恤 | blouse | 女衬衫 | paraphrase | clothing | 0 | 45771 | 6524 | 8070 | 8558 | 12180 | — | — | — | — | ringer_t-shirt, impossible_shirt, shirt_tan, no_cardigan, fuck-me_shirt | alternate_costume, alternate_uniform, group_costume_switch, change_in_common_sense, alternate_headwear |
| p-015-1 | 学校制服风格 | school_uniform | 校服 | paraphrase | clothing | 0 | 791599 | 21 | 24 | 20 | 1602 | — | — | — | — | royal_officer_academy_school_uniform, miyamasuzaka_girls'_academy_school_uniform, mahora_academy_middle_school_uniform, sanshuu_middle_school_uniform, hoshinomiya_girls'_high_school_uniform | a_certain_high_school_uniform, u.a._school_uniform, tohmi_higashi_high_school_uniform, shuuchiin_academy_school_uniform, shuka_high_school_uniform |
| p-015-3 | 校园制服搭配 | school_uniform | 校服 | paraphrase | clothing | 0 | 791599 | 140 | 79 | 47 | 2550 | — | — | — | — | sanshuu_middle_school_uniform, royal_officer_academy_school_uniform, miyamasuzaka_girls'_academy_school_uniform, chuo_academy_school_uniform, yotsuboshi_academy_school_uniform | kazamatsuri_institute_high_school_uniform, tohmi_higashi_high_school_uniform, u.a._school_uniform, a_certain_high_school_uniform, fourth_east_high_school_uniform |
| p-016-1 | 穿着制式服装 | uniform | 制服 | paraphrase | clothing | 7 | 56982 | 57 | 174 | 116 | 316 | — | — | — | — | dressing, traditional_dress, contemporary_traditional_clothes, chinese_clothes, french_clothes | traditional_dress, dress-up, costume, figure_skating_dress, tight_clothes |
| p-016-3 | 服装看起来属于同一套 | uniform | 制服 | paraphrase | clothing | 7 | 56982 | 498 | 680 | 87 | 387 | — | — | — | — | asymmetrical_clothes, asymmetrical_dress, asymmetrical_shirt, asymmetrical_coat, asymmetrical_legwear | outfit_connection, idol_clothes, clothes_on_shoulders, dress, shared_clothes |
| p-017-1 | 外面披一件短外套 | jacket | 夹克 | paraphrase | clothing | 0 | 933908 | 1193 | 2890 | 3136 | 1897 | — | — | — | — | puffy_short_sleeves, short-sleeved_jacket, pelisse, collared_shrug, short-sleeved_sweater | shorts_aside, layered_shorts, cropped_cardigan, collared_shrug, shorts_around_ankles |
| p-017-3 | 肩膀上有外套 | jacket | 夹克 | paraphrase | clothing | 0 | 933908 | 2230 | 4970 | 4217 | 3186 | — | — | — | — | shoulder_blush, jacket_on_arm, clothes_over_shoulder, clothes_on_shoulders, jacket_over_head | clothes_over_shoulder, clothes_on_shoulders, jacket_on_arm, jacket_over_shoulder, hair_over_shoulder |
| p-018-1 | 里面衬衫外面套针织开衫 | cardigan | 开襟衫 | paraphrase | clothing | 0 | 80096 | 800 | 529 | 121 | 14 | — | — | — | — | shirt_around_waist, sweater_jacket, overshirt, fur-lined_gloves, untucked_shirt | flapper_shirt, fur-trimmed_cardigan, layered_shirt, shirt_under_sweater, open_cardigan |
| p-018-2 | 纽扣针织外衣 | cardigan | 开襟衫 | paraphrase | clothing | 0 | 80096 | 3405 | 2362 | 1659 | 554 | — | — | — | — | knitting_needle, unbuttoned_dress, knit_sweater, knit_hat, sweater_jacket | button_hair_ornament, blue_tunic, underwear, tunic, bralette |
| p-018-3 | 软绵绵的开襟毛衣 | cardigan | 开襟衫 | paraphrase | clothing | 0 | 80096 | 64 | 15 | 280 | 33 | — | — | — | — | sleeveless_sweater, gradient_sweater, fluffy_legwear, green_sweater, brown_bonnet | sweater_around_waist, blue_tunic, open_leotard, shirt_under_sweater, taut_sweater |
| p-019-1 | 戴着连帽上衣 | hoodie | 连帽衫 | paraphrase | clothing | 0 | 132620 | 10 | 150 | 264 | 7252 | — | — | — | — | headwear_with_attached_mittens, hooded_coat, hooded_dress, hat_belt, hat_on_chest | jacket_over_hoodie, hooded_bodysuit, cross-laced_top, hooded_robe, multi-strapped_bikini_top |
| p-019-2 | 头后有帽兜 | hoodie | 连帽衫 | paraphrase | clothing | 0 | 132620 | 826 | 3024 | 1125 | 18891 | — | — | — | — | torn_hood, hair_through_hood, animal_ear_hood, chaperon_hat, sheep_hood | kabuto_(helmet), hat_on_back, horns_through_hood, chaperon_hat, hair_behind_eyewear |
| p-019-3 | 穿宽松卫衣 | hoodie | 连帽衫 | paraphrase | clothing | 0 | 132620 | 2874 | 14828 | 5857 | 26248 | — | — | — | — | baggy_clothes, loose_clothes, baggy_pants, loose_pants, crop_top_overhang | crop_top_overhang, loose_skirt, loose_pants, baggy_clothes, vertical-striped_corset |
| p-020-1 | 冬天穿厚外套 | coat | 大衣 | paraphrase | clothing | 0 | 225416 | 10923 | 9947 | 2347 | 5535 | — | — | — | — | winter_coat, winter_gloves, snow_on_headwear, winter_clothes, holding_holly | winter_coat, winter_clothes, winter_uniform, coat_on_shoulders, long_coat |
| p-020-2 | 长款保暖外衣 | coat | 大衣 | paraphrase | clothing | 0 | 225416 | 16059 | 14879 | 1566 | 5226 | — | — | — | — | long_shirt, duster_coat, long_coat, white_pants, pants | tunic, blue_tunic, pink_tunic, two-tone_arm_warmers, duster_coat |
| p-021-1 | 脚踝到脚趾都不套袜子 | no_socks | 未穿袜 | paraphrase | legwear | 0 | 6326 | 5 | 23 | 150 | 564 | — | — | — | — | panties_around_one_ankle, unworn_kneehighs, unworn_legwear, no_toes, no_socks | pants_around_ankles, velcro_footwear, mismatched_thighhighs, bound_ankles, sock_on_penis |
| p-021-2 | 腿上别出现袜类 | no_socks | 未穿袜 | paraphrase | legwear | 0 | 6326 | 123 | 280 | 62 | 744 | — | — | — | — | leg_belt, unworn_legwear, uneven_legwear, mismatched_legwear, brown_leg_warmers | mismatched_thighhighs, unworn_thighhighs, thighhigh_dangle, bikini_bottom_around_leg, unworn_legwear |
| p-021-3 | 把袜子去掉后露出脚 | no_socks | 未穿袜 | paraphrase | legwear | 0 | 6326 | 34 | 118 | 774 | 6337 | — | — | — | — | single_sock_removed, downpants, unworn_socks, pulling_off_legwear, stirrup_footwear | pulling_off_legwear, holding_sock, hand_in_thighhighs, loose_thighhigh, sock_pull |
| p-022-2 | 小腿下面有袜筒 | socks | 袜子 | paraphrase | legwear | 0 | 383345 | 377 | 171 | 175 | 2529 | — | — | — | — | pants_around_one_leg, underwear_around_one_leg, putting_on_legwear, leg_cutout, gingham_legwear | cum_on_legwear, tube_socks, pantyhose_around_legs, vibrator_under_pantyhose, thighhighs_under_boots |
| p-022-3 | 不要让脚是光的 | socks | 袜子 | paraphrase | legwear | 0 | 383345 | 9744 | 5652 | 6229 | 6017 | — | — | — | — | censored_feet, light-skinned_soles, no_toes, unworn_sandals, feet_out_of_frame | censored_feet, blood_on_feet, foot_focus, ankle_ring, view_between_legs |
| p-023-1 | 袜子脱下来放一边 | unworn_socks | 未穿的袜子 | paraphrase | legwear | 0 | 2018 | 70 | 21 | 441 | 25 | — | — | — | — | pulling_off_legwear, single_sock_removed, green_leggings, pants_around_one_leg, pants_pull | single_sock_removed, sock_pull, removing_sock, holding_sock, adjusting_sock |
| p-023-2 | 脚边有脱下的袜子 | unworn_socks | 未穿的袜子 | paraphrase | legwear | 0 | 2018 | 10 | 6 | 177 | 137 | — | — | — | — | single_sock_removed, foot_dangle, thighhigh_dangle, legwear_cutout, unworn_shoes | thighhigh_dangle, torn_thighhighs, mismatched_thighhighs, loose_thighhigh, single_sock_removed |
| p-023-3 | 手里拿着刚脱下的袜子 | unworn_socks | 未穿的袜子 | paraphrase | legwear | 0 | 2018 | 8 | 14 | 82 | 58 | — | — | — | — | thighhigh_dangle, pulling_off_legwear, legwear_cutout, single_sock_removed, overalls_removed | holding_sock, thighhigh_dangle, single_sock_removed, pulling_off_legwear, hand_under_clothes |
| p-024-1 | 光脚踩在地上 | barefoot | 赤脚 | paraphrase | legwear | 0 | 370744 | 1199 | 9637 | 5129 | 22094 | — | — | — | — | foot_on_weapon, foot_on_arm, foot_on_head, stirrup_legwear, land_striker | land_striker, foot_on_weapon, blood_on_feet, food_on_foot, head_on_ground |
| p-024-2 | 脚底直接接触地面 | barefoot | 赤脚 | paraphrase | legwear | 0 | 370744 | 401 | 8170 | 5913 | 18188 | — | — | — | — | soles_together, light-skinned_soles, bandaid_on_foot, from_ground, feet_against_wall | bikini_bottom_around_leg, through_ground, food_on_foot, blood_on_feet, hand_in_thighhighs |
| p-024-3 | 双脚没有鞋也没有袜 | barefoot | 赤脚 | paraphrase | legwear | 0 | 370744 | 808 | 1763 | 1586 | 12431 | — | — | — | — | no_socks, disembodied_legs, uneven_footwear, unworn_kneehighs, unworn_socks | disembodied_legs, mismatched_thighhighs, mismatched_socks, thighhigh_dangle, velcro_footwear |
| p-025-1 | 鞋子脱掉 | no_shoes | 未穿鞋 | paraphrase | legwear | 0 | 92856 | 135 | 77 | 571 | 6129 | — | — | — | — | removing_shoes, shoe_loss, unworn_shoes, removing_coat, dirty_footwear | removing_shoes, removing_sock, single_sock_removed, shoe_loss, overalls_removed |
| p-025-2 | 脚边没有鞋 | no_shoes | 未穿鞋 | paraphrase | legwear | 0 | 92856 | 3 | 2 | 13 | 75 | — | — | — | — | uneven_footwear, no_toes, no_shoes, unworn_sandals, unworn_shoes | censored_feet, bad_leg, heel_pop, disembodied_legs, uneven_footwear |
| p-025-3 | 只露出没有鞋子的双脚 | no_shoes | 未穿鞋 | paraphrase | legwear | 0 | 92856 | 17 | 18 | 74 | 362 | — | — | — | — | uneven_footwear, soles_together, two-footed_footjob, feet_against_wall, single_bare_foot | disembodied_legs, censored_feet, unworn_thighhighs, single_bare_leg, single_thighhigh |
| p-026-1 | 脚上穿鞋 | shoes | 鞋子 | paraphrase | legwear | 0 | 415943 | 118 | 144 | 55 | 438 | — | — | — | — | putting_on_footwear, chocolate_on_foot, blood_on_shoes, alternate_footwear, barefoot_sandals_(jewelry) | putting_on_footwear, footwear_on_head, lace-up_heels, heel_pop, holding_shoes |
| p-026-2 | 双脚被鞋包住 | shoes | 鞋子 | paraphrase | legwear | 0 | 415943 | 245 | 181 | 236 | 1695 | — | — | — | — | two-footed_footjob, feet_against_wall, foot_dangle, soles_together, feet_on_chair | clawed_boots, legs_on_another's_shoulders, holding_shoes, double_footjob, bound_ankles |
| p-026-3 | 不要让脚是光的 | shoes | 鞋子 | paraphrase | legwear | 0 | 415943 | 6915 | 5412 | 12904 | 29559 | — | — | — | — | censored_feet, light-skinned_soles, no_toes, feet_out_of_frame, bandaid_on_foot | censored_feet, blood_on_feet, putting_in_contact_lens, foot_blush, visor_lift |
| p-027-2 | 鞋带绕着脚背 | sandals | 凉鞋 | paraphrase | legwear | 0 | 93922 | 354 | 2263 | 947 | 2916 | — | — | — | — | alternate_footwear, putting_on_footwear, boot_straps, heel_pop, pointed_footwear | footwear_on_head, heel_pop, lace-up_heels, thighhighs_under_boots, ankle_garter |
| p-028-1 | 脚后跟被高高抬起 | high_heels | 高跟鞋 | paraphrase | legwear | 0 | 199327 | 4 | 56 | 13 | 7019 | — | — | — | — | heel_up, high_heel_boots, foot_up, high_heels, slingback_heels | heel_up, legs_back, feet_up, legs_up, foot_up |
| p-028-3 | 鞋跟细长 | high_heels | 高跟鞋 | paraphrase | legwear | 0 | 199327 | 3 | 15 | 7 | 12232 | — | — | — | — | stiletto_heels, high_heel_boots, high_heels, uneven_footwear, oversized_footwear | high_heel_sneakers, stiletto_heels, block_heels, thigh_boots, large_shoes |
| p-029-2 | 穿休闲跑鞋 | sneakers | 运动鞋 | paraphrase | legwear | 0 | 65007 | 2 | 53 | 2 | 1481 | — | — | — | — | putting_on_footwear, sneakers, zipper_footwear, sports_car, see-through_footwear | high_heel_sneakers, sneakers, green_track_suit, track_suit, black_track_suit |
| p-029-3 | 鞋底厚实的球鞋 | sneakers | 运动鞋 | paraphrase | legwear | 0 | 65007 | 10 | 275 | 21 | 404 | — | — | — | — | flats, platform_shoes, platform_boots, paw_print_soles, platform_sandals | high_heel_sneakers, platform_sandals, high_tops, platform_heels, platform_shoes |
| p-030-2 | 鞋筒高过脚踝 | boots | 靴子 | paraphrase | legwear | 0 | 455370 | 1712 | 1756 | 434 | 5662 | — | — | — | — | high_heel_sandals, high_tops, high_heel_boots, chocolate_on_foot, high_heels | thigh_boots, platform_heels, pants_around_ankles, long_fall_boots, high_heel_sneakers |
| p-030-3 | 穿长靴出场 | boots | 靴子 | paraphrase | legwear | 0 | 455370 | 265 | 654 | 64 | 1228 | — | — | — | — | clawed_boots, thigh_boots, long_sleeves, long_legs, uneven_sleeves | thigh_boots, high_heel_sneakers, clawed_boots, putting_on_footwear, high_heels |
| p-031-1 | 长筒袜一直到大腿 | thighhighs | 过膝袜 | paraphrase | legwear | 0 | 1166845 | 299 | 779 | 6 | 9078 | — | — | — | — | long_legs, white_leg_warmers, putting_on_legwear, wide_spread_legs, gingham_legwear | thighband_pantyhose, torn_bodystocking, white_thighhighs, gradient_thighhighs, thighhigh_dangle |
| p-031-2 | 袜口停在大腿根 | thighhighs | 过膝袜 | paraphrase | legwear | 0 | 1166845 | 189 | 375 | 53 | 11945 | — | — | — | — | hanging_legs, see-through_thighhighs, wide_spread_legs, over-kneehighs, severed_leg | torn_bodystocking, bikini_bottom_around_leg, thighhigh_dangle, neck_garter, loose_thighhigh |
| p-031-3 | 大腿上有高筒袜带 | thighhighs | 过膝袜 | paraphrase | legwear | 0 | 1166845 | 476 | 669 | 152 | 14127 | — | — | — | — | leg_belt, leg_ribbon, gingham_legwear, putting_on_legwear, leg_cutout | thighband_pantyhose, frilled_garter, ankle_garter, elbow_gloves, legwear_garter |
| p-032-2 | 腿部被薄丝袜包住 | pantyhose | 连裤袜 | paraphrase | legwear | 0 | 528923 | 5845 | 2016 | 606 | 1250 | — | — | — | — | leg_spikes, leg_ribbon, bandaid_on_leg, scar_on_leg, striped_leg_warmers | torn_bodystocking, ribbon-trimmed_thighhighs, pantyhose_around_legs, bodystocking, camouflage_legwear |
| p-032-3 | 从脚一直连到腹部 | pantyhose | 连裤袜 | paraphrase | legwear | 0 | 528923 | 5873 | 4454 | 2522 | 2148 | — | — | — | — | panties_around_one_ankle, bandaid_on_stomach, arm_around_chest, arm_around_leg, scar_on_stomach | food_on_foot, neck_corset, bound_ankles, thigh_bands, ankle_ring |
| p-033-1 | 穿吊带袜 | stockings | — | paraphrase | legwear | 7 | 111788 | 32430 | 42153 | 27412 | 43787 | — | — | — | — | blue_garter_belt, white_garter, red_garter_belt, frilled_garter_belt, red_garter | bodystocking, pink_garter_straps, white_garter_straps, red_garter_straps, frilled_garter |
| p-033-2 | 袜子上方有袜带 | stockings | — | paraphrase | legwear | 7 | 111788 | 34588 | 46077 | 38903 | 43837 | — | — | — | — | grey_garter_straps, legwear_garter, green_overalls, green_leggings, leg_belt | frilled_garter, holding_sock, legwear_garter, socks, wet_socks |
| p-033-3 | 大腿袜配吊袜带 | stockings | — | paraphrase | legwear | 7 | 111788 | 33758 | 45455 | 36816 | 44248 | — | — | — | — | leg_belt, gingham_legwear, o-ring_thigh_strap, red_garter_belt, white_leg_warmers | thighband_pantyhose, ankle_garter, studded_thigh_strap, white_garter_straps, o-ring_garter_belt |
| p-034-1 | 双腿套着贴身打底裤 | leggings | 紧身裤 | paraphrase | legwear | 0 | 15032 | 168 | 828 | 373 | 544 | — | — | — | — | striped_leggings, two-tone_legwear, green_leggings, black_leggings, vertical-striped_leggings | leggings_under_shorts, brown_leggings, vertical-striped_leggings, thighband_pantyhose, layered_shorts |
| p-034-3 | 裤子像第二层皮肤 | leggings | 紧身裤 | paraphrase | legwear | 0 | 15032 | 591 | 2349 | 2981 | 2118 | — | — | — | — | two-tone_skin, two-tone_pants, two-tone_legwear, two-tone_pantyhose, double_flare_skirt_one-piece | downpants, two-tone_skin, two-tone_pantyhose, two-tone_legwear, two-tone_jacket |
| p-035-1 | 腿上有专门的袜裤类服饰 | legwear | — | paraphrase | legwear | 7 | 308527 | 3097 | 4107 | 10465 | 17727 | — | — | — | — | gingham_legwear, silver_legwear, underwear_around_one_leg, single_leg_bodysuit, single_pantsleg | cross-laced_legwear, patterned_legwear, studded_legwear, cum_on_legwear, side-tie_legwear |
| p-035-2 | 下半身穿腿部服装 | legwear | — | paraphrase | legwear | 7 | 308527 | 8456 | 5957 | 8998 | 16781 | — | — | — | — | layered_legwear, half-shirt, lower_body, half-dress, legs | gradient_legwear, legwear_cutout, high-low_dress, layered_legwear, camouflage_legwear |
| p-035-3 | 腿部被织物覆盖 | legwear | — | paraphrase | legwear | 7 | 308527 | 23223 | 9070 | 19191 | 22155 | — | — | — | — | legwear_cutout, leg_cutout, clothes_between_thighs, layered_legwear, stitched_leg | camouflage_legwear, patterned_legwear, legwear_cutout, layered_legwear, clothes_between_thighs |
| p-036-1 | 双眼完全合拢 | closed_eyes | 闭眼 | paraphrase | eyes | 0 | 706552 | 983 | 1152 | 711 | 1129 | — | — | — | — | thighs_together, legs_together, mark_under_both_eyes, knees_apart_feet_together, implied_double_penetration | legs_together, thighs_together, compound_eyes, knees_apart_feet_together, asymmetrical_eyes |
| p-036-2 | 眼皮盖住两只眼 | closed_eyes | 闭眼 | paraphrase | eyes | 0 | 706552 | 153 | 221 | 641 | 2958 | — | — | — | — | mark_under_both_eyes, covering_another's_eye, two-tone_gloves, veil_over_one_eye, two-tone_skin | double_eyepatch, bandages_over_eyes, covering_another's_eye, eye_glitter, gauze_over_eye |
| p-036-3 | 看不见眼珠 | closed_eyes | 闭眼 | paraphrase | eyes | 0 | 706552 | 248 | 324 | 254 | 804 | — | — | — | — | unworn_blindfold, googly_eyes, unworn_eyewear, no_blindfold, no_eyewear | blurry_vision, no_goggles, no_pupils, no_eyepatch, no_eyes |
| p-037-1 | 两只眼一起闭着 | eyes_closed | — | paraphrase | eyes | 7 | 353257 | 16697 | 1427 | 9746 | 6723 | — | — | — | — | one_eye_closed, third_eye_closed, closing_eyes, closed_eyes, ^_^ | one_eye_closed, ;/, blurry_vision, closing_eyes, closed_eyes |
| p-037-2 | 眼睛都没有睁开 | eyes_closed | — | paraphrase | eyes | 7 | 353257 | 28313 | 5288 | 9377 | 15714 | — | — | — | — | unusually_open_eyes, sleeping_with_eyes_open, lowered_eyelids, opening_eyes, crying_with_eyes_open | blurry_vision, ;/, one_eye_closed, single_empty_eye, no_eyepatch |
| p-037-3 | 睡着般合上双眼 | eyes_closed | — | paraphrase | eyes | 7 | 353257 | 28175 | 3190 | 22062 | 21717 | — | — | — | — | mark_under_both_eyes, sleeping_with_eyes_open, white_pajamas, two-tone_pajamas, eyes_in_shadow | two-tone_pajamas, sleeping_upright, sleeping_with_eyes_open, frilled_pajamas, sleep_mask |
| p-038-1 | 只合上一边眼皮 | one_eye_closed | 单眼闭合 | paraphrase | eyes | 0 | 431971 | 2 | 17 | 89 | 10206 | — | — | — | — | lower_lip_only, one_eye_closed, lower_eyelashes_only, covering_one_eye, covering_one_nipple | bandage_over_one_eye, side-tie_peek, putting_in_contact_lens, hair_behind_eyewear, finger_on_eyewear |
| p-038-2 | 一边睁一边闭 | one_eye_closed | 单眼闭合 | paraphrase | eyes | 0 | 431971 | 3 | 6 | 1 | 1579 | — | — | — | — | unusually_open_eyes, closing, one_eye_closed, crying_with_eyes_open, ^_^ | one_eye_closed, view_between_legs, ;/, closing, closing_eyes |
| p-038-3 | 单边眨眼 | one_eye_closed | 单眼闭合 | paraphrase | eyes | 0 | 431971 | 1 | 18 | 7 | 3251 | — | — | — | — | one_eye_closed, one_eye_covered, single_blank_eye, hair_over_one_eye, winking_(animated) | monocular, single_earring, solo_focus, ;/, single_blank_eye |
| p-039-1 | 眼皮只垂下一半 | half-closed_eyes | 半闭眼 | paraphrase | eyes | 0 | 94517 | 1 | 14 | 4 | 4340 | — | — | — | — | half-closed_eyes, half-closed_eye, lowered_eyelids, half_gloves, single_half_glove | lower_eyelashes_only, over-rim_eyewear, hair_between_eyes, half-closed_eyes, scar_across_eyes |
| p-039-2 | 眼睛半睁半闭 | half-closed_eyes | 半闭眼 | paraphrase | eyes | 0 | 94517 | 1 | 6 | 1 | 164 | — | — | — | — | half-closed_eyes, half-closed_eye, lowered_eyelids, unusually_open_eyes, third_eye_closed | half-closed_eyes, half-closed_eye, one_eye_closed, ;/, lowered_eyelids |
| p-039-3 | 像困得睁不开 | half-closed_eyes | 半闭眼 | paraphrase | eyes | 0 | 94517 | 201 | 698 | 162 | 24146 | — | — | — | — | unusually_open_eyes, crying_with_eyes_open, lowered_eyelids, sleepy, undone_neckerchief | unusually_open_eyes, ;/, blurry_vision, no_one's_around_to_help_(meme), no_horny_(meme) |
| p-040-1 | 双眼睁得明显 | opening_eyes | 睁眼 | paraphrase | eyes | 0 | 229 | 9 | 6 | 28 | 120 | — | — | — | — | unusually_open_eyes, lowered_eyelids, mark_under_both_eyes, one_eye_closed, eyes_in_shadow | eyes_in_shadow, eyes_visible_through_eyewear, blush_visible_through_hair, looking_over_eyewear, looking_at_bulge |
| p-040-2 | 眼珠完整露出 | opening_eyes | 睁眼 | paraphrase | eyes | 0 | 229 | 723 | 998 | 353 | 431 | — | — | — | — | googly_eyes, eyebrows_visible_through_headband, eyebrows_visible_through_mask, eyewear_visible_through_hair, eyes_visible_through_hair | full_cleavage, full-body_blush, googly_eyes, full-length_mirror, full-body_tattoo |
| p-040-3 | 眼皮完全打开 | opening_eyes | 睁眼 | paraphrase | eyes | 0 | 229 | 13 | 6 | 25 | 55 | — | — | — | — | unusually_open_eyes, half-closed_eye, half-closed_eyes, veil_over_one_eye, eyes_out_of_frame | penis_in_eye, partially_open_jacket, one_eye_closed, penis_over_one_eye, finger_on_eyewear |
| p-041-1 | 视线直直对着画面 | looking_at_viewer | 看向观众 | paraphrase | eyes | 0 | 3315722 | 61 | 254 | 73 | 433 | — | — | — | — | vertical_eye_lines, rotating_view, averting_eyes, vertical_monitor, running_towards_viewer | facing_back, rotating_view, visor_lift, from_below, running_towards_viewer |
| p-041-2 | 正在看镜头 | looking_at_viewer | 看向观众 | paraphrase | eyes | 0 | 3315722 | 36 | 21 | 2 | 93 | — | — | — | — | grabbing_viewer, running_towards_viewer, walking_towards_viewer, watching, staring | watching, looking_at_viewer, facing_back, staring, looking_at_screen |
| p-041-3 | 和观看者对视 | looking_at_viewer | 看向观众 | paraphrase | eyes | 0 | 3315722 | 2 | 1 | 1 | 57 | — | — | — | — | watching, looking_at_viewer, eye_contact, viewer_holding_leash, reaching_towards_viewer | looking_at_viewer, eye_contact, looking_past_viewer, pointing_at_viewer, glance |
| p-042-1 | 目光故意避开镜头 | looking_away | 看向别处 | paraphrase | eyes | 7 | 27688 | 2022 | 5053 | 265 | 969 | — | — | — | — | lens_eye, detached_eyes, averting_eyes, holding_removed_eyewear, blocked_senses | blurry_vision, averting_eyes, pov_cheek_grabbing_(meme), ;/, blank_stare |
| p-042-3 | 视线飘到旁边 | looking_away | 看向别处 | paraphrase | eyes | 7 | 27688 | 379 | 1210 | 107 | 1581 | — | — | — | — | vertical_eye_lines, averting_eyes, running_towards_viewer, rear-view_mirror, v_over_eye | from_below, from_behind, from_side, visor_lift, stomping_viewer |
| p-043-1 | 脸不转但眼睛往侧面瞟 | looking_to_the_side | 侧视 | paraphrase | eyes | 0 | 178749 | 3 | 32 | 52 | 391 | — | — | — | — | from_side, facing_to_the_side, looking_to_the_side, finger_to_face, shading_face | from_side, gradient_eyes, profile, compound_eyes, facing_back |
| p-043-2 | 目光落在画面一边 | looking_to_the_side | 侧视 | paraphrase | eyes | 0 | 178749 | 74 | 645 | 4 | 73 | — | — | — | — | drawn_on_eyes, eyes_out_of_frame, covered_eyes, facing_back, averting_eyes | from_side, looking_inside, looking_away, looking_to_the_side, facing_back |
| p-043-3 | 眼神向左或右偏 | looking_to_the_side | 侧视 | paraphrase | eyes | 0 | 178749 | 98 | 862 | 483 | 2235 | — | — | — | — | v_over_eye, vertical_eye_lines, creepy_eyes, hollow_eyes, vision_(genshin_impact) | view_between_legs, scar_across_eyes, eye_twitch, w_over_eye, vertical_eye_lines |
| p-044-1 | 两只眼珠向鼻梁靠拢 | cross-eyed | 斗鸡眼 | paraphrase | eyes | 0 | 959 | 71 | 433 | 1195 | 14930 | — | — | — | — | bandaid_on_nose, googly_eyes, bridge_piercing, neck_bell, noses_touching | bandaid_on_nose, septum_piercing, looking_at_bulge, navel_focus, view_between_legs |
| p-044-3 | 视线在中间交叉 | cross-eyed | 斗鸡眼 | paraphrase | eyes | 0 | 959 | 290 | 233 | 306 | 4966 | — | — | — | — | cross-laced_collar, vertical_eye_lines, cross_in_eye, pov_across_table, running_towards_viewer | pov_across_bed, view_between_legs, rotating_view, compound_eyes, semi-circular_eyewear |
| p-045-1 | 眼睛里没有高光和神采 | empty_eyes | 空洞眼神 | paraphrase | eyes | 0 | 33336 | 56 | 10 | 111 | 3336 | — | — | — | — | single_blank_eye, no_heterochromia, eye_on_hat, hat_over_one_eye, hollow_eyes | no_heterochromia, blurry_vision, mismatched_sclera, mismatched_eyebrows, shiny_and_normal |
| p-045-2 | 瞳孔像空掉一样 | empty_eyes | 空洞眼神 | paraphrase | eyes | 0 | 33336 | 46 | 11 | 10 | 277 | — | — | — | — | drop-shaped_pupils, empty_picture_frame, eye_reflection, cephalopod_eyes, star-shaped_pupils | drop-shaped_pupils, +_-, one_eye_closed, single_empty_eye, hole_in_face |
| p-045-3 | 呆滞无神的眼睛 | empty_eyes | 空洞眼神 | paraphrase | eyes | 0 | 33336 | 5 | 1 | 9 | 190 | — | — | — | — | unworn_vision_(genshin_impact), blank_stare, creepy_eyes, no_pupils, empty_eyes | blank_stare, blurry_vision, partially_blind, ;/, blurry_eyes |
| p-046-1 | 双眼自己发亮 | glowing_eyes | 发光眼 | paraphrase | eyes | 0 | 45969 | 4 | 50 | 2 | 1091 | — | — | — | — | lightning_glare, glowing_eye, mark_under_both_eyes, glowing_eyes, eyes_in_shadow | glowing_glasses, glowing_eyes, mirror_selfie, pointing_at_self, visor_lift |
| p-046-2 | 眼睛像发光体 | glowing_eyes | 发光眼 | paraphrase | eyes | 0 | 45969 | 1 | 4 | 14 | 1242 | — | — | — | — | glowing_eyes, glowing_eye, glowing_body_fluid, lightning_glare, eyeball_hair_ornament | hair_between_eyes, glowing_glasses, glowing_organ, blush_visible_through_hair, hair_behind_eyewear |
| p-046-3 | 瞳孔泛着光 | glowing_eyes | 发光眼 | paraphrase | eyes | 0 | 45969 | 52 | 190 | 31 | 718 | — | — | — | — | glowing_pupils, constricted_pupils, yellow_pupils, lightning_bolt-shaped_pupils, star-shaped_pupils | +_-, multicolored_eyes, eye_glitter, eye_reflection, glowing_pupils |
| p-047-1 | 眼角挂着泪水 | tears | 眼泪 | paraphrase | eyes | 0 | 235779 | 92 | 168 | 924 | 8558 | — | — | — | — | glowing_tears, teardrop-framed_glasses, eye_drops, eye_socket, tears_from_one_eye | scar_across_eyes, eye_glitter, bruised_eye, liquid_from_eyes, hsien-ko_(cosplay) |
| p-047-2 | 泪珠顺着脸颊流下 | tears | 眼泪 | paraphrase | eyes | 0 | 235779 | 204 | 189 | 3329 | 18162 | — | — | — | — | floating_tears, drooling_blood, glowing_tears, tears_from_one_eye, blood_on_cheek | cheek_piercing, sunken_cheeks, precum_on_face, blush_visible_through_hair, blood_on_cheek |
| p-047-3 | 像刚哭过 | tears | 眼泪 | paraphrase | eyes | 0 | 235779 | 11 | 5 | 29 | 3674 | — | — | — | — | t_t, chopper_crying_(meme), muffled, crying_emoji, crying_with_eyes_open | ;(, nervous_smile, crying, sobbing, :c |
| p-048-1 | 鼻梁上戴着眼镜 | eyewear | — | paraphrase | eyes | 7 | 307179 | 20301 | 25114 | 20941 | 27872 | — | — | — | — | bandaid_on_nose, bridge_piercing, nose_blush, pince-nez, scar_on_nose | eyewear_on_headwear, eyewear_around_neck, eyewear_hang, eyewear_on_head, hair_behind_eyewear |
| p-048-2 | 两块镜片在眼前 | eyewear | — | paraphrase | eyes | 7 | 307179 | 22883 | 34635 | 46682 | 45495 | — | — | — | — | different_reflection, mirror, binoculars, two-tone_eyewear, mark_under_both_eyes | twin-lens_reflex_camera, mirror_twins, binoculars, multiple_pov, pov_breasts |
| p-048-3 | 眼镜框清楚可见 | eyewear | — | paraphrase | eyes | 7 | 307179 | 26698 | 28621 | 34638 | 39569 | — | — | — | — | eyes_visible_through_eyewear, eyewear_visible_through_hair, eyes_visible_through_headwear, orange-framed_eyewear, white-framed_eyewear | eyes_visible_through_eyewear, viewfinder, transparent_border, glowing_glasses, x-ray_glasses |
| p-049-3 | 眼部戴着遮挡物 | eyepatch | 眼罩 | paraphrase | eyes | 0 | 76635 | 35 | 87 | 177 | 433 | — | — | — | — | covered_eyes, covering_own_eyes, holding_eyepatch, hand_over_another's_eyes, hand_over_another's_eye | bandages_over_eyes, putting_in_contact_lens, helmet_over_eyes, goggles_on_eyes, looking_over_eyewear |
| p-050-1 | 头发垂下来盖住眼睛 | hair_over_eyes | 遮眼发 | paraphrase | eyes | 0 | 20670 | 3 | 8 | 4 | 4 | — | — | — | — | hair_between_eyes, hair_over_one_eye, hair_over_eyes, hair_behind_eyewear, hair_in_eyes | hair_behind_eyewear, hair_between_eyes, hair_over_face, hair_over_eyes, visor_lift |
| p-050-2 | 刘海挡住视线 | hair_over_eyes | 遮眼发 | paraphrase | eyes | 0 | 20670 | 326 | 6768 | 129 | 717 | — | — | — | — | eyebrows_hidden_by_hair, curtained_hair, long_hair_between_eyes, black_visor, stomping_viewer | long_hair_between_eyes, averting_eyes, curtained_hair, blurry_vision, putting_in_contact_lens |
| p-050-3 | 发丝把双眼遮掉 | hair_over_eyes | 遮眼发 | paraphrase | eyes | 0 | 20670 | 1 | 10 | 6 | 68 | — | — | — | — | hair_over_eyes, mark_under_both_eyes, hair_over_one_eye, hair_between_eyes, hair_in_eyes | hair_behind_eyewear, hair_over_crotch, hair_between_eyes, covering_another's_eye, blush_visible_through_hair |
| p-051-1 | 嘴巴张开露出里面 | open_mouth | 张嘴 | paraphrase | mouth | 0 | 2365905 | 1 | 227 | 1 | 1614 | — | — | — | — | open_mouth, mouth_visible_through_hair, mouth_out_of_frame, gag_under_mask, over_the_nose_gag | open_mouth, mouth_piercing, liquid_from_mouth, hair_over_mouth, hip_vent |
| p-051-2 | 上下唇分开 | open_mouth | 张嘴 | paraphrase | mouth | 0 | 2365905 | 216 | 1653 | 56 | 7317 | — | — | — | — | lower_lip_only, labret_piercing, side_labret_piercing, upside-down_kiss, lip_ring | separated_legs, knees_together_feet_apart, half-spread_pussy, finger_to_mouth, licking_another's_lips |
| p-051-3 | 嘴里留一道开口 | open_mouth | 张嘴 | paraphrase | mouth | 0 | 2365905 | 3 | 251 | 11 | 620 | — | — | — | — | mouth_pull, finger_in_another's_mouth, open_mouth, mouth_bubble, holding_another's_tongue | mouth_pull, :v, necktie_in_mouth, :o, :p |
| p-052-1 | 双唇紧紧合上 | closed_mouth | 闭嘴 | paraphrase | mouth | 0 | 1167588 | 2162 | 2821 | 4497 | 1489 | — | — | — | — | double_cheek_kiss, lip_ring, soul_patch, thighs_together, lower_lip_only | double_cheek_kiss, legs_together, thighs_together, sucking_both_nipples, two-tone_gloves |
| p-052-2 | 不要张嘴 | closed_mouth | 闭嘴 | paraphrase | mouth | 0 | 1167588 | 330 | 377 | 26 | 14 | — | — | — | — | no_mouth, unworn_gag, no_fingers, open_mouth, :/ | v_over_mouth, open_mouth, hair_over_mouth, :/, :p |
| p-052-3 | 嘴部没有缝隙 | closed_mouth | 闭嘴 | paraphrase | mouth | 0 | 1167588 | 473 | 597 | 352 | 245 | — | — | — | — | stitched_mouth, mouth_visible_through_hair, mouth_piercing, stitched_neck, mouth_out_of_frame | neck_corset, no_pussy, non-pubic_inmon, mouth_submerged, no_nipples |
| p-053-1 | 嘴角向上 | smile | 微笑 | paraphrase | mouth | 0 | 2873890 | 15138 | 16308 | 18820 | 37453 | — | — | — | — | beard_over_mouth, hair_over_mouth, mouth_pull, scar_on_mouth, blood_on_mouth | blood_on_mouth, mouth_pull, w_over_mouth, arm_over_head, hair_over_mouth |
| p-053-2 | 面带笑意 | smile | 微笑 | paraphrase | mouth | 0 | 2873890 | 2463 | 7245 | 1773 | 30884 | — | — | — | — | smiley_hair_ornament, smirk, facial_mark, smiley_face, naughty_face | ;), giggling, nervous_smile, ;>, :i |
| p-053-3 | 轻轻笑着 | smile | 微笑 | paraphrase | mouth | 0 | 2873890 | 4 | 7 | 24 | 15746 | — | — | — | — | spoken_smile, soulglad, \o/, smile, seductive_smile | nervous_smile, light_smile, ;), \o/, forced_smile |
| p-054-1 | 咧嘴露出夸张笑容 | grin | 露齿笑 | paraphrase | mouth | 0 | 233048 | 4 | 309 | 2 | 46 | — | — | — | — | comically_sharp_chin, ;), crooked_smile, grin, ^_^ | giggling, grin, c:, nervous_smile, ;) |
| p-054-2 | 牙齿全露出来笑 | grin | 露齿笑 | paraphrase | mouth | 0 | 233048 | 2 | 14 | 10 | 358 | — | — | — | — | upper_teeth_only, grin, lower_teeth_only, crazy_grin, fang_out | hair_over_mouth, black_mouth, full_beard, hair_over_face, c: |
| p-054-3 | 笑得很灿烂 | grin | 露齿笑 | paraphrase | mouth | 0 | 233048 | 17 | 960 | 5 | 19 | — | — | — | — | smirk, forced_smile, >:), stifled_laugh, crazy_laugh | nervous_smile, giggling, laughing, ;), grin |
| p-055-1 | 眉眼和嘴角都往下 | frown | 皱眉 | paraphrase | mouth | 0 | 107762 | 852 | 1196 | 1129 | 10171 | — | — | — | — | eyebrows_visible_through_mask, eyebrows_visible_through_hat, eyebrows_visible_through_headband, curly_eyebrows, lower_eyelashes_only | sunken_cheeks, blush_visible_through_hair, hair_over_mouth, mole_beside_mouth, mustache_stubble |
| p-055-2 | 脸上带着不高兴 | frown | 皱眉 | paraphrase | mouth | 0 | 107762 | 173 | 1160 | 45 | 264 | — | — | — | — | rice_on_face, unworn_mask, expressionless, puckered_face, no_skin | :c, ;(, unhappy, d:, smirk |
| p-056-1 | 嘴唇鼓起来 | pout | 嘟嘴 | paraphrase | mouth | 0 | 25686 | 173 | 3335 | 3692 | 7303 | — | — | — | — | lips, licking_lips, puffy_cheeks, lower_lip_only, finger_to_mouth | bouncing_belly, throat_bulge, labia_stretching, bouncing_breasts, labia_piercing |
| p-056-2 | 像在闹别扭一样噘嘴 | pout | 嘟嘴 | paraphrase | mouth | 0 | 25686 | 281 | 2423 | 771 | 8082 | — | — | — | — | foaming_at_the_mouth, heart-shaped_mouth, mouth_bubble, puckered_lips, hand_over_another's_mouth | frilled_shrug, :v, squiggle, asymmetrical_docking, twisted_breasts |
| p-056-3 | 下唇向前嘟 | pout | 嘟嘴 | paraphrase | mouth | 0 | 25686 | 109 | 2459 | 3407 | 8179 | — | — | — | — | soul_patch, lower_lip_only, labret_piercing, side_labret_piercing, lip_ring | precum_on_face, :v, :q, finger_to_mouth, mustache_stubble |
| p-057-1 | 嘴唇微微分开但不是大张 | parted_lips | 微张嘴 | paraphrase | mouth | 0 | 493440 | 2 | 1 | 4 | 1 | — | — | — | — | thick_lips, parted_lips, lower_lip_only, puffy_lips, low-tied_medium_hair | separated_legs, loosely_tucked_bangs, disembodied_breast, parted_lips, labia_stretching |
| p-057-2 | 唇间留一条细缝 | parted_lips | 微张嘴 | paraphrase | mouth | 0 | 493440 | 147 | 2 | 52 | 82 | — | — | — | — | applying_lipstick, labia_piercing, between_labia, lipstick_mark_on_neck, side_labret_piercing | between_labia, scar_on_lip, labia_piercing, :q, soul_patch |
| p-057-3 | 轻启双唇 | parted_lips | 微张嘴 | paraphrase | mouth | 0 | 493440 | 106 | 20 | 175 | 117 | — | — | — | — | lower_lip_only, side_labret_piercing, labret_piercing, lip_ring, lip_piercing | double_cheek_kiss, sucking_both_nipples, labia_stretching, double_face_punch, index_fingers_raised |
| p-058-1 | 舌头伸到嘴外 | tongue_out | 吐舌 | paraphrase | mouth | 0 | 278625 | 13 | 63 | 159 | 2212 | — | — | — | — | tongue_wrap, burnt_tongue, blood_on_tongue, tongue, tongue_suck | thumb_to_mouth, very_long_tongue, hair_over_mouth, :v, pulling_tongue |
| p-058-2 | 嘴里吐出舌尖 | tongue_out | 吐舌 | paraphrase | mouth | 0 | 278625 | 4 | 97 | 37 | 924 | — | — | — | — | stutter, toast_in_mouth, mouth_bubble, tongue_out, :p | toast_in_mouth, throat_bulge, cum_on_tongue, pill_on_tongue, blood_on_tongue |
| p-058-3 | 舌头露在唇外 | tongue_out | 吐舌 | paraphrase | mouth | 0 | 278625 | 26 | 123 | 211 | 2943 | — | — | — | — | smeared_lipstick, burnt_tongue, scar_on_lip, lipstick, exposed_teeth | blood_on_tongue, very_long_tongue, tongue_wrap, colored_tongue, pill_on_tongue |
| p-059-2 | 牙列清楚可见 | teeth | 牙齿 | paraphrase | mouth | 0 | 492181 | 94 | 7 | 167 | 9542 | — | — | — | — | upper_teeth_only, mouth_visible_through_hair, dental_chair, mouth_guard, lower_teeth_only | dot-matrix, visible_air, head-mounted_display, dildo_reveal, colored_teeth |
| p-059-3 | 嘴里能看到牙 | teeth | 牙齿 | paraphrase | mouth | 0 | 492181 | 21 | 7 | 35 | 419 | — | — | — | — | mouth_visible_through_hair, upper_teeth_only, shark_tooth, mouth_bubble, mouth_guard | hair_over_mouth, blood_on_teeth, food_in_mouth, blood_on_mouth, plectrum_in_mouth |
| p-060-2 | 上下牙用力合着 | clenched_teeth | 咬紧牙关 | paraphrase | mouth | 0 | 67693 | 11 | 473 | 836 | 5488 | — | — | — | — | dental_gag, braces, holding_toothbrush, teeth_print_mask, tooth_earrings | brushing_another's_teeth, toothbrush_in_mouth, blood_on_teeth, footjob_from_behind, hair_tie_in_mouth |
| p-060-3 | 露出紧绷的牙齿 | clenched_teeth | 咬紧牙关 | paraphrase | mouth | 0 | 67693 | 2 | 6 | 8 | 608 | — | — | — | — | fang_out, clenched_teeth, upper_teeth_only, lower_teeth_only, sharp_teeth | thick_mustache, flexing_pectorals, blush_visible_through_hair, blood_on_teeth, taut_bikini |
| p-061-1 | 脸颊泛红 | blush | 脸红 | paraphrase | expression | 0 | 2942792 | 2 | 153 | 5 | 12162 | — | — | — | — | body_blush, blush, lipstick, full-body_blush, blush_visible_through_hands | bruise_on_face, body_blush, sunken_cheeks, shoulder_blush, blush |
| p-061-2 | 两边面颊染上红晕 | blush | 脸红 | paraphrase | expression | 0 | 2942792 | 47 | 1737 | 210 | 25351 | — | — | — | — | neck_blush, knee_blush, hand_blush, nose_blush, ass_blush | neck_blush, shoulder_blush, heart_cheeks, ass_blush, blush_visible_through_hair |
| p-062-1 | 表情很生气 | angry | 愤怒 | paraphrase | expression | 0 | 44161 | 40 | 31 | 8 | 175 | — | — | — | — | >:(, :c, tantrum, crying_emoji, naughty_face | >:(, ;(, exasperation, d:, :c |
| p-062-2 | 眉头压低带怒意 | angry | 愤怒 | paraphrase | expression | 0 | 44161 | 4269 | 549 | 217 | 12512 | — | — | — | — | >:(, glaring, puckered_face, light_frown, elbow_blush | blush_visible_through_hair, frilled_shrug, face_stretching, nervous_smile, rape_face |
| p-062-3 | 像在发火 | angry | 愤怒 | paraphrase | expression | 0 | 44161 | 15568 | 12789 | 2945 | 41011 | — | — | — | — | fiery_hair, flaming_head, fire_pit, fire_hair_ornament, firing_at_viewer | firing_at_viewer, burnt, burning, in_heat, blush_visible_through_hair |
| p-063-2 | 像突然被吓到 | surprised | 惊讶 | paraphrase | expression | 0 | 53084 | 278 | 24 | 62 | 160 | — | — | — | — | horrified, surprise_hug, jumpscare, panicking, spasm | horrified, trapped, imminent_grope, nervous_smile, imminent_rape |
| p-063-3 | 一脸意外 | surprised | 惊讶 | paraphrase | expression | 0 | 53084 | 812 | 4648 | 9 | 379 | — | — | — | — | accident, accidental_touch, accidental_exposure, clueless, accidental_kiss | ;o, d:, accident, 0_0, :c |
| p-064-1 | 眼泪止不住地往下掉 | crying | 哭泣 | paraphrase | expression | 0 | 76783 | 295 | 366 | 117 | 8255 | — | — | — | — | tears_from_one_eye, flying_teardrops, glowing_tears, floating_tears, crying_with_eyes_open | ;/, ;(, single_tear, wiping_tears, mind_rape |
| p-064-2 | 哭得满脸泪 | crying | 哭泣 | paraphrase | expression | 0 | 76783 | 6 | 49 | 1 | 70 | — | — | — | — | glowing_tears, facepalm, puckered_face, fake_tears, full-face_blush | crying, ;(, crying_emoji, :c, facepalm |
| p-064-3 | 正在放声哭 | crying | 哭泣 | paraphrase | expression | 0 | 76783 | 3 | 5 | 1 | 200 | — | — | — | — | muffled, crying_with_eyes_open, crying, crying_emoji, crying_aqua_(meme) | crying, sobbing, struggling, nervous_smile, trembling |
| p-065-1 | 脸上看不出情绪 | expressionless | 无表情 | paraphrase | expression | 0 | 119191 | 1 | 7 | 135 | 32 | — | — | — | — | expressionless, naughty_face, face_in_shadow, >:(, scar_on_face | blurry_vision, ;/, face_in_shadow, ;(, blank_stare |
| p-065-2 | 表情平平的 | expressionless | 无表情 | paraphrase | expression | 0 | 119191 | 6 | 79 | 23165 | 11758 | — | — | — | — | ;(, >_o, :c, naughty_face, spoken_expression | spinning, upside-down, henohenomoheji, \n/, mask_lift |
| p-065-3 | 一副没有表情的样子 | expressionless | 无表情 | paraphrase | expression | 0 | 119191 | 1 | 1 | 3 | 11 | — | — | — | — | expressionless, ;(, :c, impossible_shirt, >:( | d:, ;(, expressionless, :c, faceless |
| p-066-1 | 头发剪到耳朵附近 | short_hair | 短发 | paraphrase | hair | 0 | 2261608 | 601 | 2252 | 1789 | 6163 | — | — | — | — | hair_around_ear, hair_ears, headphones_around_neck, hair_behind_ear, cut_ear | hair_behind_ear, hair_around_ear, sidecut, side_cut, ear_picking |
| p-066-2 | 发梢不超过下巴 | short_hair | 短发 | paraphrase | hair | 0 | 2261608 | 311 | 2113 | 2390 | 9423 | — | — | — | — | tail_between_legs, sideless_bangs, low-tied_medium_hair, unworn_hairband, tail_around_another's_leg | undercut, bikini_bottom_only, very_low_bun, non-pubic_inmon, no_hair_bow |
| p-067-1 | 发丝一直垂到腰间 | long_hair | 长发 | paraphrase | hair | 0 | 4350743 | 478 | 2882 | 2125 | 20936 | — | — | — | — | hair_between_eyes, loose_hair_strand, hair_on_horn, fur-trimmed_belt, hair_flowing_over | hair_over_crotch, blush_visible_through_hair, hair_between_eyes, hair_between_horns, hair_behind_eyewear |
| p-067-2 | 头发长度很长 | long_hair | 长发 | paraphrase | hair | 0 | 4350743 | 3 | 5 | 3 | 215 | — | — | — | — | hair_length_switch, very_long_hair, long_hair, medium_hair, very_long_sidelocks | very_long_hair, alternate_hair_length, long_hair, absurdly_long_hair, hair_length_switch |
| p-068-1 | 头发拖到腿边 | very_long_hair | 超长发 | paraphrase | hair | 0 | 952244 | 1474 | 1232 | 3541 | 910 | — | — | — | — | head_between_legs, head_between_thighs, fur-trimmed_legwear, trembling_legs, arm_around_leg | bikini_bottom_around_leg, head_on_another's_leg, hair_over_shoulder, legs_behind_head, thigh_bands |
| p-068-2 | 发尾长得夸张 | very_long_hair | 超长发 | paraphrase | hair | 0 | 952244 | 9 | 20 | 598 | 132 | — | — | — | — | hair_length_switch, official_alternate_hair_length, low-tied_medium_hair, alternate_hair_length, long_beard | balding, high_braided_ponytail, high_ponytail, high_side_ponytail, blush_visible_through_hair |
| p-068-3 | 超过腰部很多 | very_long_hair | 超长发 | paraphrase | hair | 0 | 952244 | 1015 | 966 | 918 | 443 | — | — | — | — | too_many_hands, extra_limbs, too_many_belts, too_many_bows, too_many_stickers | multiple_belts, muffin_top, multiple_pov, too_many_belts, large_belt |
| p-069-1 | 头发长度刚到肩膀 | medium_hair | 中长发 | paraphrase | hair | 0 | 377425 | 7 | 4 | 38 | 3 | — | — | — | — | hair_length_switch, short_hair_with_long_locks, hair_horns, hair_over_shoulder, very_long_hair | hair_over_shoulder, stretched_neck, arm_over_head, thick_arm_hair, hair_lift |
| p-069-2 | 不长不短的发型 | medium_hair | 中长发 | paraphrase | hair | 0 | 377425 | 8 | 3 | 13 | 11 | — | — | — | — | alternate_hair_length, short_hair_with_long_locks, very_short_hair, short_hair, asymmetrical_hair | low-tied_long_hair, very_short_hair, low-braided_long_hair, alternate_hair_length, side_cut |
| p-069-3 | 发梢落在肩头 | medium_hair | 中长发 | paraphrase | hair | 0 | 377425 | 32 | 109 | 994 | 2499 | — | — | — | — | hair_over_shoulder, bite_mark_on_shoulder, head_between_legs, hair_half_over_shoulder, blood_on_shoulder | bird_on_shoulder, bandaid_on_shoulder, object_on_shoulder, hair_over_shoulder, frilled_shrug |
| p-070-2 | 头发在身后束起来 | ponytail | 马尾 | paraphrase | hair | 0 | 599087 | 5376 | 3684 | 3580 | 12586 | — | — | — | — | hair_between_horns, bunching_hair, hair_behind_eyewear, hair_on_horn, hair_horns | hair_behind_eyewear, tying_another's_hair, bunching_hair, wringing_hair, grabbing_own_hair |
| p-071-1 | 马尾偏在一侧肩膀 | side_ponytail | 侧马尾 | paraphrase | hair | 0 | 176822 | 1 | 13 | 2 | 71 | — | — | — | — | side_ponytail, ponytail_over_shoulder, low_side_ponytail, high_side_ponytail, ponytail_with_braided_base | high_side_ponytail, side_ponytail, arm_over_head, ponytail_over_shoulder, tail_around_own_leg |
| p-071-2 | 只在左边扎一束头发 | side_ponytail | 侧马尾 | paraphrase | hair | 0 | 176822 | 444 | 371 | 399 | 3160 | — | — | — | — | single_hair_intake, one_side_up, hair_up, single_sidelock, half_updo | tying_another's_hair, single_hair_intake, blunt_tresses, wringing_hair, multi-tied_hair |
| p-071-3 | 侧边垂着马尾 | side_ponytail | 侧马尾 | paraphrase | hair | 0 | 176822 | 1 | 4 | 1 | 14 | — | — | — | — | side_ponytail, high_side_ponytail, ponytail_over_shoulder, low_side_ponytail, ponytail_with_braided_base | side_ponytail, high_side_ponytail, ponytail_holder, ponytail, ponytail_over_shoulder |
| p-072-1 | 左右各扎一束 | double_ponytail | — | paraphrase | hair | 7 | 28 | 50022 | 28798 | 29601 | 45657 | — | — | — | — | one_side_up, two_side_up, single_hair_intake, scarf_on_head, alternate_sleeve_length | tying_another's_hair, blunt_tresses, hair_behind_eyewear, multi-tied_hair, string_around_wrist |
| p-072-2 | 两条马尾对称垂下 | double_ponytail | — | paraphrase | hair | 7 | 28 | 41132 | 28044 | 17313 | 27501 | — | — | — | — | two_side_up, side_ponytail, twintails_with_braided_base, ponytail_over_shoulder, high_side_ponytail | two_side_up, arms_at_sides, twin_drills, legs_on_another's_shoulders, legs_behind_head |
| p-072-3 | 双侧发束一起绑起 | double_ponytail | — | paraphrase | hair | 7 | 28 | 34559 | 10103 | 13958 | 24227 | — | — | — | — | tail_belt, twintails_with_hair_base, bound_legs, single_hair_intake, one_side_up | multi-tied_hair, tied_to_pole, hair_behind_eyewear, bound_leg, bound_ankles |
| p-073-2 | 发丝交叉编起来 | braid | 辫子 | paraphrase | hair | 0 | 629860 | 14257 | 11832 | 3196 | 13724 | — | — | — | — | center_cross_lace, crossed_bandaids, cross-laced_hairband, ribbon_in_braid, cross_hair_ornament | cross-laced_hairband, criss-cross_strings, tying_another's_hair, cross-laced_bra, cross-laced_top |
| p-073-3 | 一条编发垂在身后 | braid | 辫子 | paraphrase | hair | 0 | 629860 | 12825 | 25017 | 1068 | 14608 | — | — | — | — | half_up_braid, behind_another, master_and_servant, behind_cover, half_up_half_down_braid | behind_curtains, hair_behind_eyewear, hair_pulled_back, braided_bun, behind_another |
| p-074-1 | 两边各有一条辫子 | twin_braids | 双麻花辫 | paraphrase | hair | 0 | 180014 | 3 | 4 | 5 | 386 | — | — | — | — | side_braids, half_crown_braid, twin_braids, braid, side_braid | side_braids, two-sided_ribbon, hair_branch, braid, twin_braids |
| p-074-2 | 左右编发成对出现 | twin_braids | 双麻花辫 | paraphrase | hair | 0 | 180014 | 1219 | 278 | 8991 | 20200 | — | — | — | — | alternate_sleeve_length, twintails_with_braided_base, half_up_half_down_braid, head_between_legs, braided_twintails | :v, backwards_text, torn_overalls, braided_twintails, from_below |
| p-074-3 | 双辫垂在肩前 | twin_braids | 双麻花辫 | paraphrase | hair | 0 | 180014 | 5 | 23 | 17 | 1506 | — | — | — | — | arms_at_sides, front_braid, foot_dangle, front-to-back, twin_braids | legs_on_another's_shoulders, arms_at_sides, hair_over_shoulder, legs_behind_head, double_strap_slip |
| p-075-1 | 一缕头发落在两眼中间 | hair_between_eyes | 发丝垂于眼间 | paraphrase | hair | 0 | 1164638 | 1 | 1 | 1 | 2 | — | — | — | — | hair_between_eyes, head_between_legs, mark_under_both_eyes, hair_in_eyes, hair_over_one_eye | hair_between_eyes, medium_sideburns, hair_behind_eyewear, double-parted_hair, hair_between_horns |
| p-075-2 | 发丝从额头垂到鼻梁 | hair_between_eyes | 发丝垂于眼间 | paraphrase | hair | 0 | 1164638 | 16 | 325 | 3 | 11 | — | — | — | — | bandaid_on_nose, over_the_nose_gag, bridge_piercing, scar_on_nose, head_wreath_removed | nipple_ribbon, hair_over_crotch, hair_between_eyes, hair_over_mouth, sparse_navel_hair |
| p-075-3 | 中间那撮头发夹在双眼之间 | hair_between_eyes | 发丝垂于眼间 | paraphrase | hair | 0 | 1164638 | 2 | 6 | 3 | 6 | — | — | — | — | head_between_thighs, hair_between_eyes, head_between_legs, mark_under_both_eyes, hair_in_eyes | double-parted_hair, head_between_thighs, hair_between_eyes, hair_between_horns, medium_sideburns |
| p-076-1 | 长发搭在肩膀前面 | hair_over_shoulder | 搭肩发 | paraphrase | hair | 0 | 53522 | 1 | 1 | 1 | 1 | — | — | — | — | hair_over_shoulder, head_between_legs, leg_behind_shoulder, arm_around_chest, front-to-back | hair_over_shoulder, arm_across_neck, arm_over_head, clothes_on_shoulders, arm_over_shoulder |
| p-076-2 | 发尾从肩头垂下来 | hair_over_shoulder | 搭肩发 | paraphrase | hair | 0 | 53522 | 1 | 2 | 1 | 3 | — | — | — | — | hair_over_shoulder, head_on_another's_shoulder, ponytail_over_shoulder, shoulder_cutout, tail_around_neck | hair_over_shoulder, ponytail_over_shoulder, arm_over_head, hair_flowing_over, head_back |
| p-076-3 | 头发越过肩头落到胸前 | hair_over_shoulder | 搭肩发 | paraphrase | hair | 0 | 53522 | 1 | 1 | 1 | 1 | — | — | — | — | hair_over_shoulder, breasts_on_head, hair_over_breasts, arm_around_chest, hair_through_headwear | hair_over_shoulder, off-shoulder_bandeau, hair_over_breasts, hair_half_over_shoulder, arm_over_head |
| p-077-1 | 额头前垂着刘海 | bangs | — | paraphrase | hair | 7 | 22505 | 45159 | 41469 | 39425 | 35407 | — | — | — | — | center-flap_bangs, sideless_bangs, eyebrows_hidden_by_hair, arched_bangs, double-parted_bangs | forehead_blush, loosely_tucked_bangs, scar_on_forehead, mole_on_forehead, forehead_tattoo |
| p-077-2 | 前额被一排头发遮住 | bangs | — | paraphrase | hair | 7 | 22505 | 35498 | 29984 | 29764 | 25166 | — | — | — | — | forehead_piercing, bandaid_on_forehead, hair_over_one_eye, scar_on_forehead, wiping_forehead | hair_over_face, hair_over_one_breast, hair_over_breasts, hair_behind_eyewear, hair_branch |
| p-077-3 | 头发从发际线落下来 | bangs | — | paraphrase | hair | 7 | 22505 | 36444 | 16206 | 30110 | 22420 | — | — | — | — | receding_hairline, hair_spread_out, untying_hair, hair_tubes_removed, loose_hair_strand | receding_hairline, hair_flowing_over, fur-trimmed_hairband, hair_branch, hair_pulled_back |
| p-078-1 | 刘海向一边梳开 | swept_bangs | 侧分刘海 | paraphrase | hair | 0 | 119964 | 13 | 12 | 63 | 1 | — | — | — | — | eyebrows_hidden_by_hair, bangs_blown_up, bangs_pinned_back, pointed_bangs, curtained_hair | loosely_tucked_bangs, curtained_hair, hair_pulled_back, flipped_bangs, blush_visible_through_hair |
| p-078-2 | 额头头发斜着分到侧面 | swept_bangs | 侧分刘海 | paraphrase | hair | 0 | 119964 | 88 | 201 | 118 | 36 | — | — | — | — | scar_on_forehead, side_ahoge, side_cut, hair_flaps, head_on_ass | forehead_tattoo, lipstick_mark_on_forehead, forehead_blush, hair_half_over_shoulder, forehead_piercing |
| p-078-3 | 前发被拨向旁边 | swept_bangs | 侧分刘海 | paraphrase | hair | 0 | 119964 | 10356 | 10651 | 353 | 33 | — | — | — | — | mole_on_forehead, hand_on_own_forehead, hair_around_ear, touching_forehead, hair_behind_eyewear | necktie_aside, head_back, arm_around_back, from_below, inverted_bob |
| p-079-1 | 刘海剪成整齐平直的一刀切 | blunt_bangs | 齐刘海 | paraphrase | hair | 0 | 289395 | 30 | 118 | 75 | 78 | — | — | — | — | cut_bangs, center-flap_bangs, curtained_hair, crew_cut, braided_bangs | cut_bangs, split_crop, double-parted_bangs, parted_bangs, surgical_scissors |
| p-079-2 | 额前发梢在同一条水平线 | blunt_bangs | 齐刘海 | paraphrase | hair | 0 | 289395 | 11129 | 10627 | 1358 | 4322 | — | — | — | — | centered_hair_bow, hair_between_ass, ass-to-ass_penetration, receding_hairline, one_side_up | lipstick_mark_on_forehead, arm_across_neck, arm_over_head, asymmetrical_docking, forehead_blush |
| p-079-3 | 不要参差的刘海 | blunt_bangs | 齐刘海 | paraphrase | hair | 0 | 289395 | 22 | 44 | 19 | 21 | — | — | — | — | sideless_bangs, eyebrows_hidden_by_hair, braided_bangs, choppy_bangs, bangs_pinned_back | sideless_bangs, double-parted_bangs, long_hair_between_eyes, loosely_tucked_bangs, asymmetrical_bangs |
| p-080-1 | 耳朵两侧留着长发束 | sidelocks | 鬓发 | paraphrase | hair | 0 | 612620 | 514 | 4356 | 1283 | 5095 | — | — | — | — | hair_around_ear, long_pointy_ears, long_earlobes, short_hair_with_long_locks, bandaged_ear | hair_behind_eyewear, hair_behind_ear, hair_around_ear, hair_over_mouth, ears_back |
| p-080-2 | 脸旁各垂一缕头发 | sidelocks | 鬓发 | paraphrase | hair | 0 | 612620 | 545 | 5885 | 1756 | 4416 | — | — | — | — | medium_hair, hair_over_face, black_facial_hair, alternate_facial_hair, hair_between_eyes | hair_over_face, sparse_navel_hair, hair_behind_eyewear, side_braids, hair_between_eyes |
| p-080-3 | 侧边发丝贴着脸颊 | sidelocks | 鬓发 | paraphrase | hair | 0 | 612620 | 183 | 3883 | 1539 | 6027 | — | — | — | — | bandaid_on_cheek, bandaid_on_face, facing_to_the_side, side_ahoge, hair_flaps | cheek_piercing, bandaid_on_cheek, gauze_on_cheek, hair_over_mouth, hair_over_crotch |
| p-081-1 | 头发卷成小卷 | curly_hair | 卷发 | paraphrase | hair | 0 | 34462 | 1 | 3 | 4 | 210 | — | — | — | — | curly_hair, curly_sidelocks, cube_hair_ornament, drill_hair, kinky_hair | kinky_hair, twirling_hair, undercut, curly_hair, hair_branch |
| p-081-2 | 发丝呈螺旋状 | curly_hair | 卷发 | paraphrase | hair | 0 | 34462 | 380 | 975 | 40 | 731 | — | — | — | — | screw_hair_ornament, drill_hair, ringlets, drill_sidelocks, snake_hair_ornament | drill_hair, screw_hair_ornament, hair_wagging, propeller_hair_ornament, loose_hair_strand |
| p-082-1 | 头发有自然波浪 | wavy_hair | 波浪卷发 | paraphrase | hair | 0 | 104017 | 1 | 1 | 1 | 1 | — | — | — | — | wavy_hair, wavy_sidelocks, hair_floating_upwards, thick_hair, hair_bobbles | wavy_hair, foaming_waves, hair_wagging, floating_hair, hair_floating_upwards |
| p-082-2 | 发丝一缕一缕弯曲 | wavy_hair | 波浪卷发 | paraphrase | hair | 0 | 104017 | 196 | 163 | 445 | 77 | — | — | — | — | floating_hair, split-color_hair, hair_scarf, kinky_hair, curly_sidelocks | hair_bobbles, hair_wagging, blush_visible_through_hair, kinky_hair, hair_between_eyes |
| p-082-3 | 不是笔直的长发 | wavy_hair | 波浪卷发 | paraphrase | hair | 0 | 104017 | 377 | 360 | 621 | 292 | — | — | — | — | medium_hair, no_hair_ornament, no_hairband, no_hairclip, very_long_hair | fade_(haircut), low-braided_long_hair, alternate_hair_length, low-tied_long_hair, no_hair_bow |
| p-083-1 | 发梢像钻头一样向外卷 | drill_hair | 螺旋卷发 | paraphrase | hair | 0 | 89870 | 2 | 12 | 30 | 1330 | — | — | — | — | curly_hair, drill_hair, curly_sidelocks, flipped_hair, single_drill | off-shoulder_bandeau, hair_over_crotch, kinky_hair, hair_behind_eyewear, hair_pulled_back |
| p-083-2 | 两侧卷发盘成螺旋 | drill_hair | 螺旋卷发 | paraphrase | hair | 0 | 89870 | 1 | 8 | 2 | 68 | — | — | — | — | drill_hair, side_drill, ringlets, twin_drills, curly_sidelocks | side_drill, drill_hair, curly_sidelocks, drill_ponytail, drill_sidelocks |
| p-083-3 | 螺旋形发束 | drill_hair | 螺旋卷发 | paraphrase | hair | 0 | 89870 | 3 | 54 | 3 | 124 | — | — | — | — | screw_hair_ornament, snake_hair_ornament, drill_hair, bolt_hair_ornament, ringlets | drill_ponytail, ringlets, drill_hair, hair_bobbles, spiral_power |
| p-084-1 | 头发乱蓬蓬的 | messy_hair | 乱发 | paraphrase | hair | 0 | 61768 | 3 | 41 | 21 | 92 | — | — | — | — | loose_hair_strand, hair_bun, messy_hair, puffy_hair, bunching_hair | loose_hair_strand, sparse_pubic_hair, ruffling_hair, stray_hair, hair_blush |
| p-084-2 | 发丝四处翘起 | messy_hair | 乱发 | paraphrase | hair | 0 | 61768 | 54 | 878 | 628 | 3426 | — | — | — | — | flipped_hair, hair_flaps, quad_hair_rings, floating_hair, hair_on_horn | hair_over_crotch, flipped_hair, hair_flaps, hair_wagging, cross-laced_hairband |
| p-084-3 | 刚睡醒般凌乱 | messy_hair | 乱发 | paraphrase | hair | 0 | 61768 | 93 | 336 | 1491 | 6319 | — | — | — | — | messy, messy_room, drugged, messy_sleeper, unkempt | messy_sleeper, sleeping_upright, nightgown_lift, flaccid, feigning_sleep |
| p-085-1 | 头发上系着蝴蝶结 | hair_ribbon | 发带 | paraphrase | hair | 0 | 604174 | 850 | 789 | 54 | 539 | — | — | — | — | bow-shaped_hair, hair_bow, bow_hairband, butterfly_on_hair, bow_headband | multiple_hat_bows, bow-shaped_hair, hair_bow, cross-laced_hairband, butterfly_hair_ornament |
| p-085-2 | 发束绑一条丝带 | hair_ribbon | 发带 | paraphrase | hair | 0 | 604174 | 121 | 112 | 62 | 735 | — | — | — | — | ribbon_bondage, ribbon, ribbon_hair, tress_ribbon, tail_belt | bandage_on_hair, tress_ribbon, ribbon_in_braid, studded_hairband, hair_behind_eyewear |
| p-086-1 | 人物直立站着 | standing | 站立 | paraphrase | pose | 0 | 901688 | 2 | 668 | 1 | 7620 | — | — | — | — | standing_on_shoulder, standing, upright_straddle, standing_on_three_legs, standing_restraints | standing, leaning, standing_on_animal, sunrise_stance, standing_on_liquid |
| p-086-2 | 双脚踩地保持站姿 | standing | 站立 | paraphrase | pose | 0 | 901688 | 33 | 11590 | 834 | 31919 | — | — | — | — | feet_on_chair, two-footed_footjob, feet_against_wall, bowlegged_pose, separated_legs | hand_between_legs, feet_on_chair, arms_between_legs, legs_on_another's_shoulders, standing_leg_lock |
| p-086-3 | 不是坐着或躺着 | standing | 站立 | paraphrase | pose | 0 | 901688 | 2978 | 17723 | 587 | 44229 | — | — | — | — | no_armwear, no_harness, no_prosthetic_arm, no_vest, no_pants | sitting_sideways, sit-up, lying, sitting, no_prosthetic_arm |
| p-087-1 | 人物坐在椅子上 | sitting | 坐姿 | paraphrase | pose | 0 | 939842 | 13 | 83 | 16 | 5392 | — | — | — | — | human_chair, sitting_on_person, sitting_on_shoulder, sitting_on_leg, sitting_on_table | sitting_on_person, yabuki_joe_in_a_chair_(meme), sitting_on_table, sitting_on_object, sitting_on_wall |
| p-087-2 | 臀部落在座位 | sitting | 坐姿 | paraphrase | pose | 0 | 939842 | 16 | 400 | 37 | 26633 | — | — | — | — | sitting_backwards, animal_on_ass, sitting_on_throne, sitting_against_vehicle, sitting_on_branch | booth_seating, sitting_backwards, yabuki_joe_in_a_chair_(meme), sitting_on_bar, sitting_on_face |
| p-088-1 | 双膝跪在地上 | kneeling | 跪姿 | paraphrase | pose | 0 | 118116 | 43 | 378 | 185 | 7842 | — | — | — | — | on_one_knee, legs_on_another's_shoulders, arms_on_knees, separated_legs, legs_on_another's_lap | legs_on_table, legs_on_another's_shoulders, arms_on_knees, over_the_knee, head_on_knees |
| p-088-2 | 身体压低跪坐 | kneeling | 跪姿 | paraphrase | pose | 0 | 118116 | 18 | 752 | 215 | 5709 | — | — | — | — | low-cut, low_neckline, sprawled, low_drills, low_horns | sitting_backwards, sitting_on_hand, figure_four_sitting, holding_cushion, indian_style |
| p-088-3 | 膝盖支撑身体 | kneeling | 跪姿 | paraphrase | pose | 0 | 118116 | 2064 | 3911 | 1121 | 18096 | — | — | — | — | leg_support, knees, bandaid_on_knee, hand_on_own_knee, flexible | leg_support, arms_on_knees, bandaged_knees, bandage_on_knee, hands_on_lap |
| p-089-1 | 身体横躺下来 | lying | 躺卧 | paraphrase | pose | 0 | 446035 | 384 | 135 | 10 | 1252 | — | — | — | — | cross-body_stretch, wide_spread_legs, arm_across_neck, loose_pants, arm_across_waist | body_switch, sitting_backwards, sitting_on_face, sitting_sideways, hollow_body |
| p-089-2 | 整个人平放在地面 | lying | 躺卧 | paraphrase | pose | 0 | 446035 | 24077 | 23851 | 9594 | 17450 | — | — | — | — | floor, hand_on_ground, equipment_layout, human_chair, hands_on_floor | focus_(horizon), through_ground, full_body, hands_on_ground, bikini_bottom_around_leg |
| p-089-3 | 保持躺姿 | lying | 躺卧 | paraphrase | pose | 0 | 446035 | 346 | 175 | 11 | 1396 | — | — | — | — | sitting, sitting_on_hand, stay_fresh_(pose), posing, sitting_on_leg | holding_cushion, sitting_sideways, sitting_backwards, sit-up, sitting_on_hand |
| p-090-1 | 屈膝蹲着 | squatting | 蹲姿 | paraphrase | pose | 0 | 86123 | 24 | 359 | 3 | 2556 | — | — | — | — | knees_up, curtsey, kneeing, bowing_and_scraping, knee_pads | sitting_backwards, over_the_knee, squatting, knees_up, legs_back |
| p-090-2 | 臀部靠近脚跟 | squatting | 蹲姿 | paraphrase | pose | 0 | 86123 | 1520 | 10220 | 1432 | 14654 | — | — | — | — | hip_vent, ass_visible_through_thighs, hip_focus, head_on_ass, hand_on_another's_ass | hip_focus, neck_corset, thigh_boots, hip_gear, skirt_around_one_ankle |
| p-090-3 | 身体压得很低 | squatting | 蹲姿 | paraphrase | pose | 0 | 86123 | 4656 | 28563 | 1935 | 26411 | — | — | — | — | low-cut, low_neckline, head_bowed, head_down, body_slam | lower_body, flexible, body_slam, hollow_body, breast_press |
| p-091-1 | 身体缩低弯着腿 | crouching | — | paraphrase | pose | 7 | 42549 | 38428 | 45111 | 35293 | 40172 | — | — | — | — | disembodied_legs, thin_calves, hanging_legs, legs_folded, leg_behind_shoulder | legs_back, leg_behind_shoulder, bikini_bottom_around_leg, hands_under_legs, arm_around_leg |
| p-091-2 | 像躲藏一样半蹲 | crouching | — | paraphrase | pose | 7 | 42549 | 45687 | 45160 | 42128 | 42434 | — | — | — | — | jacket_partially_removed, shirt_partially_removed, coat_partially_removed, partially_underwater_shot, lower_body | side_sitting_split, squatting, squatting_v_pose_(han-0v0), taking_shelter, sitting_backwards |
| p-091-3 | 重心压在下方 | crouching | — | paraphrase | pose | 7 | 42549 | 44866 | 51878 | 37745 | 47392 | — | — | — | — | yellow_tank_top, white_tank_top, tank_top, heart_hands_failure, breasts_on_another's_back | pectoral_press, multiple_head_bumps, breast_press, breasts_on_another's_back, pectorals_on_glass |
| p-092-1 | 正迈步向前走 | walking | 行走 | paraphrase | pose | 0 | 37739 | 73 | 446 | 14 | 452 | — | — | — | — | mid-stride, pointing_forward, battle_of_midway, reach-around, reaching_towards_another | pointing_forward, massugu_go, stepping, mid-stride, walking_backwards |
| p-092-3 | 走路中的姿势 | walking | 行走 | paraphrase | pose | 0 | 37739 | 162 | 412 | 62 | 1347 | — | — | — | — | poses, pose, posing, action_pose, henshin_pose | pose, posing, rope_walking, action_pose, dynamic_pose |
| p-093-1 | 双腿大步奔跑 | running | 跑步 | paraphrase | pose | 0 | 31166 | 70 | 37 | 16 | 569 | — | — | — | — | wide_spread_legs, trembling_legs, spread_legs, crossed_legs, jogging | wide_spread_legs, legs_over_head, legs_on_another's_shoulders, separated_legs, rope_walking |
| p-093-2 | 身体向前冲 | running | 跑步 | paraphrase | pose | 0 | 31166 | 1159 | 795 | 11 | 609 | — | — | — | — | dashing, arm_around_chest, arm_around_leg, bend, arm_behind_leg | body_switch, bend, body_slam, pointing_forward, cross-body_stretch |
| p-093-3 | 正在快速跑动 | running | 跑步 | paraphrase | pose | 0 | 31166 | 64 | 16 | 7 | 530 | — | — | — | — | sports_car, jogging, racing, fast_forward_button, relay_race | teleportation, instant_transmission, racing, burst_bomb_(splatoon), launching |
| p-094-1 | 双脚离地跳起 | jumping | 跳跃 | paraphrase | pose | 0 | 24755 | 78 | 471 | 70 | 1339 | — | — | — | — | feet_against_wall, two-footed_footjob, spread_legs, separated_legs, knees_apart_feet_together | separated_legs, foot_dangle, legs_on_another's_shoulders, trembling_legs, heel_pop |
| p-094-2 | 人物悬在空中 | jumping | 跳跃 | paraphrase | pose | 0 | 24755 | 3133 | 5365 | 496 | 7599 | — | — | — | — | hover_hand, hang_gliding, hanging_legs, hanging_on, hanging_from_ceiling | hang_gliding, person_on_head, object_on_bulge, vent_(object), mobile |
| p-095-1 | 双臂举过头顶 | arms_up | 双臂上举 | paraphrase | pose | 0 | 188117 | 4 | 4 | 2 | 41 | — | — | — | — | arm_over_head, arm_above_head, arm_on_own_head, arms_up, hands_on_own_head | arm_over_head, arms_up, arms_on_knees, x_arms, arms_at_sides |
| p-095-2 | 手臂向上伸直 | arms_up | 双臂上举 | paraphrase | pose | 0 | 188117 | 26 | 35 | 17 | 34 | — | — | — | — | cross-body_stretch, dorsiflexion_(wrist), arm_on_thigh, hanging_on_arm, arm_around_leg | arm_over_head, arm_across_neck, arm_across_waist, arm_on_thigh, hands_up |
| p-095-3 | 两只胳膊抬起来 | arms_up | 双臂上举 | paraphrase | pose | 0 | 188117 | 26 | 315 | 10 | 651 | — | — | — | — | hand_grabbing_both_breasts, hands_up, double_biceps_pose, two-sided_scarf, wide_spread_legs | arm_over_head, clenched_hands, double_biceps_pose, hand_between_legs, legs_together |
| p-096-1 | 双手叉在腰上 | hands_on_hips | — | paraphrase | pose | 7 | 12954 | 29758 | 6140 | 7367 | 11643 | — | — | — | — | hands_on_own_hips, hand_on_own_hip, hands_on_own_legs, hand_on_own_leg, hands_under_legs | hands_on_lap, hand_on_another's_hip, hands_on_another's_hips, hand_on_another's_waist, hand_on_belt |
| p-096-2 | 手掌撑着胯部 | hands_on_hips | — | paraphrase | pose | 7 | 12954 | 32839 | 8211 | 21983 | 20144 | — | — | — | — | glove_spread, hand_on_own_neck, hands_on_another's_crotch, hands_on_own_chest, crotch_rub | dorsiflexion_(wrist), hands_on_lap, hands_on_another's_crotch, crotch_rub, bursting_ass |
| p-096-3 | 两只手放在腰侧 | hands_on_hips | — | paraphrase | pose | 7 | 12954 | 30309 | 14623 | 12181 | 15292 | — | — | — | — | hand_between_legs, two-handed, hand_on_another's_hip, hand_on_another's_thigh, hand_on_another's_leg | hand_between_thighs, hand_between_legs, hands_on_own_thighs, hands_on_lap, hands_on_another's_hips |
| p-097-1 | 双手藏在身后 | hands_behind_back | — | paraphrase | pose | 7 | 35615 | 2799 | 837 | 321 | 2139 | — | — | — | — | arms_behind_back, hands_on_own_back, own_hands_clasped, hand_on_own_back, arm_around_back | arms_behind_back, arm_behind_back, hands_on_own_back, hiding_behind_another, holding_behind_neck |
| p-097-2 | 手臂从背后交叠 | hands_behind_back | — | paraphrase | pose | 7 | 35615 | 6193 | 198 | 3774 | 6967 | — | — | — | — | arm_behind_back, arm_around_back, arm_held_back, arms_around_back, footjob_from_behind | arm_behind_back, arm_over_head, arm_across_neck, arm_around_back, arm_held_back |
| p-097-3 | 正面看不到手掌 | hands_behind_back | — | paraphrase | pose | 7 | 35615 | 30441 | 13775 | 7690 | 11519 | — | — | — | — | blush_visible_through_hands, high-visibility_vest, v_over_eye, see-through_gloves, heart_hands_failure | looking_at_hand, blush_visible_through_hands, bad_hands, v_over_mouth, looking_at_hands |
| p-098-1 | 双手插进衣服口袋 | hands_in_pockets | 双手插兜 | paraphrase | pose | 0 | 24611 | 5 | 2 | 6 | 6 | — | — | — | — | hands_in_another's_pockets, hand_in_jacket, hand_under_clothes, hand_in_clothes, hands_in_pockets | hand_in_clothes, hands_in_another's_pockets, hand_under_clothes, hand_under_shirt, finger_under_clothes |
| p-098-2 | 手掌被口袋收进去 | hands_in_pockets | 双手插兜 | paraphrase | pose | 0 | 24611 | 47 | 6 | 3 | 5 | — | — | — | — | hand_in_jacket, pocket, open_hand, hand_on_own_leg, heart_floating_above_hand | hands_in_pocket, hand_in_pocket, hands_in_pockets, holding_sack, hand_in_jacket |
| p-098-3 | 两边口袋里各有一只手 | hands_in_pockets | 双手插兜 | paraphrase | pose | 0 | 24611 | 8 | 4 | 4 | 6 | — | — | — | — | hand_between_legs, two-handed, hands_in_another's_pockets, hand_in_another's_pocket, pocket | hand_in_pocket, hands_in_another's_pockets, hands_in_pocket, hands_in_pockets, hand_in_another's_pocket |
| p-099-1 | 两只手臂交叉抱在胸前 | crossed_arms | 双臂交叉 | paraphrase | pose | 0 | 84820 | 5 | 323 | 11 | 2478 | — | — | — | — | holding_to_chest, arm_across_chest, arm_around_chest, arm_across_neck, crossed_arms | x_arms, arm_around_chest, arm_over_head, arm_across_neck, bra_around_one_arm |
| p-099-2 | 胳膊在身前叠起来 | crossed_arms | 双臂交叉 | paraphrase | pose | 0 | 84820 | 2287 | 5528 | 111 | 5470 | — | — | — | — | arm_around_chest, arm_across_neck, hand_on_breast, arm_across_waist, hands_on_another's_chest | arm_over_head, arm_on_thigh, arm_across_neck, arm_around_chest, arm_across_waist |
| p-099-3 | 双臂环在胸口 | crossed_arms | 双臂交叉 | paraphrase | pose | 0 | 84820 | 54 | 1151 | 60 | 8270 | — | — | — | — | arm_around_chest, bra_around_one_arm, arms_between_legs, armlet, arm_around_leg | snake_armband, arms_on_knees, heart_arms, x_arms, silver_armlet |
| p-100-1 | 手指朝某个方向指 | pointing | 指点 | paraphrase | pose | 0 | 65269 | 344 | 234 | 242 | 1465 | — | — | — | — | curled_fingers, symmetrical_hand_pose, double_middle_finger, holding_another's_finger, finger_on_forehead | pointing_forward, finger_to_cheek, fingers_to_cheek, finger_on_trigger, finger_to_tongue |
| p-100-2 | 一只手伸出去做指引 | pointing | 指点 | paraphrase | pose | 0 | 65269 | 2248 | 1018 | 755 | 3561 | — | — | — | — | holding_rolling_pin, holding_another's_finger, holding_anchor, imminent_hand_holding, holding_hands | guiding_hand, offering_hand, one_arm_handstand, holding_another's_arm, one-armed_hug |
| p-100-3 | 指尖明确指向前方 | pointing | 指点 | paraphrase | pose | 0 | 65269 | 85 | 83 | 435 | 4203 | — | — | — | — | pointing_forward, fingers_to_head, on_finger, pointing_to_the_side, sharp_tail | pointing_forward, holding_behind_neck, :v, vertical_foregrip, angled_foregrip |
| p-101-1 | 抬手向画面打招呼 | waving | 挥手 | paraphrase | pose | 0 | 26502 | 735 | 2418 | 37 | 2082 | — | — | — | — | reaching_towards_viewer, spoken_character, holding_picture_frame, holding_phone, holding_camera | hand_up, face_hug, palm-fist_greeting, fist_in_hand, \o/ |
| p-101-2 | 手掌左右摆动 | waving | 挥手 | paraphrase | pose | 0 | 26502 | 6723 | 15479 | 551 | 3246 | — | — | — | — | holding_handheld_game_console, one_arm_handstand, handheld_game_console, hands_under_legs, palms | arm_around_leg, arm_around_back, hand_around_wrist, arm_over_head, hands_on_lap |
| p-102-1 | 伸出食指和中指比出胜利手势 | v_sign | — | paraphrase | pose | 7 | 23170 | 43405 | 10206 | 24826 | 19497 | — | — | — | — | index_fingers_raised, double_ok_sign, index_finger_raised, holding_cue_stick, index_fingers_together | index_fingers_raised, holding_trophy, holding_binoculars, bent_v, double_inward_v |
| p-102-2 | 手指组成V形 | v_sign | — | paraphrase | pose | 7 | 23170 | 17097 | 1317 | 11817 | 22504 | — | — | — | — | v_arms, v, bent_v, v_formation, double_v | v_over_mouth, v-bangs, :v, veiny_hands, diamond_hands |
| p-102-3 | 做出剪刀手 | v_sign | — | paraphrase | pose | 7 | 23170 | 52228 | 45433 | 38356 | 44975 | — | — | — | — | v, holding_scissors, scissor_blade_(kill_la_kill), rock_paper_scissors, hand_on_blade | v, holding_scalpel, holding_cleaver, stitched_hand, holding_boxcutter |
| p-103-1 | 手里拿着一个东西 | holding | 手持 | paraphrase | action | 0 | 1354000 | 5 | 118 | 33 | 204 | — | — | — | — | holding_gift, holding_another's_finger, two-handed, holding_clothes_hanger, holding | holding_money, holding_wallet, holding_toy, holding_gift, holding_manga |
| p-103-2 | 双手把物品握住 | holding | 手持 | paraphrase | action | 0 | 1354000 | 2 | 315 | 8 | 80 | — | — | — | — | two-handed, holding, holding_flashlight, holding_figure, holding_gloves | holding_own_wrist, holding_gloves, holding_tissue, holding_tool, holding_toy |
| p-103-3 | 正在抓住物件 | holding | 手持 | paraphrase | action | 0 | 1354000 | 52 | 696 | 275 | 3647 | — | — | — | — | caught, captured, holding_cloak, clothes_grab, imminent_kick | vibrator, imminent_kiss, incoming_kiss, vest_lift, imminent_breast_grab |
| p-104-1 | 手臂伸出去够远处的东西 | reaching | 伸手够向 | paraphrase | action | 0 | 29748 | 51 | 274 | 568 | 1280 | — | — | — | — | outstretched_arm, outstretched_arms, arm_across_waist, convenient_arm, arm_at_side | arm_over_head, arm_held_back, hands_on_own_thighs, arm_across_neck, arm_behind_back |
| p-104-2 | 指尖努力向前够 | reaching | 伸手够向 | paraphrase | action | 0 | 29748 | 207 | 874 | 15 | 201 | — | — | — | — | fingers_to_head, pointing_forward, sharp_tail, strength_(tarot), on_finger | pointing_forward, tiptoes, hand_in_thighhighs, vest_lift, holding_binoculars |
| p-104-3 | 正要拿到目标 | reaching | 伸手够向 | paraphrase | action | 0 | 29748 | 121 | 700 | 18 | 149 | — | — | — | — | goal, achievement_unlocked, good_luck_knot, wishing_cairn_(e.g.o), chase_my_ideal_idol!_(project_sekai) | vest_lift, aiming_up, throwing, skill, pointing_forward |
| p-105-1 | 上半身朝前探 | leaning_forward | 前倾 | paraphrase | pose | 0 | 115911 | 140 | 120 | 899 | 678 | — | — | — | — | upper_body, lower_body, partially_underwater_shot, half_chest_guard, waist_apron | arm_over_head, front-tie_top, upper_body, head_back, front-tie_bikini_top |
| p-105-3 | 背部弯向镜头 | leaning_forward | 前倾 | paraphrase | pose | 0 | 115911 | 4101 | 7791 | 1512 | 567 | — | — | — | — | facing_back, facing_away, back_focus, criss-cross_back-straps, see-through_tank_top | facing_back, back, criss-cross_back-straps, back_focus, focus_(horizon) |
| p-106-1 | 身体正对着画面 | facing_viewer | 面向观众 | paraphrase | orientation | 0 | 62315 | 81 | 14 | 1094 | 324 | — | — | — | — | see-through_body, human_focus, stare_down, facing_back, bodypaint | facing_back, pov_across_bed, arm_over_head, bend, photocopying_self |
| p-106-2 | 正面面对观众 | facing_viewer | 面向观众 | paraphrase | orientation | 0 | 62315 | 1 | 1 | 6 | 1 | — | — | — | — | facing_viewer, reaching_towards_viewer, audience, viewer_on_leash, firing_at_viewer | looking_at_viewer, looking_past_viewer, audience, pointing_at_viewer, facing_back |
| p-106-3 | 胸口和脸都朝向镜头 | facing_viewer | 面向观众 | paraphrase | orientation | 0 | 62315 | 3647 | 1041 | 726 | 192 | — | — | — | — | chest_eye, face_to_breasts, arm_around_chest, face_to_pecs, see-through_bra | facing_back, pov_breasts, face_to_pecs, face_to_breasts, face_in_shadow |
| p-107-1 | 镜头从人物背后拍 | from_behind | 背面视角 | paraphrase | orientation | 0 | 232537 | 11 | 27 | 3 | 17 | — | — | — | — | facing_back, zooming_out, running_towards_viewer, lens, film_set | facing_back, grabbing_viewer, from_behind, grabbing_from_behind, under_shot |
| p-107-2 | 看到后背而不是脸 | from_behind | 背面视角 | paraphrase | orientation | 0 | 232537 | 1 | 4 | 6 | 14 | — | — | — | — | from_behind, sex_from_behind, facing_back, see-through_tank_top, hand_on_own_back | facing_back, facing_down, head_back, from_side, view_between_legs |
| p-107-3 | 人物背对画面 | from_behind | 背面视角 | paraphrase | orientation | 0 | 232537 | 5 | 11 | 8 | 181 | — | — | — | — | facing_back, person_on_back, back_focus, facing_away, from_behind | person_on_back, facing_back, piggyback, animal_on_face, breasts_on_another's_back |
| p-108-2 | 身体转成侧面 | profile | 侧脸 | paraphrase | orientation | 0 | 129076 | 28 | 51 | 32 | 1746 | — | — | — | — | transformation, from_side, transforming_clothes, facing_to_the_side, deformed_face | body_switch, rearing, breasts_on_another's_back, leaning_to_the_side, head_back |
| p-108-3 | 只看到一边脸 | profile | 侧脸 | paraphrase | orientation | 0 | 129076 | 124 | 128 | 16 | 177 | — | — | — | — | lower_lip_only, lower_eyelashes_only, one_eye_covered, covering_one_eye, single_empty_eye | facing_down, looking_inside, from_side, ;/, looking_to_the_side |
| p-109-1 | 人物回头看身后 | looking_back | 回眸 | paraphrase | orientation | 0 | 281064 | 91 | 2451 | 1 | 15 | — | — | — | — | looking_past_viewer, behind_another, arms_behind_back, hands_on_own_back, from_behind | looking_back, looking_past_viewer, rearing, from_behind, leaning_back |
| p-109-2 | 肩膀朝前但脸转回来 | looking_back | 回眸 | paraphrase | orientation | 0 | 281064 | 4411 | 8650 | 16 | 109 | — | — | — | — | front-to-back, arm_around_chest, arm_across_neck, arm_across_waist, bend | facing_back, head_back, legs_back, leaning_back, arm_over_head |
| p-109-3 | 越过肩膀往后看 | looking_back | 回眸 | paraphrase | orientation | 0 | 281064 | 1401 | 11938 | 38 | 1934 | — | — | — | — | looking_over_eyewear, see-through_tank_top, walking_towards_viewer, running_towards_viewer, see-through_shawl | view_between_legs, facing_back, lap_pov, looking_at_bulge, from_above |
| p-110-1 | 只画到胸口或腰部 | upper_body | 上半身 | paraphrase | camera | 0 | 772446 | 2730 | 414 | 932 | 5346 | — | — | — | — | ink_on_breast, breast_focus, bandaid_on_breast, bandaid_on_chest, waist_brooch | pectoral_squeeze, neck_corset, hip_focus, ink_on_breast, abs_peek |
| p-110-3 | 下半身不出镜 | upper_body | 上半身 | paraphrase | camera | 0 | 772446 | 66 | 70 | 50 | 2767 | — | — | — | — | lower_body, lowered_eyelids, half-closed_eyes, half-closed_eye, partially_opaque_glasses | bottomless, lower_body, medium_sideburns, dip_(dance_move), partially_undressed |
| p-111-1 | 从头到脚完整入镜 | full_body | 全身 | paraphrase | camera | 0 | 805933 | 1285 | 1123 | 994 | 6961 | — | — | — | — | feet_out_of_frame, full-length_mirror, see-through_tank_top, head_between_legs, soles_together | walking_towards_viewer, facing_back, head_back, arm_over_head, knees_to_chest |
| p-111-3 | 不裁掉脚部 | full_body | 全身 | paraphrase | camera | 0 | 805933 | 7604 | 3707 | 4918 | 15732 | — | — | — | — | censored_feet, bandaid_on_foot, feet_out_of_frame, butt_crush, camisole_removed | holding_own_leg, censored_feet, blood_on_feet, food_on_foot, separated_legs |
| p-112-1 | 画面截到大腿中段 | cowboy_shot | 牛仔镜头 | paraphrase | camera | 0 | 556396 | 9875 | 4889 | 4838 | 2615 | — | — | — | — | cropped_legs, wide_spread_legs, separated_legs, spread_legs, leg_cast | thigh_cutout, bandaid_on_thigh, view_between_legs, bound_thighs, thigh_focus |
| p-112-2 | 半身以下到大腿的构图 | cowboy_shot | 牛仔镜头 | paraphrase | camera | 0 | 556396 | 19847 | 13703 | 28774 | 24478 | — | — | — | — | cropped_torso, lower_body, stitched_leg, thigh_strap, half-timbered | pants_around_thighs, hand_between_thighs, bound_thighs, bikini_bottom_around_leg, lower_body |
| p-112-3 | 比头像更宽但不露全腿 | cowboy_shot | 牛仔镜头 | paraphrase | camera | 0 | 556396 | 14638 | 6902 | 12808 | 6944 | — | — | — | — | wide_spread_legs, head_between_legs, head_between_thighs, bikini_bottom_around_leg, legs_over_head | multiple_pov, bare_legs, view_between_legs, vest_lift, bound_thighs |
| p-113-1 | 镜头贴近脸部 | close-up | 特写 | paraphrase | camera | 0 | 46497 | 6304 | 27028 | 3828 | 13758 | — | — | — | — | bandaid_on_face, face_in_crotch, faceplant, shaded_face, shading_face | zooming_in, facing_back, putting_in_contact_lens, goggles_around_neck, holding_binoculars |
| p-113-2 | 只看脸和肩膀附近 | close-up | 特写 | paraphrase | camera | 0 | 46497 | 4970 | 23193 | 11026 | 22133 | — | — | — | — | arm_above_head, goggles_around_arm, face_hold, arm_on_own_head, see-through_tank_top | view_between_legs, looking_at_ass, sitting_on_face, facing_back, shoulder_peek |
| p-114-2 | 画面专注一个人的脸 | portrait | 肖像 | paraphrase | camera | 0 | 82065 | 254 | 408 | 636 | 2274 | — | — | — | — | face_hold, simulated_facial, grabbing_another's_face, facejob, drawing_on_another's_face | facing_back, human_focus, face_in_shadow, hand_on_another's_face, focus_(horizon) |
| p-114-3 | 正式头像式取景 | portrait | 肖像 | paraphrase | camera | 0 | 82065 | 202 | 159 | 46 | 290 | — | — | — | — | profile_picture, real_world_location, very_wide_shot, viewfinder, kaneki_profile_picture_(meme) | viewfinder, taking_picture, film_set, photo_shoot, polaroid_camera |
| p-115-2 | 镜头拉远留出大量背景 | wide_shot | 远景 | paraphrase | camera | 0 | 15927 | 6 | 5 | 23 | 9 | — | — | — | — | zooming_out, very_wide_shot, facing_back, facing_away, dithered_background | zooming_out, multiple_pov, zooming_in, very_wide_shot, facing_back |
| p-115-3 | 广角全景 | wide_shot | 远景 | paraphrase | camera | 0 | 15927 | 17 | 19 | 19 | 14 | — | — | — | — | panorama, traffic_mirror, holographic_horns, very_wide_shot, mosaic_background | panorama, focus_(horizon), pov_across_bed, very_wide_shot, seascape |
| p-116-1 | 画面故意倾斜 | dutch_angle | 荷兰角 | paraphrase | camera | 0 | 119425 | 10970 | 9953 | 15175 | 18120 | — | — | — | — | lopsided_border, asymmetrical_eyes, smear_frame, 6_9, hypnotizing_viewer | image_warping, screen_zoom, body_slam, facing_back, art_shift |
| p-116-2 | 地平线斜着 | dutch_angle | 荷兰角 | paraphrase | camera | 0 | 119425 | 1830 | 2231 | 2353 | 4727 | — | — | — | — | horizon, mountainous_horizon, leaning, lopsided_border, \|_\| | focus_(horizon), horizon, bent_over, leaning_back, upside-down |
| p-116-3 | 镜头不是水平的 | dutch_angle | 荷兰角 | paraphrase | camera | 0 | 119425 | 6318 | 5238 | 2308 | 12142 | — | — | — | — | non-circular_lens_flare, lens, zooming_out, facing_back, lens_eye | lens, blurry_vision, fixed-point_camera, quality, out-of-frame_censoring |
| p-117-1 | 画面只有一个人 | solo | 单人 | paraphrase | quantity | 0 | 5000954 | 40 | 117 | 3 | 572 | — | — | — | — | solo_focus, head_only, sound_effects_only, viewer_self-insert, single_empty_eye | sound_effects_only, single_vambrace, solo, solo_focus, single_sode |
| p-117-2 | 不要出现第二个人 | solo | 单人 | paraphrase | quantity | 0 | 5000954 | 1438 | 987 | 514 | 8091 | — | — | — | — | dual_persona, multiple_others, heart_hands_duo, no_one's_around_to_help_(meme), hands_on_another's_chest | 2others, no_u-turn_sign, multiple_others, redesign, gear_second |
| p-118-1 | 两个女生同时入镜 | 2girls | 双人女性 | paraphrase | quantity | 0 | 1021591 | 2 | 3 | 1 | 22 | — | — | — | — | shared_innertube, 2girls, two-tone_eyewear, two-tone_skirt, sucking_both_nipples | 2girls, two-tone_dress, female_pov, multiple_girls, two-tone_bodysuit |
| p-118-2 | 画面里有两位女孩 | 2girls | 双人女性 | paraphrase | quantity | 0 | 1021591 | 2 | 2 | 1 | 3 | — | — | — | — | multiple_girls, 2girls, girl_on_top, 6+girls, high_school_girls_posing_for_google_street_view_(meme) | 2girls, female_pov, 2others, girl_sandwich, high_school_girls_posing_for_google_street_view_(meme) |
| p-118-3 | 两名女性一起出现 | 2girls | 双人女性 | paraphrase | quantity | 0 | 1021591 | 1 | 1 | 1 | 3 | — | — | — | — | 2girls, multiple_girls, 1girl, bisexual_female, female_butler | 2girls, two-tone_dress, duet, multiple_girls, female_pov |
| p-119-1 | 一群女孩一起 | multiple_girls | 多名女性 | paraphrase | quantity | 0 | 1533521 | 1 | 1 | 5 | 30 | — | — | — | — | multiple_girls, 5girls, 6+girls, girl_on_top, 1girl | group_pose, gangbang, witches_5, cooking_together, multiple_girls |
| p-119-2 | 不止一个女生 | multiple_girls | 多名女性 | paraphrase | quantity | 0 | 1533521 | 3 | 1 | 1 | 8 | — | — | — | — | 1girl, virgin, multiple_girls, girl_on_top, girly_boy | multiple_girls, female_butler, 2girls, female_pov, other_with_female |
| p-119-3 | 多人女性场景 | multiple_girls | 多名女性 | paraphrase | quantity | 0 | 1533521 | 1 | 1 | 2 | 18 | — | — | — | — | multiple_girls, female_pov, mixed_maids, other_with_female, female_service_cap | female_pov, multiple_girls, multiple_others, multiple_pov, multiple_persona |
| p-120-1 | 只画出一只眼 | one_eye_visible | — | paraphrase | quantity | 7 | 206 | 6083 | 4583 | 1334 | 1146 | — | — | — | — | drawn_on_eyes, single_blank_eye, hair_over_one_eye, lower_eyelashes_only, spiral-only_eyes | one_eye_closed, bandage_over_one_eye, one-eyed, tears_from_one_eye, covering_one_eye |
| p-120-2 | 画面里只留单眼 | one_eye_visible | — | paraphrase | quantity | 7 | 206 | 2447 | 7201 | 9040 | 9738 | — | — | — | — | single_blank_eye, one_eye_covered, veil_over_one_eye, one_eye_closed, single_empty_eye | sound_effects_only, single_empty_eye, finger_to_face, one_eye_closed, ok_sign_over_eye |
| p-120-3 | 另一只眼不出现 | one_eye_visible | — | paraphrase | quantity | 7 | 206 | 1333 | 1257 | 4153 | 6415 | — | — | — | — | mark_under_both_eyes, hand_over_another's_eye, single_blank_eye, one_eye_closed, covering_another's_eye | looking_at_another, blurry_vision, no_heterochromia, hand_over_another's_eyes, missing_eye |
| p-121-1 | 两只眼睛都清楚可见 | eyes_visible_through_hair | 透发可见眼 | paraphrase | quantity | 0 | 74450 | 3 | 18 | 13 | 29 | — | — | — | — | eyes_visible_through_headwear, eyes_visible_through_eyewear, eyes_visible_through_hair, two-tone_eyes, mark_under_both_eyes | two-tone_eyes, two-tone_eyewear, eyes_visible_through_eyewear, multicolored_eyes, eyes_in_shadow |
| p-121-2 | 双眼同时入镜 | eyes_visible_through_hair | 透发可见眼 | paraphrase | quantity | 0 | 74450 | 269 | 1279 | 262 | 321 | — | — | — | — | mark_under_both_eyes, two-tone_eyewear, eyes_visible_through_eyewear, eyes_in_shadow, binoculars | double_eyepatch, compound_eyes, hybrid_sight, eyes_in_shadow, rear-view_mirror |
| p-121-3 | 不是只画一只 | eyes_visible_through_hair | 透发可见眼 | paraphrase | quantity | 0 | 74450 | 17723 | 23621 | 21187 | 24666 | — | — | — | — | single_blank_eye, single_mitten, single_horn, no_heterochromia, single_mechanical_hand | no_tattoo, single_strap, covering_one_nipple, single_wing, one_breast_out |
| p-122-1 | 画面只出现一只手 | single_hand | 单手 | paraphrase | quantity | 0 | 81 | 2 | 5 | 9 | 1 | — | — | — | — | single_mechanical_hand, single_hand, one_arm_handstand, arm_out_of_frame, single_mitten | one_arm_handstand, looking_at_hand, pov_hands, person_on_hand, single_mechanical_hand |
| p-122-3 | 另一只手不要出现 | single_hand | 单手 | paraphrase | quantity | 0 | 81 | 19 | 35 | 4 | 1 | — | — | — | — | no_hands, heart_hands_failure, hands_on_another's_chest, hand_on_another's_back, hand_on_another's_leg | single_mechanical_hand, one_arm_handstand, single_half_glove, single_hand, single_vambrace |
| p-123-1 | 两只手都在画面里 | multiple_hands | — | paraphrase | quantity | 0 | 618 | 4068 | 1026 | 6007 | 21989 | — | — | — | — | hand_between_legs, finger_frame_duo, two-handed, hand_grabbing_both_breasts, artist's_hand_in_frame | finger_frame_duo, two-handed, double_w, double_\n/, double_finger_gun |
| p-123-2 | 双手同时可见 | multiple_hands | — | paraphrase | quantity | 0 | 618 | 6416 | 1194 | 4497 | 20916 | — | — | — | — | own_hands_together, hand_on_another's_hand, hands_on_another's_waist, hands_on_another's_arms, hands_on_another's_arm | own_hands_together, blush_visible_through_hands, hands_on_another's_face, glowing_hands, hands_in_own_hair |
| p-123-3 | 一只手不够 | multiple_hands | — | paraphrase | quantity | 0 | 618 | 22921 | 4947 | 11632 | 24405 | — | — | — | — | too_many_hands, no_hands, wrong_hand, single_mechanical_hand, one_arm_handstand | one_arm_handstand, single_hand, wrong_hand, fewer_digits, small_hands |
| p-124-1 | 身上多长出额外手臂 | extra_arms | 多臂 | paraphrase | quantity | 0 | 10005 | 2 | 5 | 1 | 82 | — | — | — | — | extra_limbs, extra_arms, too_many_arms, oversized_forearms, extra_legs | extra_arms, thick_arm_hair, extra_hands, arm_over_head, extra_limbs |
| p-124-2 | 手臂数量超过正常两条 | extra_arms | 多臂 | paraphrase | quantity | 0 | 10005 | 12 | 62 | 10 | 494 | — | — | — | — | arms_up, thick_arms, too_many_arms, outstretched_arms, double_amputee | arm_over_head, index_fingers_raised, hands_on_own_thighs, x_arms, oversized_forearms |
| p-124-3 | 需要多只胳膊 | extra_arms | 多臂 | paraphrase | quantity | 0 | 10005 | 88 | 63 | 4 | 593 | — | — | — | — | too_many_hands, multiple_scarves, multiple_tattoos, too_many_arms, torso_only | extra_limbs, hands_on_own_thighs, multiple_bracelets, extra_arms, arm_over_head |
| p-125-1 | 画面里出现多余的手 | extra_hands | 多出的手 | paraphrase | quantity | 0 | 341 | 2 | 3 | 1 | 2 | — | — | — | — | too_many_hands, extra_hands, extra_fingers, large_hands, hand_size_difference | extra_hands, extra_fingers, multiple_legs, double_\m/, v_over_mouth |
| p-125-2 | 手的数量超过两只 | extra_hands | 多出的手 | paraphrase | quantity | 0 | 341 | 6 | 3 | 3 | 9 | — | — | — | — | too_many_hands, hand_between_legs, two-handed, heart_hands_failure, too_many | hand_size_difference, index_fingers_raised, extra_hands, two-handed, hands_on_own_thighs |
| p-125-3 | 额外手掌 | extra_hands | 多出的手 | paraphrase | quantity | 0 | 341 | 1 | 2 | 1 | 2 | — | — | — | — | extra_hands, hand_on_another's_hat, palms, hand_on_another's_hip, extra_horns | extra_hands, extra_fingers, extra_arms, extra_limbs, palms |
| p-126-1 | 一只手放到背后 | hand_behind_back | — | paraphrase | spatial | 7 | 5726 | 5161 | 859 | 994 | 4311 | — | — | — | — | arm_around_back, hand_on_another's_leg, hand_on_own_back, hand_on_another's_back, hands_on_another's_head | arm_around_back, one_arm_handstand, arm_behind_back, hand_on_another's_leg, holding_behind_neck |
| p-126-2 | 手掌藏在身体后面 | hand_behind_back | — | paraphrase | spatial | 7 | 5726 | 17039 | 896 | 1031 | 2873 | — | — | — | — | hand_on_another's_back, hand_on_own_back, arm_behind_leg, hands_on_another's_chest, hand_between_legs | arm_behind_back, arms_under_breasts, arm_behind_leg, arm_around_back, arms_behind_back |
| p-126-3 | 手臂绕到身后 | hand_behind_back | — | paraphrase | spatial | 7 | 5726 | 28697 | 1150 | 1141 | 1243 | — | — | — | — | arms_behind_back, arm_around_chest, hands_on_own_back, arm_around_leg, arm_behind_back | arm_held_back, arm_behind_back, arms_behind_back, arm_around_back, arm_across_neck |
| p-127-1 | 一只手撑着腰 | hand_on_hip | — | paraphrase | spatial | 7 | 56734 | 38601 | 25444 | 27486 | 18283 | — | — | — | — | hand_on_floor, hands_on_floor, glove_spread, hand_on_ground, hands_on_another's_waist | hand_on_another's_hip, hands_on_lap, hand_on_belt, hands_on_another's_hips, hand_on_another's_waist |
| p-127-2 | 单手扶住胯部 | hand_on_hip | — | paraphrase | spatial | 7 | 56734 | 38556 | 18184 | 32638 | 16035 | — | — | — | — | hand_on_another's_hip, hand_on_own_neck, hand_on_another's_neck, hand_on_own_opposite_hip, holding_behind_neck | single_elbow_pad, one_arm_handstand, hand_on_own_knee, single_wrist_cuff, single_bracer |
| p-127-3 | 手掌贴在腰侧 | hand_on_hip | — | paraphrase | spatial | 7 | 56734 | 36136 | 17978 | 22335 | 14455 | — | — | — | — | bandaid_on_neck, bandaid_on_hand, hand_on_another's_hip, heart-shaped_bandaid, bandaid_on_finger | hand_between_thighs, hand_on_belt, hand_on_another's_hip, hand_on_another's_waist, hands_on_lap |
| p-128-1 | 手伸到两腿之间 | hand_between_legs | 手置于两腿间 | paraphrase | spatial | 0 | 26866 | 1 | 1 | 1 | 5 | — | — | — | — | hand_between_legs, spread_legs, double_handjob, hands_on_another's_legs, arms_between_legs | hand_between_legs, hand_between_thighs, hands_on_another's_legs, hands_on_lap, arms_between_legs |
| p-128-2 | 手掌位于大腿中间 | hand_between_legs | 手置于两腿间 | paraphrase | spatial | 0 | 26866 | 2 | 2 | 5 | 12 | — | — | — | — | hands_on_own_thighs, hand_between_legs, head_between_legs, hand_between_thighs, hands_under_legs | hand_between_thighs, arm_between_legs, arm_on_thigh, arms_between_legs, hand_between_legs |
| p-128-3 | 手放在双腿内侧 | hand_between_legs | 手置于两腿间 | paraphrase | spatial | 0 | 26866 | 1 | 3 | 3 | 22 | — | — | — | — | hand_between_legs, arms_between_legs, hand_between_thighs, hand_on_another's_leg, arm_on_own_leg | hand_between_thighs, hands_on_own_thighs, hand_between_legs, arms_between_legs, arm_on_thigh |
| p-129-1 | 一侧头发把一只眼遮住 | hair_over_one_eye | 单眼遮盖 | paraphrase | spatial | 0 | 245322 | 1 | 4 | 1 | 8 | — | — | — | — | hair_over_one_eye, hair_over_eyes, hair_in_eyes, one_eye_covered, covering_one_eye | hair_over_one_eye, hair_over_face, hat_over_one_eye, hair_behind_eyewear, hair_over_one_breast |
| p-129-2 | 只有单眼被发丝盖住 | hair_over_one_eye | 单眼遮盖 | paraphrase | spatial | 0 | 245322 | 1 | 6 | 2 | 108 | — | — | — | — | hair_over_one_eye, veil_over_one_eye, one_eye_covered, lower_eyelashes_only, single_sidelock | single_hair_intake, hair_over_one_eye, bandage_over_one_eye, hair_behind_eyewear, single_empty_eye |
| p-129-3 | 头发挡住半边视线 | hair_over_one_eye | 单眼遮盖 | paraphrase | spatial | 0 | 245322 | 7 | 312 | 5 | 153 | — | — | — | — | hair_tubes_removed, half-closed_eyes, hair_over_eyes, hair_half_undone, hair_half_over_shoulder | hair_behind_eyewear, hair_over_face, hair_half_over_shoulder, hair_behind_ear, hair_over_one_eye |
| p-130-1 | 衣料垂到两腿之间 | clothes_between_thighs | 衣物夹于腿间 | paraphrase | spatial | 0 | 1489 | 2 | 7 | 1 | 2 | — | — | — | — | two-tone_legwear, clothes_between_thighs, separated_legs, bound_legs, double_flare_skirt_one-piece | clothes_between_thighs, two-tone_legwear, breast_clinging, clothes_between_breasts, gradient_legwear |
| p-130-2 | 布料夹在大腿中间 | clothes_between_thighs | 衣物夹于腿间 | paraphrase | spatial | 0 | 1489 | 1 | 1 | 1 | 11 | — | — | — | — | clothes_between_thighs, legjob, stitched_leg, leg_between_thighs, buttjob_under_clothes | clothes_between_thighs, leg_between_thighs, head_between_thighs, sword_between_thighs, bikini_bottom_around_leg |
| p-130-3 | 裙摆落入双腿缝隙 | clothes_between_thighs | 衣物夹于腿间 | paraphrase | spatial | 0 | 1489 | 10 | 100 | 2 | 38 | — | — | — | — | two-tone_legwear, skirt_caught_on_object, skirt_around_one_leg, wide_spread_legs, separated_legs | pants_tucked_in, clothes_between_thighs, legs_on_table, two-tone_legwear, head_between_thighs |
| p-131-1 | 裙子被拨到身体一侧 | skirt_aside | 裙摆侧撩 | paraphrase | spatial | 0 | 88 | 14 | 8 | 12 | 7 | — | — | — | — | skirt_caught_on_object, torn_skirt, torn_dress, leotard_aside, hand_under_dress | skirt_around_ankles, breast_clinging, skirt_tied_over_head, skirt_around_one_ankle, clothes_over_shoulder |
| p-131-2 | 一边裙摆掀开 | skirt_aside | 裙摆侧撩 | paraphrase | spatial | 0 | 88 | 10 | 10 | 4 | 3 | — | — | — | — | skirt_caught_on_object, dress_flip, dress_lift, swinging, swaying | skirt_flip, dress_lift, open_skirt, skirt_aside, apron_aside |
| p-131-3 | 布料移向侧面露出腿 | skirt_aside | 裙摆侧撩 | paraphrase | spatial | 0 | 88 | 2136 | 1890 | 63 | 34 | — | — | — | — | side-seamed_legwear, see-through_legwear, shiny_legwear, uneven_legwear, gradient_legwear | gradient_legwear, breast_clinging, pants_around_thighs, bikini_bottom_around_leg, side-tie_legwear |
| p-132-1 | 嘴边叼着烟 | smoking | 吸烟 | paraphrase | action | 0 | 23374 | 32 | 90 | 27 | 7452 | — | — | — | — | too_many_cigarettes, smoking_pipe_in_mouth, cigarette_holder, smoke, blowing_smoke | smoking_pipe_in_mouth, holding_smoking_pipe, toast_in_mouth, too_many_cigarettes, string_in_mouth |
| p-132-2 | 手里拿着点燃的香烟 | smoking | 吸烟 | paraphrase | action | 0 | 23374 | 37 | 100 | 17 | 2172 | — | — | — | — | holding_cigarette, lighting_cigarette, holding_cigarette_pack, cigarette, holding_fireworks | holding_cigarette, cigarette, holding_smoking_pipe, holding_fireworks, cigarette_candy |
| p-132-3 | 正吸着烟 | smoking | 吸烟 | paraphrase | action | 0 | 23374 | 1 | 3 | 1 | 31 | — | — | — | — | smoking, smoke, holding_smoking_pipe, smoke_ring, colored_smoke | smoking, cigarette, smoke, blowing_smoke, smoke_from_mouth |
| p-133-1 | 正把杯子送到嘴边 | drinking | 饮用 | paraphrase | action | 0 | 19190 | 156 | 1601 | 221 | 768 | — | — | — | — | cup_to_cheek, holding_cup, bottle_to_cheek, holding_beaker, cup_on_head | cup_to_cheek, cup_on_head, holding_juice_box, :v, thumb_to_mouth |
| p-133-2 | 手里端着饮料 | drinking | 饮用 | paraphrase | action | 0 | 19190 | 9 | 82 | 10 | 34 | — | — | — | — | holding_drink, drink_bag, drink, incoming_drink, drink_can | holding_drink, holding_juice_box, drink, drink_bag, holding_ice_cream |
| p-133-3 | 正在喝东西 | drinking | 饮用 | paraphrase | action | 0 | 19190 | 1 | 9 | 2 | 9 | — | — | — | — | drinking, holding_drink, drinking_glass, drink, incoming_drink | drink, drinking, drinking_from_condom, drinking_blood, drinking_from_bowl |
| p-134-1 | 嘴里正在吃东西 | eating | 进食 | paraphrase | action | 0 | 85306 | 107 | 278 | 7 | 48 | — | — | — | — | stutter, food_in_mouth, too_many_in_mouth, mouth_bubble, toast_in_mouth | food_in_mouth, toast_in_mouth, food_on_face, food_in_ass, utensil_in_mouth |
| p-134-2 | 手拿食物送入口中 | eating | 进食 | paraphrase | action | 0 | 85306 | 111 | 153 | 22 | 18 | — | — | — | — | food_on_hand, food_insertion, holding_food, finger_in_own_mouth, putting_on_gloves | holding_food, holding_utensil, food_on_hand, food_in_ass, utensil_in_mouth |
| p-135-1 | 手里摊着书在看 | reading | 阅读 | paraphrase | action | 0 | 17519 | 208 | 779 | 1443 | 3310 | — | — | — | — | against_bookshelf, hand_on_book, holding_book, holding_bookmark, floating_book | holding_book, bookshelf_pov, hand_on_book, book_strap, upside-down_book |
| p-135-3 | 正在翻书 | reading | 阅读 | paraphrase | action | 0 | 17519 | 60 | 1009 | 338 | 3812 | — | — | — | — | turning_page, through_page, floating_book, against_bookshelf, book | turning_page, book_on_head, through_page, book_to_mouth, against_bookshelf |
| p-136-1 | 手握笔在纸上写字 | writing | 书写 | paraphrase | action | 0 | 4310 | 184 | 579 | 345 | 2340 | — | — | — | — | writing_on_hand, holding_paper, holding_clipboard, paper_on_head, hand_on_book | holding_clipboard, writing_on_hand, holding_pencil, holding_paper, holding_paper_airplane |
| p-136-2 | 正在记录内容 | writing | 书写 | paraphrase | action | 0 | 4310 | 61 | 194 | 3 | 47 | — | — | — | — | log_pose, recording, recollection_(blue_archive), holding_newspaper, collection | recording, narration, writing, taking_notes, recorder |
| p-136-3 | 笔尖落在纸面 | writing | 书写 | paraphrase | action | 0 | 4310 | 445 | 749 | 237 | 3667 | — | — | — | — | paper_on_head, torn_paper, pen_in_pocket, falling_paper, paper_background | pen_behind_ear, pencil_behind_ear, falling_paper, clipboard, screentone |
| p-137-1 | 闭着眼睡着了 | sleeping | 睡觉 | paraphrase | action | 0 | 73398 | 36 | 167 | 4 | 29 | — | — | — | — | closing_eyes, closed_eyes, sleeping_with_eyes_open, ;/, unusually_open_eyes | ;/, sleeping_with_eyes_open, sleeping_on_person, sleeping, lying |
| p-137-2 | 人物躺着休息 | sleeping | 睡觉 | paraphrase | action | 0 | 73398 | 179 | 1054 | 50 | 991 | — | — | — | — | resting, character_pillow, sleepwalking, hypnotizing_viewer, person_on_shoulder | lying, resting, sitting_on_log, sitting_on_wall, sitting_on_person |
| p-137-3 | 进入睡眠状态 | sleeping | 睡觉 | paraphrase | action | 0 | 73398 | 8 | 17 | 14 | 111 | — | — | — | — | sleeping_with_eyes_open, sleeping_upright, sleeping_on_desk, feigning_sleep, zzz | sleeping_upright, sleeping_with_eyes_open, sleep_mask, open_pajamas, sleeping_on_desk |
| p-138-1 | 手里拿着手机 | holding_phone | 手持手机 | paraphrase | action | 0 | 50373 | 1 | 1 | 1 | 14 | — | — | — | — | holding_phone, cellphone, phone_in_pocket, smartphone, smartphone_case | holding_phone, holding_saxophone, looking_at_phone, holding_television, holding_tablet_pc |
| p-138-2 | 低头看屏幕 | holding_phone | 手持手机 | paraphrase | action | 0 | 50373 | 1219 | 1399 | 4609 | 22016 | — | — | — | — | looking_down, head_down, floating_screen, heads-up_display, cellphone_display | looking_down, blurry_vision, looking_at_screen, head_down, ;/ |
| p-138-3 | 正在操作移动电话 | holding_phone | 手持手机 | paraphrase | action | 0 | 50373 | 5 | 1 | 3 | 265 | — | — | — | — | corded_phone, cradling_phone, talking_on_phone, phone, holding_phone | talking_on_phone, holding_microphone, holding_phone, looking_at_phone, cellphone_vibrator |
| p-139-1 | 举起相机对着目标拍摄 | taking_picture | 拍照 | paraphrase | action | 0 | 7475 | 66 | 323 | 12 | 105 | — | — | — | — | action_camera, camera_around_neck, camera_hold_pose_(han-0v0), twin-lens_reflex_camera, holding_camera | action_camera, polaroid_camera, under_shot, facing_back, film_set |
| p-139-2 | 正在按快门 | taking_picture | 拍照 | paraphrase | action | 0 | 7475 | 12748 | 22580 | 15206 | 25696 | — | — | — | — | against_door, fast_forward_button, door, closing_door, open_door | fast_forward_button, pressing_button, rewind_button, button_prompt, imminent_breast_grab |
| p-140-2 | 把乱掉的发丝拨开 | adjusting_hair | 整理头发 | paraphrase | action | 0 | 20766 | 1349 | 213 | 33 | 4 | — | — | — | — | loose_hair_strand, stray_hair, hair_spread_out, sidelocks_tied_back, receding_hairline | untying_hair, loose_hair_strand, wringing_hair, adjusting_another's_hair, blunt_tresses |
| p-140-3 | 正在梳理发型 | adjusting_hair | 整理头发 | paraphrase | action | 0 | 20766 | 120 | 33 | 6 | 1 | — | — | — | — | hair_chart, borrowed_hairstyle, matching_hairstyle, flower-shaped_hair, folded_hair | brushing_own_hair, hair_pulled_back, sidecut, side_cut, fade_(haircut) |
| p-141-1 | 正在整理衣服褶皱 | adjusting_clothes | 整理衣物 | paraphrase | action | 0 | 25155 | 3 | 5 | 1 | 5 | — | — | — | — | wrinkled_fabric, pleated_shirt, adjusting_clothes, pleated_pants, pulling_own_clothes | adjusting_clothes, adjusting_sleeves, adjusting_another's_clothes, adjusting_shirt, adjusting_leotard |
| p-141-2 | 手在拉平衣料 | adjusting_clothes | 整理衣物 | paraphrase | action | 0 | 25155 | 410 | 172 | 51 | 437 | — | — | — | — | finger_under_clothes, hand_under_clothes, hand_under_shirt, hand_on_own_crotch, hand_in_clothes | hand_under_clothes, clothes_over_shoulder, finger_under_clothes, clothes_on_shoulders, hand_in_clothes |
| p-141-3 | 把服装重新摆好 | adjusting_clothes | 整理衣物 | paraphrase | action | 0 | 25155 | 10 | 3 | 1 | 3 | — | — | — | — | adjusting_another's_clothes, official_alternate_costume, opened_by_self, adjusting_collar, vintage_clothes | adjusting_clothes, dress-up, adjusting_dress, adjusting_headwear, redesign |
| hard-001-1 | 别把衣角收进裙头 | untucked_shirt | 衬衫下摆外露 | hard | negation | 0 | 2915 | 210 | 163 | 520 | 39 | — | shirt_tucked_in | 50 | 196 | hand_under_dress, sideless_dress, impossible_dress, no_u-turn_sign, unworn_dress | side-tie_skirt, side-tie_dress, unbuttoned_dress, skirt_tied_over_head, bodysuit_aside |
| hard-001-2 | 上衣下缘垂在腰线外 | untucked_shirt | 衬衫下摆外露 | hard | negation | 0 | 2915 | 232 | 213 | 852 | 10 | — | shirt_tucked_in | 520 | 1215 | jumpsuit_around_waist, alternate_sleeve_length, shirt_down, leotard_aside, underbutt | crop_top_overhang, off-shoulder_dress, cross-laced_top, clothes_around_waist, brown_tunic |
| hard-001-3 | 不要把衬衣扎进裤头 | untucked_shirt | 衬衫下摆外露 | hard | negation | 0 | 2915 | 41 | 17 | 516 | 13 | — | shirt_tucked_in | 706 | 963 | no_male_underwear, impossible_shirt, shirt_partially_tucked_in, no_scarf, shirt_under_shirt | shirt_around_waist, shirt_on_shoulders, flapper_shirt, downpants, shirt_under_shirt |
| hard-001-4 | 衣角留在外面别收进去 | untucked_shirt | 衬衫下摆外露 | hard | negation | 0 | 2915 | 41 | 36 | 172 | 3 | — | shirt_tucked_in | 3 | 84 | clothing_aside, head_under_another's_clothes, shirt_tucked_in, no_pants, from_inside | from_inside, side-tie_bikini_bottom, bikini_bottom_pull, bodysuit_aside, torn_underwear |
| hard-001-5 | 不要整理成塞进腰里的样子 | untucked_shirt | 衬衫下摆外露 | hard | negation | 0 | 2915 | 1308 | 1017 | 4825 | 207 | — | shirt_tucked_in | 6 | 1129 | no_detached_sleeves, sleeveless_blazer, jumpsuit_around_waist, see-through_midriff, yabuki_joe_in_a_chair_(meme) | adjusting_clothes, obi_spin, adjusting_legwear, adjusting_buruma, taking_shelter |
| hard-002-1 | 脚上什么都别套 | no_socks | 未穿袜 | hard | negation | 0 | 6326 | 311 | 1193 | 511 | 1032 | — | socks | 5675 | 2741 | barefoot_sandals_(jewelry), panties_around_one_ankle, bandaid_on_foot, foot_dangle, ankle_bow | bikini_bottom_around_leg, skirt_around_one_leg, shorts_around_one_leg, bound_ankles, unworn_legwear |
| hard-002-2 | 袜子拿掉 | no_socks | 未穿袜 | hard | negation | 0 | 6326 | 48 | 129 | 53 | 2203 | — | socks | 15 | 6 | single_sock_removed, pulling_off_legwear, legwear_cutout, removing_sock, unworn_socks | single_sock_removed, removing_sock, sock_pull, adjusting_sock, holding_sock |
| hard-002-3 | 腿脚露出来别穿袜 | no_socks | 未穿袜 | hard | negation | 0 | 6326 | 8 | 37 | 204 | 753 | — | socks | 850 | 252 | unworn_legwear, putting_on_legwear, unworn_kneehighs, uneven_legwear, unworn_thighhighs | lace-up_thighhighs, cum_on_legwear, loose_thighhigh, side-tie_legwear, thighhighs |
| hard-002-4 | 不要给脚穿袜 | no_socks | 未穿袜 | hard | negation | 0 | 6326 | 1 | 1 | 6 | 62 | — | socks | 252 | 24 | no_socks, unworn_legwear, unworn_kneehighs, unworn_socks, single_sock_removed | holding_sock, mismatched_thighhighs, stirrup_footwear, velcro_footwear, frilled_footwear |
| hard-002-5 | 光着脚踝和脚趾 | no_socks | 未穿袜 | hard | negation | 0 | 6326 | 2057 | 4542 | 23984 | 33236 | — | socks | 9176 | 4178 | light-skinned_soles, panties_around_one_ankle, pants_around_ankles, bandaid_on_foot, ankle_bow | wiggling_toes, blood_on_feet, ankle_ribbon, ankle_belt, ankle_scrunchie |
| hard-003-1 | 嘴巴张开 | open_mouth | 张嘴 | hard | state | 0 | 2365905 | 1 | 25 | 2 | 1071 | — | closed_mouth | 27 | 216 | open_mouth, gag, over_the_nose_gag, gagged, hand_gagged | bone_gag, open_mouth, spread_fingers, bit_gag, plug_gag |
| hard-003-2 | 上下嘴唇拉开一点 | open_mouth | 张嘴 | hard | state | 0 | 2365905 | 184 | 1398 | 134 | 9734 | — | closed_mouth | 171 | 1167 | thick_lips, lower_lip_only, soul_patch, labret_piercing, side_labret_piercing | mask_lift, vest_lift, bikini_bottom_lift, biting_another's_lip, licking_another's_lips |
| hard-003-3 | 露出嘴里面 | open_mouth | 张嘴 | hard | state | 0 | 2365905 | 34 | 713 | 13 | 4377 | — | closed_mouth | 187 | 142 | mouth_visible_through_hair, presenting_nipples, dildo_in_mouth, penis_out, dildo_reveal | presenting_nipples, hair_in_another's_mouth, hair_over_mouth, mouth_piercing, toast_in_mouth |
| hard-003-4 | 不要紧抿嘴唇 | open_mouth | 张嘴 | hard | state | 0 | 2365905 | 525 | 7456 | 273 | 7773 | — | closed_mouth | 576 | 119 | no_lips, licking_lips, lower_lip_only, licking_another's_lips, lips | licking_lips, licking_navel, biting_another's_lip, pursed_lips, licking_tip |
| hard-003-5 | 让嘴留一道开口 | open_mouth | 张嘴 | hard | state | 0 | 2365905 | 2 | 109 | 6 | 1430 | — | closed_mouth | 21 | 44 | mouth_pull, open_mouth, holding_another's_tongue, covering_own_mouth, extra_mouth | :v, mouth_pull, sideways_mouth, v_over_mouth, book_to_mouth |
| hard-004-1 | 双眼一起合上 | closed_eyes | 闭眼 | hard | quantity | 0 | 706552 | 854 | 1443 | 644 | 1060 | — | one_eye_closed | 3 | 49 | mark_under_both_eyes, thighs_together, one_eye_closed, eyes_in_shadow, covering_another's_eye | legs_together, thighs_together, soles_together, knees_apart_feet_together, compound_eyes |
| hard-004-2 | 两边眼皮都落下来 | closed_eyes | 闭眼 | hard | quantity | 0 | 706552 | 119 | 131 | 405 | 4219 | — | one_eye_closed | 66 | 9 | mark_under_both_eyes, two-tone_skin, eye_injury, eye_drops, lowered_eyelids | face_cutout, strap_slip, vaginal_prolapse, sunken_cheeks, blurry_vision |
| hard-004-3 | 两只眼都别睁着 | closed_eyes | 闭眼 | hard | quantity | 0 | 706552 | 24 | 99 | 27 | 329 | — | one_eye_closed | 3 | 1 | unusually_open_eyes, single_blank_eye, one_eye_closed, mark_under_both_eyes, covering_another's_eye | one_eye_closed, view_between_legs, blurry_vision, ;/, single_blank_eye |
| hard-004-4 | 像睡着一样闭住两眼 | closed_eyes | 闭眼 | hard | quantity | 0 | 706552 | 7 | 7 | 15 | 230 | — | one_eye_closed | 5 | 8 | sleeping_with_eyes_open, unusually_open_eyes, half-closed_eye, closing_eyes, one_eye_closed | sleeping_with_eyes_open, feigning_sleep, messy_sleeper, sleep_mask, ;/ |
| hard-004-5 | 不要只闭一边 | closed_eyes | 闭眼 | hard | quantity | 0 | 706552 | 299 | 2348 | 163 | 4752 | — | one_eye_closed | 9 | 3 | bodystocking_only, closing, single_over-kneehigh, single_shoulder_pad, single_fingerless_glove | side_drill, no_u-turn_sign, one_eye_closed, from_side, single_vambrace |
| hard-005-1 | 双眼睁开 | opening_eyes | 睁眼 | hard | state | 0 | 229 | 3 | 3 | 1 | 7 | — | closed_eyes | 13 | 17 | unusually_open_eyes, sleeping_with_eyes_open, opening_eyes, crying_with_eyes_open, lowered_eyelids | opening_eyes, one_eye_closed, unusually_open_eyes, ^_^, blinking |
| hard-005-2 | 眼睛全打开 | opening_eyes | 睁眼 | hard | state | 0 | 229 | 9 | 3 | 2 | 12 | — | closed_eyes | 16 | 74 | half-closed_eyes, unusually_open_eyes, half-closed_eye, eyes_out_of_frame, eye_of_providence | averting_eyes, opening_eyes, one_eye_closed, ok_sign_over_eye, eyelid_pull |
| hard-005-3 | 把眼皮抬起来 | opening_eyes | 睁眼 | hard | state | 0 | 229 | 72 | 47 | 41 | 390 | — | closed_eyes | 67 | 1222 | hands_up, blindfold_lift, glowing_pupils, glowing_eye, eye_piercing | visor_lift, eyelid_pull, hair_lift, adjusting_eyepatch, mask_lift |
| hard-005-4 | 不要闭着眼 | opening_eyes | 睁眼 | hard | state | 0 | 229 | 49 | 109 | 5 | 116 | — | closed_eyes | 5 | 8 | no_sclera, closing_eyes, ;/, no_goggles, closed_eyes | ;/, one_eye_closed, ^_^, closing_eyes, opening_eyes |
| hard-005-5 | 两边眼珠都露出来 | opening_eyes | 睁眼 | hard | state | 0 | 229 | 897 | 917 | 910 | 1598 | — | closed_eyes | 238 | 1522 | mark_under_both_eyes, eyes_visible_through_headwear, googly_eyes, eyes_in_shadow, covering_another's_eye | looking_at_bulge, blush_visible_through_hair, partially_visible_vulva, googly_eyes, view_between_legs |
| hard-006-1 | 只闭一边 | one_eye_closed | 单眼闭合 | hard | quantity | 0 | 431971 | 2 | 85 | 1 | 6171 | — | closed_eyes | 95 | 43 | closing, one_eye_closed, single_gauntlet, single_mitten, single_over-kneehigh | one_eye_closed, side_drill, closing, ;/, single_loose_sock |
| hard-006-2 | 一边睁着另一边合上 | one_eye_closed | 单眼闭合 | hard | quantity | 0 | 431971 | 3 | 137 | 46 | 9254 | — | closed_eyes | 3124 | 2548 | knees_apart_feet_together, hand_on_another's_knee, one_eye_closed, hand_on_another's_ass, bound_together | looking_at_another, facing_back, facing_another, pouring_onto_another, looking_away |
| hard-006-3 | 单眼眨着 | one_eye_closed | 单眼闭合 | hard | quantity | 0 | 431971 | 4 | 9 | 2 | 795 | — | closed_eyes | 61 | 83 | blinking, winking_(animated), one_eye_covered, one_eye_closed, single_blank_eye | single_blank_eye, one_eye_closed, ;/, tears_from_one_eye, blinking |
| hard-006-4 | 让另一只保持打开 | one_eye_closed | 单眼闭合 | hard | quantity | 0 | 431971 | 56 | 1103 | 2 | 2378 | — | closed_eyes | 2931 | 1426 | opening_another's_clothes, holding_another's_finger, separated_legs, open_skirt, open_fly | unbuckled, one_eye_closed, reloading, lockpick, head_on_another's_leg |
| hard-006-5 | 不要两只一起闭 | one_eye_closed | 单眼闭合 | hard | quantity | 0 | 431971 | 1 | 154 | 2 | 3886 | — | closed_eyes | 413 | 203 | one_eye_closed, closing, separated_legs, trick_or_treat, no_sclera | soles_together, one_eye_closed, bound_together, combination_wrench, sucking_both_nipples |
| hard-007-1 | 光脚踩地 | barefoot | 赤脚 | hard | state | 0 | 370744 | 399 | 5738 | 3785 | 24532 | — | shoes | 11492 | 5530 | light-skinned_soles, foot_on_head, foot_on_chest, foot_on_weapon, foot_on_arm | head_on_ground, foot_on_weapon, blood_on_feet, land_striker, wet_spot |
| hard-007-2 | 脚上别有鞋 | barefoot | 赤脚 | hard | state | 0 | 370744 | 435 | 2128 | 1731 | 13342 | — | shoes | 168 | 345 | uneven_footwear, no_toes, unworn_shoes, unworn_sandals, no_shoes | heel_pop, putting_on_footwear, alternate_footwear, censored_feet, blood_on_feet |
| hard-007-3 | 只露出脚趾 | barefoot | 赤脚 | hard | state | 0 | 370744 | 238 | 2852 | 2833 | 24286 | — | shoes | 4160 | 9921 | single_over-kneehigh, single_fingerless_glove, single_bare_foot, no_toes, feet_only | single_thighhigh, naked_gloves, censored_feet, feet_only, single_knee_pad |
| hard-007-4 | 鞋子脱掉直接走 | barefoot | 赤脚 | hard | state | 0 | 370744 | 6678 | 18407 | 12249 | 25106 | — | shoes | 61 | 314 | removing_shoes, shoe_loss, unworn_shoes, straight-laced_footwear, removing_coat | heel_pop, removing_shoes, removing_sock, single_sock_removed, dip_(dance_move) |
| hard-007-5 | 双脚直接碰到地面 | barefoot | 赤脚 | hard | state | 0 | 370744 | 434 | 2098 | 5036 | 23538 | — | shoes | 5794 | 7213 | feet_against_wall, soles_together, two-footed_footjob, mutual_foot_licking, double_footjob | through_ground, feet_against_wall, foot_dangle, land_striker, body_slam |
| hard-008-1 | 把鞋脱下来 | no_shoes | 未穿鞋 | hard | negation | 0 | 92856 | 227 | 140 | 308 | 6036 | — | shoes | 55 | 144 | unworn_shoes, removing_shoes, shoe_loss, single_sock_removed, removing_coat | removing_shoes, heel_pop, removing_sock, single_sock_removed, unbuckled |
| hard-008-2 | 脚边空着别放鞋 | no_shoes | 未穿鞋 | hard | negation | 0 | 92856 | 15 | 4 | 1149 | 8011 | — | shoes | 350 | 1342 | shoe_loss, foot_dangle, heel_pop, unworn_shoes, uneven_footwear | heel_pop, putting_on_footwear, head_on_another's_leg, holding_own_legs, bikini_bottom_around_leg |
| hard-008-3 | 不要穿任何鞋 | no_shoes | 未穿鞋 | hard | negation | 0 | 92856 | 1 | 1 | 1 | 7 | — | shoes | 283 | 1117 | no_shoes, uneven_footwear, no_socks, unworn_sandals, unworn_slippers | no_shoes, no_bodystocking, putting_on_footwear, no_scarf, alternate_footwear |
| hard-008-4 | 鞋子一双都没有 | no_shoes | 未穿鞋 | hard | negation | 0 | 92856 | 2 | 3 | 3 | 19 | — | shoes | 91 | 36 | uneven_footwear, no_shoes, unworn_shoes, no_scarf, unworn_sandals | disembodied_legs, mismatched_socks, no_shoes, single_shoe, two-tone_jacket |
| hard-008-5 | 让双脚露在外面 | no_shoes | 未穿鞋 | hard | negation | 0 | 92856 | 5667 | 3328 | 8124 | 14643 | — | shoes | 11778 | 6084 | feet_against_wall, foot_dangle, two-footed_footjob, mutual_foot_licking, panty_peek | separated_legs, feet_against_wall, spread_legs, side-tie_peek, censored_feet |
| hard-009-1 | 发梢到耳边就停 | short_hair | 短发 | hard | direction | 0 | 2261608 | 416 | 2089 | 13516 | 16942 | — | long_hair | 425 | 14730 | hair_around_ear, headphones_around_neck, hair_ears, scar_on_ear, hair_behind_ear | hair_behind_ear, headphones_around_neck, ears_back, hair_around_ear, ear_tufts |
| hard-009-2 | 不要垂过肩膀 | short_hair | 短发 | hard | direction | 0 | 2261608 | 3124 | 13789 | 8956 | 18665 | — | long_hair | 13182 | 8576 | no_scarf, no_stopping_sign, strapless_leotard, no_neckwear, no_harness | shoulder_pads, arm_over_shoulder, shoulder_strap, elbow_rest, arm_over_head |
| hard-009-3 | 头发剪得很短 | short_hair | 短发 | hard | direction | 0 | 2261608 | 2 | 3 | 5 | 75 | — | long_hair | 49 | 250 | very_short_hair, short_hair, short_hair_with_long_locks, pixie_cut, very_long_sidelocks | side_cut, very_short_hair, sidecut, fur-trimmed_capelet, short_hair |
| hard-009-4 | 颈部附近就是发尾 | short_hair | 短发 | hard | direction | 0 | 2261608 | 411 | 1180 | 11662 | 19741 | — | long_hair | 773 | 7818 | tail_around_neck, headband_around_neck, animal_around_neck, bandaid_on_neck, arm_across_neck | neck_corset, neck_piercing, neck_penetration, neck_tattoo, neck_bobbles |
| hard-009-5 | 发梢停在耳朵附近 | short_hair | 短发 | hard | direction | 0 | 2261608 | 721 | 3471 | 11633 | 18968 | — | long_hair | 548 | 13323 | hair_around_ear, headphones_around_neck, hair_ears, hair_behind_ear, scar_on_ear | headphones_around_neck, ear_tufts, ear_focus, hair_behind_ear, stethoscope_between_breasts |
| hard-010-1 | 发丝垂到腰 | long_hair | 长发 | hard | direction | 0 | 4350743 | 943 | 3742 | 5472 | 24251 | — | short_hair | 824 | 9326 | tightrope, hair_between_eyes, fur-trimmed_belt, floating_hair, hair_scarf | hair_over_crotch, hair_between_eyes, neck_corset, obi_spin, waist_sash |
| hard-010-2 | 头发留得很长 | long_hair | 长发 | hard | direction | 0 | 4350743 | 3 | 6 | 7 | 521 | — | short_hair | 52 | 1185 | very_long_hair, hair_length_switch, long_hair, very_long_sidelocks, absurdly_long_hair | very_long_hair, hair_over_face, hair_over_mouth, hair_behind_ear, hair_behind_eyewear |
| hard-010-3 | 不要剪成短发 | long_hair | 长发 | hard | direction | 0 | 4350743 | 567 | 604 | 153 | 4952 | — | short_hair | 1 | 3 | short_hair, short_hair_with_long_locks, pixie_cut, no_hairclip, very_short_hair | side_cut, shorts_aside, short_hair, sidecut, very_short_hair |
| hard-010-4 | 发丝一直垂到腰际 | long_hair | 长发 | hard | direction | 0 | 4350743 | 280 | 1533 | 2835 | 19793 | — | short_hair | 583 | 7419 | hair_between_eyes, hair_over_mouth, hair_on_horn, receding_hairline, hair_scarf | hair_over_crotch, hair_between_horns, hair_behind_eyewear, midriff_tattoo, hair_between_eyes |
| hard-010-5 | 发尾超过肩膀很多 | long_hair | 长发 | hard | direction | 0 | 4350743 | 462 | 258 | 1029 | 8149 | — | short_hair | 187 | 11866 | too_many_hair_ornaments, impossible_hair, extra_limbs, hair_over_shoulder, curly_ends | hair_over_shoulder, arm_over_head, head_between_thighs, legs_over_head, ponytail_over_shoulder |
| hard-011-1 | 画面只留一个人 | solo | 单人 | hard | quantity | 0 | 5000954 | 844 | 488 | 91 | 520 | — | 2girls | 16614 | 20081 | arm_out_of_frame, empty_picture_frame, single_empty_eye, solo_focus, face_of_the_people_who_sank_all_their_money_into_the_fx_(meme) | single_vambrace, sound_effects_only, single_boot, single_loose_sock, single_hair_tube |
| hard-011-2 | 不要安排第二个人 | solo | 单人 | hard | quantity | 0 | 5000954 | 6798 | 2872 | 2378 | 13686 | — | 2girls | 189 | 464 | trick_or_treat, trick-or-treating, hands_on_another's_chest, hand_on_another's_back, no_parking_sign | redesign, 2others, no_bodystocking, gear_second, take_your_pick |
| hard-011-3 | 镜头中只安排一位角色 | solo | 单人 | hard | quantity | 0 | 5000954 | 2241 | 1663 | 151 | 6384 | — | 2girls | 24212 | 18773 | viewer_self-insert, group_profile, running_towards_viewer, character_sticker, solo_focus | redesign, sound_effects_only, single_strap, one_breast_out, viewer_self-insert |
| hard-011-4 | 不需要两位女生同框 | solo | 单人 | hard | quantity | 0 | 5000954 | 15572 | 2257 | 11916 | 3444 | — | 2girls | 4 | 3 | finger_frame_duo, two-tone_eyewear, asymmetrical_dual_wielding, 2girls, multiple_others | finger_frame_duo, female_pov, 2girls, non-binary_flag, two-tone_dress |
| hard-011-5 | 只有一名角色 | solo | 单人 | hard | quantity | 0 | 5000954 | 46 | 363 | 4 | 1237 | — | 2girls | 13345 | 8038 | multiple_others, character_single, head_only, single_bare_shoulder, disembodied_torso | 1boy, sound_effects_only, 1girl, solo, redesign |
| hard-012-1 | 两个女生同框 | 2girls | 双人女性 | hard | quantity | 0 | 1021591 | 1 | 3 | 1 | 1 | — | solo | 17788 | 20823 | 2girls, finger_frame_duo, two-tone_eyewear, multiple_girls, girls'_power_(idolmaster) | 2girls, finger_frame_duo, female_pov, girl_sandwich, two-tone_dress |
| hard-012-2 | 画面里要有两位女孩 | 2girls | 双人女性 | hard | quantity | 0 | 1021591 | 1 | 2 | 1 | 1 | — | solo | 19855 | 19418 | 2girls, multiple_girls, core_(girls'_frontline), two-tone_skirt, 6+girls | 2girls, female_pov, two-tone_bra, dual_persona, duo_chromatic |
| hard-012-3 | 不要只放一个人 | 2girls | 双人女性 | hard | quantity | 0 | 1021591 | 7606 | 3429 | 6618 | 11419 | — | solo | 21 | 129 | lower_lip_only, hand_on_another's_back, single_fingerless_glove, anal_only, hand_on_another's_crotch | single_strap, single_slipper, single_vambrace, single_loose_sock, single_hair_intake |
| hard-012-4 | 两名女生一起出现 | 2girls | 双人女性 | hard | quantity | 0 | 1021591 | 1 | 1 | 1 | 1 | — | solo | 11646 | 9910 | 2girls, multiple_girls, 1girl, thighs_together, hand_grabbing_both_breasts | 2girls, twins, duo_chromatic, 2others, two-tone_dress |
| hard-012-5 | 一人不够，要两个人 | 2girls | 双人女性 | hard | quantity | 0 | 1021591 | 590 | 278 | 71 | 628 | — | solo | 115 | 27 | heart_hands_duo, implied_double_penetration, single_mitten, double_amputee, couple | fewer_digits, double_amputee, multiple_pov, single_mitten, single_half_glove |
| hard-013-1 | 只出现单眼 | one_eye_visible | — | hard | quantity | 7 | 206 | 2212 | 3772 | 1565 | 3979 | — | eyes_visible_through_hair | 121 | 230 | single_blank_eye, single_empty_eye, one_eye_covered, one_eye_closed, lower_eyelashes_only | single_empty_eye, single_blank_eye, one_eye_closed, sound_effects_only, solo_focus |
| hard-013-2 | 另一只眼不要入镜 | one_eye_visible | — | hard | quantity | 7 | 206 | 5192 | 5534 | 12644 | 10649 | — | eyes_visible_through_hair | 617 | 539 | no_goggles, no_eyewear, no_sclera, unworn_goggles, hand_over_another's_eyes | against_mirror, alternate_eyewear, averting_eyes, putting_in_contact_lens, blurry_vision |
| hard-013-3 | 画面只留一边眼睛 | one_eye_visible | — | hard | quantity | 7 | 206 | 3579 | 7820 | 15368 | 16486 | — | eyes_visible_through_hair | 99 | 931 | eyes_out_of_frame, one_eye_covered, one_eye_closed, veil_over_one_eye, covering_one_eye | blurry_vision, split_screen, from_side, facing_back, focus_(horizon) |
| hard-013-4 | 只能看到一只眼 | one_eye_visible | — | hard | quantity | 7 | 206 | 683 | 311 | 80 | 263 | — | eyes_visible_through_hair | 54 | 152 | one_eye_covered, one-eyed, covering_one_eye, single_blank_eye, spiral-only_eyes | blurry_vision, tears_from_one_eye, mask_over_one_eye, one_eye_closed, ;/ |
| hard-013-5 | 不要把两只眼都画出来 | one_eye_visible | — | hard | quantity | 7 | 206 | 27720 | 26358 | 13364 | 13318 | — | eyes_visible_through_hair | 1008 | 459 | mark_under_both_eyes, drawn_on_eyes, single_blank_eye, multiple_style_parody, no_eyepatch | view_between_legs, blurry_vision, multiple_pov, one_eye_closed, two-tone_skin |
| hard-014-1 | 只要一只手 | single_hand | 单手 | hard | quantity | 0 | 81 | 1 | 1 | 2 | 1 | — | multiple_hands | 29730 | 17598 | single_hand, single_mechanical_hand, one_arm_handstand, holding_another's_finger, torso_only | one_arm_handstand, single_hand, single_mechanical_hand, half-heart_hands, one-armed_hug |
| hard-014-2 | 另一只手不入镜 | single_hand | 单手 | hard | quantity | 0 | 81 | 74 | 76 | 15 | 2 | — | multiple_hands | 25129 | 14893 | hand_on_mirror, hand_mirror, hand_between_legs, hand_over_another's_eye, hand_on_another's_crotch | looking_at_hand, single_mechanical_hand, hand_over_another's_eyes, hand_on_another's_face, looking_at_hands |
| hard-014-3 | 画面里只露出一边胳膊的手 | single_hand | 单手 | hard | quantity | 0 | 81 | 20 | 108 | 719 | 7 | — | multiple_hands | 20403 | 19283 | arm_out_of_frame, blush_visible_through_hands, single_mechanical_hand, arm_above_head, single_sleeve_past_wrist | arm_out_of_frame, arms_under_breasts, naked_gloves, arm_held_back, single_vambrace |
| hard-014-4 | 双手不要同时出现 | single_hand | 单手 | hard | quantity | 0 | 81 | 50 | 66 | 110 | 4 | — | multiple_hands | 5082 | 5408 | own_hands_together, hands_on_another's_chest, hands_on_another's_head, too_many_hands, hands_on_another's_ass | hands_on_lap, hands_on_own_thighs, own_hands_together, hands_on_another's_arms, hands_on_hilt |
| hard-014-5 | 一只手就够了 | single_hand | 单手 | hard | quantity | 0 | 81 | 2 | 1 | 2 | 1 | — | multiple_hands | 30487 | 13637 | one_arm_handstand, single_hand, one-armed_hug, two-handed, single_mechanical_hand | one_arm_handstand, single_hand, half-heart_hands, single_mechanical_hand, two-handed_sword |
| hard-015-1 | 两只手一起出现 | multiple_hands | — | hard | quantity | 0 | 618 | 4044 | 1005 | 4602 | 16615 | — | single_hand | 11 | 113 | hand_between_legs, two-handed, two-handed_handjob, hand_grabbing_both_breasts, two-sided_gloves | two-handed, own_hands_together, hands_on_another's_arm, hands_on_another's_face, hand_on_another's_wrist |
| hard-015-2 | 两只手要同时出现在镜头里 | multiple_hands | — | hard | quantity | 0 | 618 | 13551 | 2729 | 10037 | 20997 | — | single_hand | 19 | 369 | hand_grabbing_both_breasts, hand_between_legs, double_handjob, finger_frame_duo, twin-lens_reflex_camera | twin-lens_reflex_camera, hands_on_another's_arm, double_\n/, double_finger_gun, double_face_punch |
| hard-015-3 | 要看到两只手 | multiple_hands | — | hard | quantity | 0 | 618 | 19722 | 2451 | 2736 | 7786 | — | single_hand | 5 | 80 | hand_grabbing_both_breasts, two-handed, hand_between_legs, two-handed_handjob, single_hand | looking_at_hand, two-handed, looking_at_hands, two-handed_sword, double_\n/ |
| hard-015-4 | 不要只画一只手 | multiple_hands | — | hard | quantity | 0 | 618 | 19745 | 1483 | 1993 | 4897 | — | single_hand | 2 | 1 | single_mechanical_hand, single_hand, no_hands, single_fingerless_glove, artist's_hand_in_frame | single_hand, single_mechanical_hand, one_arm_handstand, looking_at_hand, artist's_hand_in_frame |
| hard-015-5 | 手的数量至少两个 | multiple_hands | — | hard | quantity | 0 | 618 | 1120 | 291 | 6593 | 16888 | — | single_hand | 11 | 178 | two-handed, too_many_hands, two-sided_gloves, finger_counting, hand_between_legs | two-handed, two-handed_sword, double_\n/, double_\m/, index_fingers_raised |
| hard-016-1 | 正面看镜头 | facing_viewer | 面向观众 | hard | direction | 0 | 62315 | 72 | 48 | 150 | 16 | — | from_behind | 168 | 28 | lens, facing_back, lens_eye, running_towards_viewer, twin-lens_reflex_camera | facing_back, lens, walking_towards_viewer, looking_at_mirror, movie_camera |
| hard-016-2 | 胸口朝向画面 | facing_viewer | 面向观众 | hard | direction | 0 | 62315 | 1362 | 667 | 515 | 203 | — | from_behind | 255 | 73 | see-through_bra, chest_eye, head_on_chest, looking_at_breasts, heart_on_chest | pov_breasts, facing_back, bandaid_on_chest, breasts_on_another's_back, pectoral_squeeze |
| hard-016-3 | 面对观众站着 | facing_viewer | 面向观众 | hard | direction | 0 | 62315 | 7 | 2 | 2 | 2 | — | from_behind | 646 | 118 | stepping_on_viewer, reaching_towards_viewer, viewer_on_leash, peeing_on_viewer, firing_at_viewer | reaching_towards_viewer, facing_viewer, standing_on_liquid, standing_on_animal, looking_at_viewer |
| hard-016-4 | 不要背对镜头 | facing_viewer | 面向观众 | hard | direction | 0 | 62315 | 2020 | 741 | 610 | 29 | — | from_behind | 5 | 54 | facing_back, facing_away, ass-to-ass_penetration, against_chalkboard, from_behind | facing_back, facing_away, against_mirror, putting_in_contact_lens, non-circular_lens_flare |
| hard-016-5 | 从正面拍摄 | facing_viewer | 面向观众 | hard | direction | 0 | 62315 | 92 | 46 | 506 | 66 | — | from_behind | 26 | 10 | facing_back, film_set, recording, frontal_wedgie, photorealistic | facing_back, take_the_best_shot!_(project_sekai), photo_shoot, polaroid_camera, from_side |
| hard-017-1 | 只看背影 | from_behind | 背面视角 | hard | direction | 0 | 232537 | 5 | 60 | 6 | 15 | — | facing_viewer | 207 | 1072 | see-through_tank_top, back_focus, lower_eyelashes_only, torso_only, from_behind | ;/, sound_effects_only, blurry_vision, no_reflection, pov_peephole |
| hard-017-2 | 镜头在人物身后 | from_behind | 背面视角 | hard | direction | 0 | 232537 | 18 | 27 | 1 | 10 | — | facing_viewer | 380 | 56 | facing_back, looking_past_viewer, running_towards_viewer, facing_away, zooming_out | from_behind, facing_back, lens, walking_towards_viewer, looking_past_viewer |
| hard-017-3 | 脸不要出现 | from_behind | 背面视角 | hard | direction | 0 | 232537 | 1790 | 2502 | 470 | 1231 | — | facing_viewer | 4109 | 2076 | faceless, no_skin, in_the_face, faceless_male, faceless_female | hidden_face, face_cutout, face_in_shadow, not_present, face_filter |
| hard-017-4 | 人物背对相机 | from_behind | 背面视角 | hard | direction | 0 | 232537 | 11 | 35 | 19 | 173 | — | facing_viewer | 457 | 643 | facing_back, facing_away, holding_camera, person_on_back, back_focus | facing_back, person_on_back, holding_camera, mirror_selfie, camera_around_neck |
| hard-017-5 | 不要拍正面 | from_behind | 背面视角 | hard | direction | 0 | 232537 | 302 | 660 | 177 | 453 | — | facing_viewer | 736 | 976 | no_pupils, no_prosthetic_arm, no_harness, blurry_foreground, no_horns | negative, negative_space, facing_back, no_bodystocking, tap_out |
| hard-018-1 | 直视镜头 | looking_at_viewer | 看向观众 | hard | direction | 0 | 3315722 | 670 | 280 | 66 | 479 | — | looking_away | 1280 | 310 | running_towards_viewer, zooming_out, facing_back, zooming_in, grabbing_viewer | lens, facing_back, fixed-point_camera, x-ray_glasses, video_camera |
| hard-018-2 | 视线对着我 | looking_at_viewer | 看向观众 | hard | direction | 0 | 3315722 | 27 | 54 | 33 | 634 | — | looking_away | 313 | 345 | averting_eyes, vertical_eye_lines, eye_contact, blurry_vision, stare_down | facing_back, from_below, from_behind, eye_contact, pov_across_bed |
| hard-018-3 | 看向观看者 | looking_at_viewer | 看向观众 | hard | direction | 0 | 3315722 | 2 | 3 | 1 | 20 | — | looking_away | 19 | 38 | watching, looking_at_viewer, reaching_towards_viewer, viewer_holding_leash, looking_past_viewer | looking_at_viewer, looking_past_viewer, pointing_at_viewer, watching, reaching_towards_viewer |
| hard-018-4 | 不要把目光移开 | looking_at_viewer | 看向观众 | hard | direction | 0 | 3315722 | 1396 | 2807 | 25 | 1357 | — | looking_away | 412 | 5 | averting_eyes, no_pupils, no_eyebrows, no_sclera, unusually_open_eyes | averting_eyes, visor_lift, one_eye_closed, putting_in_contact_lens, looking_away |
| hard-018-5 | 眼睛对着画面 | looking_at_viewer | 看向观众 | hard | direction | 0 | 3315722 | 50 | 37 | 11 | 159 | — | looking_away | 1026 | 705 | eye_contact, vertical_eye_lines, averting_eyes, x-ray_vision, facing_back | facing_back, drawn_on_eyes, eye_contact, looking_at_screen, against_mirror |
| hard-019-1 | 别看镜头 | looking_away | 看向别处 | hard | direction | 7 | 27688 | 192 | 798 | 14 | 828 | — | looking_at_viewer | 256 | 31 | no_goggles, hidden_camera, zooming_out, non-circular_lens_flare, no_eyewear | blurry_vision, lens, zooming_out, facing_back, facing_away |
| hard-019-2 | 目光移到旁边 | looking_away | 看向别处 | hard | direction | 7 | 27688 | 132 | 314 | 7 | 236 | — | looking_at_viewer | 1078 | 86 | averting_eyes, looking_ahead, from_below, hair_behind_eyewear, walking_towards_viewer | facing_back, putting_in_contact_lens, looking_inside, looking_to_the_side, from_side |
| hard-019-3 | 视线避开观众 | looking_away | 看向别处 | hard | direction | 7 | 27688 | 1043 | 1138 | 355 | 937 | — | looking_at_viewer | 6 | 2 | attacking_viewer, peeing_on_viewer, insulting_viewer, stepping_on_viewer, firing_at_viewer | aiming_at_viewer, looking_at_viewer, averting_eyes, looking_past_viewer, blurry_vision |
| hard-019-4 | 不要和我对视 | looking_away | 看向别处 | hard | direction | 7 | 27688 | 413 | 2143 | 158 | 3293 | — | looking_at_viewer | 606 | 95 | stare_down, no_blindfold, unworn_vision_(genshin_impact), eye_contact, no_eyewear | ;/, blurry_vision, bad_perspective, no_one's_around_to_help_(meme), eye_contact |
| hard-019-5 | 视线转向旁边的区域 | looking_away | 看向别处 | hard | direction | 7 | 27688 | 51 | 233 | 48 | 764 | — | looking_at_viewer | 518 | 81 | pov_doorway, vertical_eye_lines, pov_across_table, pov_across_bed, running_towards_viewer | from_below, facing_back, from_behind, walking_towards_viewer, from_side |
| hard-020-1 | 手臂完全露出 | sleeveless | 无袖 | hard | state | 0 | 426734 | 2451 | 1416 | 20612 | 10858 | — | long_sleeves | 4608 | 16369 | completely_nude, full-body_blush, bare_arms, breasts_out, glowing_arms | arm_over_head, full-body_tattoo, arm_across_neck, arm_on_thigh, full-body_blush |
| hard-020-2 | 肩膀到腋下没有布 | sleeveless | 无袖 | hard | state | 0 | 426734 | 513 | 689 | 4912 | 433 | — | long_sleeves | 5167 | 18373 | no_bra, elbow_blush, strapless_bodysuit, no_scarf, strapless | armpit_cutout, bikini_bottom_around_leg, neck_corset, bad_neck, untied_bikini_bottom |
| hard-020-3 | 不要有袖子 | sleeveless | 无袖 | hard | state | 0 | 426734 | 10 | 3 | 33 | 11 | — | long_sleeves | 716 | 2247 | no_detached_sleeves, unworn_sleeves, no_neckwear, no_headwear, no_scarf | no_detached_sleeves, no_bodystocking, no_scarf, no_headwear, no_hairband |
| hard-020-4 | 两边胳膊裸着 | sleeveless | 无袖 | hard | state | 0 | 426734 | 799 | 475 | 22635 | 6277 | — | long_sleeves | 7392 | 12177 | naked_cape, hand_on_another's_ass, bare_arms, two-handed_masturbation, hands_on_own_ass | head_between_thighs, arms_at_sides, legs_on_another's_shoulders, side_chest_pose, naked_overalls |
| hard-020-5 | 上衣剪掉袖筒 | sleeveless | 无袖 | hard | state | 0 | 426734 | 2033 | 626 | 11448 | 2481 | — | long_sleeves | 1072 | 2703 | cutting_clothes, clothing_cutout, coat_partially_removed, arm_cutout, crotch_cutout | removing_bra_under_shirt, front-tie_top, crop_top_lift, crop_top_overhang, fur-trimmed_dress |
| r-001 | 衣服不要塞进裙子 | untucked_shirt | 衬衫下摆外露 | required-case | clothing | 0 | 2915 | 435 | 332 | 425 | 75 | — | shirt_tucked_in | 23 | 148 | sleeveless_dress, hand_under_dress, unworn_sleeves, no_detached_sleeves, sweater_under_dress | unbuttoned_dress, side-tie_skirt, clothes_between_breasts, side-tie_dress, dress_pants |
| r-002 | 让衬衣自然垂在裤子外面 | untucked_shirt | 衬衫下摆外露 | required-case | clothing | 0 | 2915 | 26 | 20 | 35 | 1 | — | shirt_tucked_in | 1008 | 933 | male_underwear_aside, panties_under_leotard, shirt_around_waist, shirt_overhang, panties_around_one_leg | vibrator_over_clothes, shirt_around_waist, shirt_over_dress, overshirt, shirttail |
| r-003 | 上衣别扎进去 | untucked_shirt | 衬衫下摆外露 | required-case | clothing | 0 | 2915 | 12 | 20 | 689 | 10 | — | shirt_tucked_in | 188 | 422 | finger_under_clothes, head_under_another's_clothes, sweater_tucked_in, hand_under_clothes, bodysuit_under_clothes | sweater_tucked_in, bodysuit_under_clothes, hand_under_clothes, underwear, open_bodysuit |
| r-004 | 衣摆留在外面 | untucked_shirt | 衬衫下摆外露 | required-case | clothing | 0 | 2915 | 1 | 2 | 40 | 1 | — | shirt_tucked_in | 540 | 389 | untucked_shirt, untucked, clothing_aside, clothes_over_shoulder, clothes_on_shoulders | vibrator_over_clothes, untucked, vibrator_under_clothes, panties_over_clothes, fur-trimmed_dress |
| r-005 | 不把衣服塞进裤腰 | untucked_shirt | 衬衫下摆外露 | required-case | clothing | 0 | 2915 | 387 | 192 | 1016 | 70 | — | shirt_tucked_in | 30 | 220 | pants_tucked_in, no_male_underwear, sleeveless_tunic, hand_in_pants, no_detached_sleeves | vibrator_over_clothes, clothes_around_waist, used_condom_in_clothes, clothes_between_breasts, downpants |
| r-006 | 不穿袜子 | no_socks | 未穿袜 | required-case | negation | 0 | 6326 | 1 | 4 | 1 | 6 | 1 | socks | 210 | 5 | no_socks, unworn_legwear, unworn_socks, unworn_kneehighs, unworn_thighhighs | no_socks, wet_socks, no_scarf, no_bodystocking, socks |
| r-007 | 腿上别有袜子 | no_socks | 未穿袜 | required-case | negation | 0 | 6326 | 12 | 64 | 72 | 456 | — | socks | 200 | 67 | unworn_legwear, putting_on_legwear, pants_around_one_leg, leg_belt, underwear_around_one_leg | alternate_legwear, cum_on_legwear, thighhigh_removed, towel_on_legs, loose_thighhigh |
| r-008 | 不要给她穿袜 | no_socks | 未穿袜 | required-case | negation | 0 | 6326 | 2 | 3 | 1 | 22 | — | socks | 532 | 12 | unworn_legwear, no_socks, unworn_kneehighs, unworn_thighhighs, unworn_pantyhose | no_socks, sockjob, removing_sock, frilled_footwear, velcro_footwear |
| r-009 | 脚上没有袜子 | no_socks | 未穿袜 | required-case | negation | 0 | 6326 | 1 | 6 | 8 | 76 | — | socks | 84 | 47 | no_socks, unworn_socks, unworn_kneehighs, unworn_legwear, panties_around_one_ankle | mismatched_thighhighs, thighhigh_dangle, censored_feet, disembodied_legs, unworn_thighhighs |
| r-010 | 袜子去掉 | no_socks | 未穿袜 | required-case | negation | 0 | 6326 | 48 | 116 | 68 | 1730 | — | socks | 7 | 9 | single_sock_removed, pulling_off_legwear, removing_sock, legwear_cutout, unworn_socks | single_sock_removed, removing_sock, sock_pull, adjusting_sock, pulling_off_legwear |
| r-013 | 把上衣边缘收进腰里 | shirt_tucked_in | 塞衣角 | required-case | clothing | 0 | 30535 | 46 | 165 | 621 | 3877 | — | untucked_shirt | 538 | 1919 | jumpsuit_around_waist, finger_under_clothes, sweater_tucked_in, hand_under_clothes, hand_in_underwear | clothes_around_waist, obi_bow, hand_under_clothes, obi_spin, shirt_around_waist |
| r-014 | 衣角整齐塞进裙腰 | shirt_tucked_in | 塞衣角 | required-case | clothing | 0 | 30535 | 1 | 2 | 6 | 317 | — | untucked_shirt | 819 | 1809 | shirt_tucked_in, jumpsuit_around_waist, clothes_around_waist, hand_under_dress, skirt_set | clothes_around_waist, adjusting_dress, side-tie_skirt, adjusting_skirt, tunic |
| r-015 | 下摆全部收好别露在外面 | shirt_tucked_in | 塞衣角 | required-case | clothing | 0 | 30535 | 4886 | 8903 | 12656 | 20413 | — | untucked_shirt | 2 | 148 | off-shoulder_jacket, untucked_shirt, sideless_outfit, untucked, off-shoulder_shirt | untucked, backless_bikini_bottom, one_breast_out, bikini_bottom_pull, bikini_bottom_lift |
| r-016 | 两只眼睛都合上 | closed_eyes | 闭眼 | required-case | quantity | 0 | 706552 | 168 | 209 | 474 | 2826 | — | one_eye_closed | 23 | 43 | mark_under_both_eyes, double_eyepatch, two_of_hearts, third_eye_on_chest, two-tone_eyes | two-tone_eyes, two-tone_eyewear, head_between_thighs, two-tone_vest, view_between_legs |
| r-017 | 不要睁眼 | closed_eyes | 闭眼 | required-case | negation | 0 | 706552 | 137 | 250 | 11 | 102 | — | one_eye_closed | 202 | 8 | sleeping_with_eyes_open, unusually_open_eyes, no_sclera, opening_eyes, lowered_eyelids | ;/, blurry_vision, opening_eyes, no_blindfold, no_eyepatch |
| r-018 | 只闭一只眼 | one_eye_closed | 单眼闭合 | required-case | quantity | 0 | 431971 | 1 | 1 | 1 | 402 | — | closed_eyes | 7 | 9 | one_eye_closed, one_eye_covered, unusually_open_eyes, closing_eyes, covering_one_eye | one_eye_closed, ;/, closing_eyes, single_blank_eye, covering_one_eye |
| r-019 | 双眼闭着 | closed_eyes | 闭眼 | required-case | quantity | 0 | 706552 | 4 | 6 | 5 | 37 | — | one_eye_closed | 2 | 4 | closing_eyes, one_eye_closed, third_eye_closed, closed_eyes, ;/ | ;/, closing_eyes, blurry_vision, one_eye_closed, closed_eyes |
| h-001 | 衬衫下摆不塞在裙子里 | untucked_shirt | 衬衫下摆外露 | real-world-holdout | holdout | 0 | 2915 | 1 | 1 | 10 | 1 | — | shirt_tucked_in | 65 | 111 | untucked_shirt, shirttail, shirt_on_shoulders, sideless_dress, skirt_caught_on_object | shirttail, shirt_over_dress, shirt_on_shoulders, shirt_under_sweater, shirt_around_waist |
| h-002 | 衬衫不塞进裙子 | untucked_shirt | 衬衫下摆外露 | real-world-holdout | holdout | 0 | 2915 | 17 | 11 | 45 | 1 | — | shirt_tucked_in | 12 | 73 | shirt_under_dress, shirt_over_dress, slip_showing, shirt_under_shirt, sweater_under_shirt | shirt_over_dress, shirt_on_shoulders, shirt_under_dress, shirt_around_waist, shirt_under_sweater |
| h-003 | 衬衫不扎进去 | untucked_shirt | 衬衫下摆外露 | real-world-holdout | holdout | 0 | 2915 | 5 | 2 | 53 | 2 | — | shirt_tucked_in | 156 | 121 | shirt_partially_tucked_in, impossible_shirt, unbuttoned_shirt, shirt_partially_removed, untucked_shirt | shirt_under_shirt, shirt_around_waist, shirt_partially_tucked_in, sweater_tucked_in, sweater_under_shirt |
| h-004 | 衣摆放在外面 | untucked_shirt | 衬衫下摆外露 | real-world-holdout | holdout | 0 | 2915 | 2 | 4 | 46 | 1 | — | shirt_tucked_in | 452 | 648 | untucked, untucked_shirt, clothes_over_shoulder, clothing_aside, off-shoulder_dress | vibrator_over_clothes, untucked, bikini_over_clothes, panties_over_clothes, adjusting_clothes |
| h-005 | 高中制服，衬衫下摆不要塞进裙子里 | untucked_shirt | 衬衫下摆外露 | real-world-holdout | holdout | 0 | 2915 | 3 | 2 | 18 | 1 | — | shirt_tucked_in | 340 | 331 | shirttail, youtou_high_school_uniform, untucked_shirt, sideless_dress, salt_middle_school_uniform | shirt_on_shoulders, shirt_over_dress, shirttail, shirt_around_waist, layered_shorts |
| h-006 | shirt not tucked in | untucked_shirt | 衬衫下摆外露 | real-world-holdout | holdout | 0 | 2915 | 18 | 6 | 9 | 1 | — | shirt_tucked_in | 20 | 4 | tucked_shirt, tight_t-shirt, sleeveless_turtleneck_shirt, shirtless, undone_shirt | tucked_shirt, t-shirt_only, shirt_only, shirt_tucked_in, tugging_clothing |
| h-007 | シャツの裾を出す | untucked_shirt | 衬衫下摆外露 | real-world-holdout | holdout | 0 | 2915 | 745 | 2015 | 396 | 2 | — | shirt_tucked_in | 1945 | 267 | tan_headwear, tan_t-shirt, corrugated_waist, :>, >_< | shirt_tug, shirttail, head_up_shirt, shirt_lift, flapper_shirt |
| h-008 | 把衬衫塞进裙子里 | shirt_tucked_in | 塞衣角 | real-world-holdout | holdout | 0 | 30535 | 5 | 7 | 107 | 233 | — | untucked_shirt | 44 | 83 | shirt_under_dress, shirt_over_dress, sweater_under_shirt, shirt_under_shirt, shirt_tucked_in | shirt_on_shoulders, shirt_over_dress, shirt_under_dress, shirt_under_shirt, shirt_under_sweater |
| h-009 | shirt tucked into skirt | shirt_tucked_in | 塞衣角 | real-world-holdout | holdout | 0 | 30535 | 7 | 3 | 15 | 2 | — | untucked_shirt | 41 | 1036 | tucked_shirt, cum_through_shirt, cum_through_skirt, horizontal-striped_skirt, tight_t-shirt | tucked_shirt, tight_skirt, tight_coat, studded_clothing, striped_t-shirt |
| h-010 | 衬衫只塞进去一半 | shirt_partially_tucked_in | 衬衫半扎 | real-world-holdout | holdout | 0 | 780 | 2 | 2 | 2 | 6 | — | untucked_shirt | 25 | 208 | shirt_partially_removed, shirt_partially_tucked_in, sweater_partially_tucked_in, cardigan_partially_removed, partially_undressed | shirt_partially_removed, shirt_partially_tucked_in, shirt_around_waist, sweater_partially_tucked_in, shirt_under_sweater |
| h-012 | 没穿袜子 | no_socks | 未穿袜 | real-world-holdout | holdout | 0 | 6326 | 1 | 4 | 1 | 3 | 1 | socks | 177 | 30 | no_socks, unworn_socks, unworn_legwear, unworn_pantyhose, unworn_kneehighs | no_socks, no_bodystocking, no_scarf, no_pants, no_cardigan |
| h-013 | wearing no socks | no_socks | 未穿袜 | real-world-holdout | holdout | 0 | 6326 | 2 | 8 | 7 | 5 | — | socks | 288 | 6458 | toeless_socks_(marking), no_socks, toeless_footwear, crotchless_bottomwear, socks_only | socks_only, footless_socks, no_underwear, putting_on_socks, crotchless_clothing |
| h-015 | 嘴巴闭着 | closed_mouth | 闭嘴 | real-world-holdout | holdout | 0 | 1167588 | 1 | 1 | 1 | 2 | — | open_mouth | 83 | 39 | closed_mouth, :p, stutter, mouth_bubble, clenched_teeth | closed_mouth, :p, ;/, :/, closing |
| h-017 | 两只眼睛都闭上 | closed_eyes | 闭眼 | real-world-holdout | holdout | 0 | 706552 | 7 | 8 | 3 | 42 | — | one_eye_closed | 1 | 1 | one_eye_closed, third_eye_closed, closing_eyes, half-closed_eyes, unusually_open_eyes | one_eye_closed, closing_eyes, closed_eyes, ;/, half-closed_eyes |
| h-018 | 只闭上一只眼睛 | one_eye_closed | 单眼闭合 | real-world-holdout | holdout | 0 | 431971 | 1 | 1 | 1 | 344 | — | closed_eyes | 10 | 10 | one_eye_closed, unusually_open_eyes, one_eye_covered, covering_one_eye, single_blank_eye | one_eye_closed, ;/, covering_one_eye, single_blank_eye, closing_eyes |
| h-019 | 头发很短 | short_hair | 短发 | real-world-holdout | holdout | 0 | 2261608 | 2 | 3 | 2 | 17 | — | long_hair | 25 | 35 | very_short_hair, short_hair, short_hair_with_long_locks, tiny_head, pixie_cut | very_short_hair, short_hair, low-braided_long_hair, low-tied_long_hair, low-tied_medium_hair |
| h-020 | 头发很长 | long_hair | 长发 | real-world-holdout | holdout | 0 | 4350743 | 2 | 1 | 2 | 138 | — | short_hair | 53 | 1055 | very_long_hair, long_hair, very_long_sidelocks, hair_length_switch, absurdly_long_hair | very_long_hair, long_hair, tall_hair, hair_floating_upwards, thick_hair |

## Appendix B. Leakage-excluded cases

这些样例被保留用于审计，但不进入主指标：

| id | source | query | target | existing label | reason |
| --- | --- | --- | --- | --- | --- |
| p-015-2 | paraphrase | 穿校服上课的感觉 | school_uniform | 校服 | zh_cn |
| p-016-2 | paraphrase | 上下装统一的制服感 | uniform | 制服 | zh_cn |
| p-017-2 | paraphrase | 上身加一层夹克 | jacket | 夹克 | zh_cn |
| p-020-3 | paraphrase | 身上裹着大衣 | coat | 大衣 | zh_cn |
| p-022-1 | paraphrase | 脚上穿着成对的袜子 | socks | 袜子 | zh_cn |
| p-027-1 | paraphrase | 穿露趾凉鞋 | sandals | 凉鞋 | zh_cn |
| p-027-3 | paraphrase | 鞋底是凉鞋 | sandals | 凉鞋 | zh_cn |
| p-028-2 | paraphrase | 穿高跟鞋 | high_heels | 高跟鞋 | zh_cn |
| p-029-1 | paraphrase | 脚上是运动鞋 | sneakers | 运动鞋 | zh_cn |
| p-030-1 | paraphrase | 小腿套着靴子 | boots | 靴子 | zh_cn |
| p-032-1 | paraphrase | 一整条连裤袜连到腰 | pantyhose | 连裤袜 | zh_cn |
| p-034-2 | paraphrase | 运动紧身裤包住腿 | leggings | 紧身裤 | zh_cn |
| p-042-2 | paraphrase | 看向别处不看画面 | looking_away | 看向别处 | zh_cn |
| p-044-2 | paraphrase | 眼神斗鸡眼 | cross-eyed | 斗鸡眼 | zh_cn |
| p-049-1 | paraphrase | 一只眼睛被眼罩盖住 | eyepatch | 眼罩 | zh_cn |
| p-049-2 | paraphrase | 黑色眼罩遮着眼 | eyepatch | 眼罩 | zh_cn |
| p-055-3 | paraphrase | 皱眉撇嘴 | frown | 皱眉 | zh_cn |
| p-059-1 | paraphrase | 说话时露出牙齿 | teeth | 牙齿 | zh_cn |
| p-060-1 | paraphrase | 咬紧牙关 | clenched_teeth | 咬紧牙关 | zh_cn |
| p-061-3 | paraphrase | 害羞得脸红 | blush | 脸红 | zh_cn |
| p-063-1 | paraphrase | 眼神和表情显得惊讶 | surprised | 惊讶 | zh_cn |
| p-066-3 | paraphrase | 短发造型 | short_hair | 短发 | zh_cn |
| p-067-3 | paraphrase | 长发披在身后 | long_hair | 长发 | zh_cn |
| p-070-1 | paraphrase | 后脑勺扎一束马尾 | ponytail | 马尾 | zh_cn |
| p-070-3 | paraphrase | 单条马尾垂下 | ponytail | 马尾 | zh_cn |
| p-073-1 | paraphrase | 把头发编成辫子 | braid | 辫子 | zh_cn |
| p-081-3 | paraphrase | 蓬松的卷发 | curly_hair | 卷发 | zh_cn |
| p-085-3 | paraphrase | 头顶有发带装饰 | hair_ribbon | 发带 | zh_cn |
| p-087-3 | paraphrase | 保持坐姿 | sitting | 坐姿 | zh_cn |
| p-092-2 | paraphrase | 一只脚抬起正在行走 | walking | 行走 | zh_cn |
| p-094-3 | paraphrase | 正做跳跃动作 | jumping | 跳跃 | zh_cn |
| p-101-3 | paraphrase | 正在挥手 | waving | 挥手 | zh_cn |
| p-105-2 | paraphrase | 身体向前倾过去 | leaning_forward | 前倾 | zh_cn |
| p-108-1 | paraphrase | 侧脸轮廓清楚 | profile | 侧脸 | zh_cn |
| p-110-2 | paraphrase | 构图集中在上半身 | upper_body | 上半身 | zh_cn |
| p-111-2 | paraphrase | 全身都在画面里 | full_body | 全身 | zh_cn |
| p-113-3 | paraphrase | 特写构图 | close-up | 特写 | zh_cn |
| p-114-1 | paraphrase | 像人物肖像照一样构图 | portrait | 肖像 | zh_cn |
| p-115-1 | paraphrase | 人物在远景中很小 | wide_shot | 远景 | zh_cn |
| p-117-3 | paraphrase | 单人构图 | solo | 单人 | zh_cn |
| p-122-2 | paraphrase | 只露单手 | single_hand | 单手 | zh_cn |
| p-134-3 | paraphrase | 画面表现进食 | eating | 进食 | zh_cn |
| p-135-2 | paraphrase | 低头阅读文字 | reading | 阅读 | zh_cn |
| p-139-3 | paraphrase | 画面里有人拍照 | taking_picture | 拍照 | zh_cn |
| p-140-1 | paraphrase | 手指正在整理头发 | adjusting_hair | 整理头发 | zh_cn |
| r-011 | required-case | 穿袜子 | socks | 袜子 | zh_cn |
| r-012 | required-case | 给她穿上袜子 | socks | 袜子 | zh_cn |
| h-014 | real-world-holdout | 穿着袜子 | socks | 袜子 | zh_cn |

## Appendix C. Artifact pointers

- Case manifest: `tool/.tmp/semantic-search/paraphrase/cases.json`
- Machine-readable summary: `tool/.tmp/semantic-search/paraphrase/summary.json`
- Benchmark source: `tool/semantic_search/semantic_paraphrase_benchmark.py`
- This renderer: `tool/semantic_search/render_semantic_paraphrase_report.py`
