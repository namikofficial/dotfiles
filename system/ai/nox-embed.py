#!/usr/bin/env python3
"""Encode text with the locally downloaded Qwen3 embedding model."""
import argparse
import json
import os
import subprocess
import sys

import torch
from sentence_transformers import SentenceTransformer


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("texts", nargs="*")
    parser.add_argument("--file", help="Read one text per line")
    parser.add_argument("--device", default=os.getenv("NOX_AI_DEVICE", "auto"))
    args = parser.parse_args()

    texts = list(args.texts)
    if args.file:
        with open(args.file, encoding="utf-8") as handle:
            texts.extend(line.rstrip("\n") for line in handle if line.strip())
    if not texts:
        parser.error("provide text arguments or --file")

    model_path = os.getenv(
        "NOX_EMBED_MODEL",
        os.path.expanduser("~/ai-models/embedding/qwen3-embedding-0.6b"),
    )
    device = "cuda" if args.device == "auto" and torch.cuda.is_available() else args.device
    manager = os.path.join(os.path.dirname(__file__), "nox-gpu-manager.sh")
    acquired = device.startswith("cuda") and args.device == "auto"
    if acquired:
        subprocess.run([manager, "acquire", "embedding"], check=True)
    try:
        model = SentenceTransformer(model_path, device=device)
        vectors = model.encode(
            texts,
            normalize_embeddings=True,
            convert_to_tensor=False,
            show_progress_bar=False,
        )
        print(json.dumps({"model": model_path, "device": device, "dimensions": len(vectors[0]), "embeddings": vectors.tolist()}))
    finally:
        if acquired:
            subprocess.run([manager, "release"], check=False)


if __name__ == "__main__":
    main()
