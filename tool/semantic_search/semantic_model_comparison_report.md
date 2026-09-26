# Semantic Model Comparison

## 1. Executive Summary

E5-small remains the practical baseline. Best Top-20 gain is +0.6 pp (M3E-small); this is below the 4 pp meaningful-advantage threshold, so there is no evidence to replace E5-small yet.

## 2. Dataset

- Reused clean manifest: `E:\AI-Dev-Environment\Projects\Aaalice_NAI_Launcher\tool\.tmp\semantic-search\paraphrase\cases.json`; original clean cases: **512**.
- Production-relevant subset: **495** (excluded **17** manually reviewed reverse-negation cases).
- Candidates unchanged: category 0 + 7, **54879** tags.
- Document A: canonical English tag + existing `zh_cn`; no aliases, generated translations, or online calls.

Excluded IDs: hard-005-4, hard-006-5, hard-009-2, hard-010-3, hard-011-2, hard-011-4, hard-012-3, hard-013-2, hard-013-5, hard-014-2, hard-014-4, hard-015-4, hard-016-4, hard-018-4, hard-019-1, hard-019-4, r-017

## 3. Models

| Model | Revision | Dim | ONNX bytes | Model SHA-256 | Encoding |
|---|---|---:|---:|---|---|
| E5-small | `614241f622f53c4eeff9890bdc4f31cfecc418b3` | 384 | 118,346,824 | `dd476dd0c2514e9b9be83aeb3853fac0763e0bdf4a71645407587d77c48a2d88` | E5 query:/passage: prefixes; mean pooling; L2 |
| M3E-small | `main (downloaded model files; SHA-256 recorded below)` | 512 | 94,844,758 | `08618a60586084c71eeca03418c7e64e71ef4a78da338357c5830f1bd2f69bfb` | plain text; mean pooling; L2 (SentenceTransformers-compatible) |
| BGE-small-zh-v1.5 | `main (Xenova conversion; SHA-256 recorded below)` | 512 | 94,851,877 | `69a0b846f4f116b5e6aabf9546ea6754d02264f3211a13a1bd69b31b8040749a` | BGE Chinese retrieval instruction on queries; mean pooling; L2 |

## 4. Main Results

| Model | N | Top-1 | Top-5 | Top-20 | Top-50 | MRR@10 | Median rank |
|---|---:|---:|---:|---:|---:|---:|---:|
| E5-small | 495 | 10.1% | 24.0% | 37.6% | 45.9% | 16.5% | 77 |
| M3E-small | 495 | 8.9% | 23.6% | 38.2% | 49.3% | 15.1% | 59 |
| BGE-small-zh-v1.5 | 495 | 7.5% | 19.4% | 31.5% | 40.2% | 12.5% | 132 |

### By subset

| Subset | E5 Top20 | M3E Top20 | BGE Top20 | N |
|---|---:|---:|---:|---:|
| paraphrase | 34.9% | 38.6% | 30.4% | 378 |
| real-world-holdout | 88.2% | 64.7% | 58.8% | 17 |
| required-case | 68.8% | 43.8% | 43.8% | 16 |

## 5. Required Case Comparison

