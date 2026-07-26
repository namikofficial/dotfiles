#!/usr/bin/env python3
"""Compare screenshots using a local DINOv2 visual embedding."""
import argparse
import os
import subprocess

import torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModel


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("current")
    parser.add_argument("--device", default=os.getenv("NOX_AI_DEVICE", "auto"))
    args = parser.parse_args()

    model_path = os.getenv(
        "NOX_DINO_MODEL",
        os.path.expanduser("~/ai-models/vision/dinov2-small"),
    )
    device_name = "cuda" if args.device == "auto" and torch.cuda.is_available() else args.device
    device = torch.device(device_name)
    manager = os.path.join(os.path.dirname(__file__), "nox-gpu-manager.sh")
    acquired = device_name.startswith("cuda") and args.device == "auto"
    if acquired:
        subprocess.run([manager, "acquire", "dinov2"], check=True)
    try:
        processor = AutoImageProcessor.from_pretrained(model_path)
        model = AutoModel.from_pretrained(model_path).to(device).eval()

        def embed(path: str) -> torch.Tensor:
            inputs = processor(images=Image.open(path).convert("RGB"), return_tensors="pt")
            inputs = {key: value.to(device) for key, value in inputs.items()}
            with torch.inference_mode():
                vector = model(**inputs).last_hidden_state[:, 0]
            return torch.nn.functional.normalize(vector, dim=-1)

        similarity = torch.sum(embed(args.baseline) * embed(args.current)).item()
        print(f"{similarity:.6f}")
    finally:
        if acquired:
            subprocess.run([manager, "release"], check=False)


if __name__ == "__main__":
    main()
