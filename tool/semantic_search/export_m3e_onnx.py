"""Export the downloaded moka-ai/m3e-small encoder to a plain ONNX graph.

This is an offline benchmark helper only.  It deliberately exports the
Transformer hidden states; the evaluation harness applies the same attention
mask mean pooling and L2 normalization used by SentenceTransformers.
"""
from pathlib import Path
import argparse
import json
import shutil


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-length", type=int, default=128)
    args = parser.parse_args()
    model_dir = args.model_dir.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    import torch
    from transformers import AutoModel, AutoTokenizer

    # Loading strictly from the downloaded directory prevents accidental
    # network access and makes the benchmark reproducible.
    tokenizer = AutoTokenizer.from_pretrained(model_dir, local_files_only=True)
    model = AutoModel.from_pretrained(model_dir, local_files_only=True)
    model.eval()

    encoded = tokenizer(
        ["示例查询", "another example"],
        padding="max_length",
        truncation=True,
        max_length=args.max_length,
        return_tensors="pt",
    )
    # Inspect the signature and retain only arguments accepted by this model.
    import inspect
    accepted = set(inspect.signature(model.forward).parameters)
    input_names = [name for name in ("input_ids", "attention_mask", "token_type_ids")
                   if name in encoded and name in accepted]

    class Wrapper(torch.nn.Module):
        def __init__(self, encoder, names):
            super().__init__()
            self.encoder = encoder
            self.names = names

        def forward(self, *values):
            kwargs = {name: value for name, value in zip(self.names, values)}
            return self.encoder(**kwargs).last_hidden_state

    wrapper = Wrapper(model, input_names)
    args_tuple = tuple(encoded[name] for name in input_names)
    dynamic = {name: {0: "batch", 1: "sequence"} for name in input_names}
    dynamic["last_hidden_state"] = {0: "batch", 1: "sequence"}
    onnx_path = output / "model.onnx"
    with torch.no_grad():
        torch.onnx.export(
            wrapper,
            args_tuple,
            onnx_path,
            input_names=input_names,
            output_names=["last_hidden_state"],
            dynamic_axes=dynamic,
            opset_version=17,
            do_constant_folding=True,
            dynamo=False,
        )

    # Keep the exact tokenizer used at export next to the graph.
    shutil.copy2(model_dir / "tokenizer.json", output / "tokenizer.json")
    metadata = {
        "model_id": "moka-ai/m3e-small",
        "source_dir": str(model_dir),
        "max_length": args.max_length,
        "dimensions": int(model.config.hidden_size),
        "input_names": input_names,
        "pooling": "last_hidden_state attention-mask mean pooling, then L2",
    }
    (output / "export.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