| Query | Expected | E5 rank / Top-5 | M3E rank / Top-5 | BGE rank / Top-5 |
|---|---|---|---|---|
| 衣服不要塞进裙子 | `untucked_shirt` | 130 / sleeveless_dress, hand_under_dress, sleeveless_coat, impossible_dress, unworn_skirt | 711 / aoqun, impossible_dress, culottes, skirt, coat_dress | 1233 / impossible_dress, asymmetrical_dress, fortress, side-tie_dress, asymmetrical_pants |
| 让衬衣自然垂在裤子外面 | `untucked_shirt` | 13 / panties_under_leotard, shirt_overhang, male_underwear_aside, underwear_around_one_leg, panties_around_one_leg | 9 / shirt_over_dress, shirt_under_dress, dress_shirt, shirttail, tight_shirt | 2 / side-tie_shirt, untucked_shirt, bodysuit_aside, tied_shirt, overshirt |
| 上衣别扎进去 | `untucked_shirt` | 6 / sweater_tucked_in, head_under_another's_clothes, finger_under_clothes, hand_under_clothes, shibari_under_clothes | 265 / shirt, no_shirt, head_up_shirt, tight_top, shirt_lift | 221 / sweater_tucked_in, impossible_underwear, shirt_partially_tucked_in, impossible_shirt, head_under_another's_clothes |
| 衣摆留在外面 | `untucked_shirt` | 2 / untucked, untucked_shirt, clothing_aside, clothes_over_shoulder, clothes_on_shoulders | 8 / shirttail, untucked, purple_dress_shirt, shirt, shirt_over_dress | 2 / untucked, untucked_shirt, overshirt, defenestration, undershirt_peek |
| 不把衣服塞进裤腰 | `untucked_shirt` | 122 / no_male_underwear, sleeveless_tunic, pants_tucked_in, unworn_panties, no_leotard | 864 / sagging_pants, sleeveless_tunic, lowleg_pants, tunic, belt | 3233 / asymmetrical_pants, asymmetrical_shorts, mismatched_pants, downpants, side-tie_panties |
| 不穿袜子 | `no_socks` | 1 / no_socks, unworn_socks, unworn_legwear, unworn_pantyhose, unworn_kneehighs | 8 / thighhighs, latex_legwear, heel-less_legwear, lace_thighhighs, toeless_legwear | 4 / unworn_thighhighs, mismatched_thighhighs, unworn_socks, no_socks, single_thighhigh |
| 腿上别有袜子 | `no_socks` | 2 / unworn_legwear, no_socks, unworn_kneehighs, unworn_socks, putting_on_legwear | 45 / thighhighs, lace_thighhighs, latex_legwear, two-tone_thighhighs, white_thighhighs | 84 / pantyhose_around_legs, thighhighs_under_pantyhose, latex_legwear, latex_thighhighs, pantyhose_around_one_leg |
| 不要给她穿袜 | `no_socks` | 1 / no_socks, unworn_legwear, unworn_socks, unworn_kneehighs, no_pants | 64 / lace_thighhighs, thighhighs, single_thighhigh, single_kneehigh, single_detached_legging | 35 / thighhighs_under_pantyhose, mismatched_thighhighs, partially_toeless_legwear, pantyhose_under_shorts, two-tone_pantyhose |
| 脚上没有袜子 | `no_socks` | 1 / no_socks, unworn_socks, unworn_kneehighs, unworn_legwear, unworn_pantyhose | 4 / thighhighs, no_toes, stirrup_footwear, no_socks, bodystocking | 3 / unworn_thighhighs, unworn_socks, no_socks, unworn_legwear, unworn_pantyhose |
| 袜子去掉 | `no_socks` | 19 / single_sock_removed, pulling_off_legwear, unworn_socks, leg_cutout, legwear_cutout | 143 / single_sock_removed, pulling_off_legwear, removing_sock, bodystocking, thighhighs | 126 / single_sock_removed, adjusting_sock, thighhigh_removed, thighhigh_dangle, two-tone_thighhighs |
| 把上衣边缘收进腰里 | `shirt_tucked_in` | 93 / jumpsuit_around_waist, hand_under_clothes, finger_under_clothes, sweater_tucked_in, jacket_around_waist | 1232 / sleeveless_tunic, tight_top, tunic, shirt, jacket_around_waist | 1136 / side-tie_leotard, crop_top_overhang, side-tie_shorts, edging_underwear, top_pull |
| 衣角整齐塞进裙腰 | `shirt_tucked_in` | 1 / shirt_tucked_in, jumpsuit_around_waist, hand_under_skirt, skirt_set, hand_under_dress | 25 / sleeveless_tunic, high-waist_dress, lowleg_skirt, obi, tight_dress | 3 / side-tie_dress, adjusting_apron, shirt_tucked_in, amemiya_taiyou_(mixi_max_zhuge_kongming), side-tie_skirt |
| 下摆全部收好别露在外面 | `shirt_tucked_in` | 6073 / untucked_shirt, off-shoulder_bandeau, untucked, off-shoulder_jacket, sideless_outfit | 22331 / untucked, back_cutout, dress_tug, public_nudity, bottomless | 19001 / untucked, untucked_shirt, side-tie_peek, downpants, partially_visible_vulva |
| 两只眼睛都合上 | `closed_eyes` | 215 / mark_under_both_eyes, two-tone_eyes, double_eyepatch, third_eye_on_chest, eye_injury | 12 / =_=, <|>_<|>, no_eyes, two_tone_eyes, two_tone_eyebrows | 691 / eyes_visible_through_eyewear, bisexual_flag, among_us_eyes_(meme), one_eye_closed, eyes_visible_through_headwear |
| 只闭一只眼 | `one_eye_closed` | 1 / one_eye_closed, single_blank_eye, unusually_open_eyes, covering_one_eye, one_eye_covered | 16 / =_=, closed_eyes, no_eyes, <|>_<|>, closing_eyes | 6 / single_blank_eye, ^_^, unusually_open_eyes, no_eyes, ;/ |
| 双眼闭着 | `closed_eyes` | 7 / one_eye_closed, third_eye_closed, closing_eyes, half-closed_eyes, ;/ | 1 / closed_eyes, ;/, closing_eyes, one_eye_closed, ^_^ | 8 / single_blank_eye, ^_^, unusually_open_eyes, ;/, eyes_visible_through_eyewear |
| 衣服别塞进裙腰 | `untucked_shirt` | 93 / sweater_tucked_in, hand_under_dress, hand_under_clothes, shirt_tucked_in, hand_under_skirt | 1195 / obi, culottes, gym_shirt, high-waist_dress, shirt_around_waist | 1110 / side-tie_dress, asymmetrical_dress, shorts_under_dress, tied_dress, impossible_dress |
| 脚踝到脚趾都不套袜子 | `no_socks` | 2 / panties_around_one_ankle, no_socks, unworn_legwear, unworn_kneehighs, no_toes | 45 / stirrup_footwear, thighhighs, toes, no_toes, sweaty_foot | 29 / unworn_legwear, socks_over_pants, thighhighs_over_pantyhose, unworn_thighhighs, ankle_garter |
| 双手叉在腰上 | `hands_on_hips` | 32361 / hands_on_own_hips, hand_on_own_hip, hands_on_own_legs, hand_on_own_leg, hands_on_own_thighs | 3057 / hand_on_own_hip, hands_on_own_hips, harpoon, bident, fork | 26451 / bident, hand_on_own_hip, hands_on_another's_hips, snagharpoon_(e.g.o), crossed_legs |
| 一只手撑着腰 | `hand_on_hip` | 44836 / hand_on_floor, hand_on_ground, hands_on_floor, hand_on_own_hip, hands_on_another's_waist | 6535 / i_heart..., <|>_<|>, <o>_<o>, \m/, =_= | 20739 / spreader_bar, reaching, shoulder_support, glove_spread, hand_on_another's_hip |
| 伸出食指和中指比出胜利手势 | `v_sign` | 38918 / double_ok_sign, index_fingers_together, index_fingers_raised, holding_cue_stick, symmetrical_hand_pose | 29791 / o_arms, l_hand, hand_gesture, gesture, w | 32230 / che_vuoi?_(italian_gesture), pointing_with_thumb, spoken_thumbs_up, thumb, offering_hand |
| 左右各扎一束 | `double_ponytail` | 43719 / one_side_up, single_hair_intake, alternate_sleeve_length, scarf_on_head, side_drill | 1772 / tie-dye, half_updo, ;<, single_hair_intake, hair_up | 27572 / tail_between_breasts, pride_flag_question_mark_(meme), for_the_better_right?_(meme), just_as_planned_(meme), take_the_best_shot!_(project_sekai) |
| 把衣服往上掀露出腰 | `clothing_lift` | 32568 / downpants, underwear_reveal_pose_(han-0v0), jumpsuit_around_waist, hand_under_clothes, vibrator_under_clothes | 4925 / shirt_lift, shirt_around_waist, sleeveless_tunic, sagging_pants, shirt | 49905 / downpants, underwear_reveal_pose_(han-0v0), dress_aside, tied_sweater, crop_top_overhang |
| 衬衫扣子解开几颗 | `unbuttoned_shirt` | 1 / unbuttoned_shirt, shirt_partially_removed, unbuttoning, shirttail, shirt_straps | 1 / unbuttoned_shirt, unbuttoned, unbuttoning, shirttail, shirt_under_shirt | 1 / unbuttoned_shirt, unbuttoned, unbuttoning, unbuckled, open_shirt |
| 只合上一边眼皮 | `one_eye_closed` | 1 / one_eye_closed, lower_eyelashes_only, covering_one_eye, lower_lip_only, stitched_eye | 31 / monolids, no_eyes, eyelid_pull, <|>_<|>, extra_eyes | 12 / monolids, lower_eyelashes_only, partially_blind, disembodied_legs, eyes_visible_through_headwear |
| 双眼完全合拢 | `closed_eyes` | 707 / thighs_together, legs_together, knees_apart_feet_together, mark_under_both_eyes, two-tone_eyes | 10 / single_blank_eye, extra_eyes, no_eyes, double_eyepatch, <|>_<|> | 136 / eye_of_providence, bisexual_flag, thighs_together, eyes_visible_through_eyewear, one_eye_closed |
| 视线直直对着画面 | `looking_at_viewer` | 77 / vertical_eye_lines, rotating_view, vertical_monitor, averting_eyes, blurry_vision | 116 / blurry_vision, from_above, from_side, ;/, lazy_eye | 5131 / mischievous_straight_uniform_(blue_archive), how_to_draw_manga_redraw_challenge_(meme), on-model_vs_in_your_style_challenge, massugu_go, what_i_watched_what_i_expected_what_i_got_(meme) |
| 镜头从人物背后拍 | `from_behind` | 5 / facing_back, zooming_out, film_set, facing_away, from_behind | 112 / facing_back, movie_camera, photo_background, lens, film_set | 3 / facing_away, facing_back, from_behind, lens, arm_behind_another's_back |

