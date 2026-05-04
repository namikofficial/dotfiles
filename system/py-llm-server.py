#!/usr/bin/env python3
"""
Simple LLM server using transformers - OpenAI-compatible API
No complex dependencies, works on any system
"""

import sys
import os
from pathlib import Path

print("🚀 LLM Server starting...")

# Try to import required packages
try:
    from flask import Flask, request, jsonify
    from transformers import AutoTokenizer, AutoModelForCausalLM
    import torch
except ImportError as e:
    print(f"❌ Missing dependency: {e}")
    print("Installing required packages...")
    os.system("pip install flask transformers torch --quiet")
    print("Please run this script again")
    sys.exit(1)

app = Flask(__name__)

# Global model/tokenizer
MODEL = None
TOKENIZER = None
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

def load_model(model_name="meta-llama/Llama-2-7b-chat-hf"):
    """Load model from HuggingFace or local"""
    global MODEL, TOKENIZER
    
    print(f"Loading model: {model_name}")
    
    # Try to load from local first
    model_path = Path(f"~/llama-models/{model_name}").expanduser()
    if model_path.exists():
        print(f"Found local: {model_path}")
        # For GGUF files, would need llama-cpp-python
        pass
    
    print(f"Downloading from HuggingFace: {model_name}")
    TOKENIZER = AutoTokenizer.from_pretrained(model_name)
    MODEL = AutoModelForCausalLM.from_pretrained(model_name, torch_dtype=torch.float16).to(DEVICE)
    print("✓ Model loaded")

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"})

@app.route('/v1/completions', methods=['POST'])
def completions():
    try:
        data = request.json
        prompt = data.get("prompt", "")
        max_tokens = data.get("max_tokens", 100)
        
        inputs = TOKENIZER(prompt, return_tensors="pt").to(DEVICE)
        outputs = MODEL.generate(**inputs, max_new_tokens=max_tokens)
        text = TOKENIZER.decode(outputs[0])
        
        return jsonify({
            "choices": [{"text": text}],
            "usage": {"prompt_tokens": len(inputs.input_ids[0]), "completion_tokens": max_tokens}
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    print("Loading default model...")
    try:
        load_model()
    except Exception as e:
        print(f"⚠️  Model load failed: {e}")
        print("Server starting anyway (requests will fail)")
    
    print("🌐 Starting server on 127.0.0.1:8000")
    app.run(host="127.0.0.1", port=8000, debug=False)
