# E5 local deployment (development)

The user selected E5-small for the Android prototype. The application now wires
`E5CompletionSource` into `CompletionOrchestrator`, separately from the lexical
`FastTagService`. Lexical results appear first; a 250 ms debounce starts semantic
retrieval and stale responses are ignored. Exact/prefix/contains matches keep
their existing priority; semantic fallback rows retain cosine ordering rather
than being reordered by popularity. Already-used tags still appear last.

Only Chinese queries of at least two characters and general categories are
eligible. Library aliases, related-tag requests, author/series/character filters
and English lookups retain their existing behavior. Up to 50 semantic results
come from all 54,879 category 0/7 candidates. Scores are similarity, not calibrated
confidence: unrelated or ambiguous queries may still return poor suggestions.

Display translations use the shared FastTagService resolver: reviewed catalog
corrections, installed dictionary, and bundled gap-fillers take precedence.
Missing labels fall back to the existing Chinese strings in the E5 tags asset.
This lightweight, cached lookup also supports English search results without
starting ONNX inference. It respects the existing translation visibility and
locale gates; it does not generate translations or replace dictionary updates.

## Resources

`assets/semantic_search/manifest.json` locks the model revision, the existing
catalog/dictionary, and each artifact's size and SHA-256. The four large files
are generated local assets and ignored by Git. They total approximately 222 MB
uncompressed; APK compression and installed size have not yet been measured.

The model is `intfloat/multilingual-e5-small`, revision
`614241f622f53c4eeff9890bdc4f31cfecc418b3`. Its source artifact is
`onnx/model_qint8_avx512_vnni.onnx`, locally named `model.onnx`. Runtime uses
standard ONNX CPU operators with two intra-op threads, not QNN/NPU. Its filename
does not establish ARM compatibility. Loading and inference have been exercised
on the API 35 x86_64 Android emulator; ARM64 phone validation remains pending.
The 384-dimensional matrix contains the frozen canonical English
tag plus existing Chinese translation, with E5 passage prefix, mean pooling
and L2 normalization. No query fixtures are included in the production pack.

Files are copied into versioned app-support storage and verified before model
loading. Android copies large assets through the existing streaming asset
channel; an isolate owns tokenizer, model, vectors, pooling and full-corpus
similarity. Loading is lazy on the first eligible query, and results have a
32-query memory cache. No model, vector pack or query cache is registered with
the application's cloud-sync data types. Failed initialization retains lexical
completion and allows a retry after a 30-second cooldown.

## Prepare on another checkout

Obtain the pinned model/tokenizer and an existing ffdkj dictionary matching the
manifest. `prepare_e5_pack.py` validates them, reuses a matching local benchmark
matrix if present and otherwise requires explicit `--build-vectors`. It never
downloads or translates implicitly, and rejects output differing from the lock.

```powershell
tool/.tmp/semantic-search/venv/Scripts/python.exe tool/semantic_search/prepare_e5_pack.py
# Only if no verified candidate cache exists (CPU work):
tool/.tmp/semantic-search/venv/Scripts/python.exe tool/semantic_search/prepare_e5_pack.py --build-vectors
```

The reference environment uses Python 3.12, NumPy 2.4.6, ONNX Runtime 1.30.0 and
tokenizers 0.22.2. Regeneration uses batches of 64 in deterministic length order.
Cross-runtime floating-point/quantization differences must be reviewed rather
than silently changing the pack. A clean CI/release checkout must provision the
four verified assets before publishing this feature; an independently hosted
release pack has not been published by this task.

## Validation status and next run

Before the user's no-start instruction, the Dart tokenizer matched the pinned
Hugging Face tokenizer on 567 reference inputs. Its NFKC/metaspace adaptation is
covered by those inputs, not a claim of complete Unicode-normalizer equivalence.
Queries use `query: `, explicit XLM-R start/end tokens and a 128-token maximum.

The bounded ranking/orchestrator regression batch passes 22 tests. The Android
debug APK builds and launches on Aaalice_API35 (x86_64); the complete debug APK
is 482,057,219 bytes, not the incremental model cost or a release APK estimate.
Cold semantic initialization returns results in the real prompt completion UI.
`不穿袜子` returns `no_socks` first and selecting it inserts `no_socks, `.
`上衣别扎进去` returns `untucked_shirt` fifth. `双手叉在腰上` finds
`hands_on_own_hips`. Positive/negative prompt lookup, consecutive query changes,
clearing/canceling the popup, and English `no_socks` lookup were exercised.

`让衬衣自然垂在裤子外面` retrieves `untucked_shirt` lower in the list (after
the first 15 rows), while a one-query Python run ranks it 13th. Other close
neighbors also differ in ordering between runtimes. Exact embedding parity is
not established; ranking is not guaranteed identical to the offline benchmark.
Driver lookup of the not-yet-built row timed out; manual driver scrolling then
exposed its widget. The later scrollIntoView/tap attempt also timed out, so
selection of this long-query result is not counted as a passed UI check.
These driver errors are not model-loading failures. No model-loading exception
or app crash was observed; emulator frame/IME warnings remain in the logs.

ARM64 phone inference, release-mode latency/memory, physical IME typing,
deliberately corrupted-pack recovery and category-filter UI scenarios remain
pending. Do not substitute emulator or offline scores for these checks. The
emulator's separate Chinese display dictionary is not installed; semantic
retrieval still works, but its footer says the dictionary is not installed.
