# 随包中文词库（AME）

数据来自 [amenorira/danbooru-tags-data-zh](https://github.com/amenorira/danbooru-tags-data-zh)（MIT，`source_lock.json` 固定提交 `5805e470`）。它在应用里有两个用途：

- `assets/zh_lexicon/ame_lexicon.json.gz`：通用、角色、作品、元标签的中文译名与中文别名。
  - 由 `AmeZhLexicon` 提供中文反查，例如“红白”“碧蓝档案”“麻花辫”；
  - 同时是翻译的最后一级兜底，排在人工修正、已安装的 ffdkj、目录补充和 E5 标签之后。
  - 画师表不纳入：它的 zh 列多为日文原名，会给普通中文查询带来噪声。
- `assets/semantic_search/`：通用标签的译名、别名和一句话注释作为 E5 语义检索的额外视图，由 `tool/semantic_search/prepare_e5_pack.py` 生成。

标签名先按精确同名映射到 `tag_catalog.db`，再依次尝试目录别名表、AME 别名列里的旧标签名；只映射到同一分类族。锁定的哈希对应 GitHub 原始字节（UTF-8 BOM、LF）。Windows 开启 autocrlf 的 git 检出与之不同，请用 `--fetch` 获取。

```powershell
# 项目根目录；首次或更新 source_lock.json 后加 --fetch（仅此时联网）
tool/.tmp/semantic-search/venv/Scripts/python.exe tool/zh_lexicon/build_lexicon.py --fetch
tool/.tmp/semantic-search/venv/Scripts/python.exe -m unittest discover -s tool/zh_lexicon -p "test_*.py"
```

输出是确定性的（gzip `mtime=0`），`assets/zh_lexicon/manifest.json` 记录源文件、目录库哈希与条目数，`test/core/autocomplete/ame_zh_lexicon_test.dart` 会校验随包文件与清单一致。

DanbooruSearchOnline 的 `tags_enhanced.csv` 为 GPL-3.0，与本项目的 MIT 许可不兼容，只用于 `tool/.tmp` 内的离线对照评测，不进入任何随应用分发的文件。