## 6. BGE Chinese-only Ablation

| Variant | Top-1 | Top-5 | Top-20 | Top-50 | MRR@10 | Median rank |
|---|---:|---:|---:|---:|---:|---:|
| BGE-A (tag + zh_cn) | 7.5% | 19.4% | 31.5% | 40.2% | 12.5% | 132 |
| BGE-ZH (zh_cn only; English fallback) | 9.3% | 24.2% | 41.0% | 48.7% | 16.0% | 56 |

## 7. Performance

| Model | File | RSS delta MB | Cold load median/P95 ms | Query embedding median/P95 ms | Similarity median/P95 ms | Total median/P95 ms |
|---|---:|---:|---:|---:|---:|---:|
| E5-small | 118.3 MB | 191.6 | 1156.7/1221.0 | 3.4/3.5 | 2.6/2.8 | 6.0/6.3 |
| M3E-small | 94.8 MB | 92.5 | 152.7/161.4 | 2.8/3.5 | 3.4/4.2 | 6.3/7.1 |
| BGE-small-zh-v1.5 | 94.9 MB | 92.5 | 169.7/198.0 | 5.2/6.5 | 3.7/4.3 | 8.8/11.9 |

RSS is the process working-set change after loading the ONNX session; it is approximate and includes runtime overhead. Windows CPU timings are not Snapdragon 8 Gen 3 Android timings.

## Reproduction

```powershell
tool/.tmp/semantic-search/venv/Scripts/python.exe tool/semantic_search/semantic_model_comparison.py --threads 2 --batch 64
```

## 8. Recommendation

Keep E5-small as the Android prototype baseline. Neither M3E nor BGE shows a meaningful enough Top-20 improvement on the production-relevant subset to justify a model switch; continue only with targeted Android profiling if a Chinese-only BGE path is otherwise attractive. Continued horizontal swapping among same-size embedding models may have limited returns.
