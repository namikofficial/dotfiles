#!/usr/bin/env python3
"""Run PaddleOCR against an image and print its structured result."""
import argparse
import json
import os

from paddleocr import PaddleOCR


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image")
    parser.add_argument("--lang", default=os.getenv("NOX_OCR_LANG", "en"))
    args = parser.parse_args()

    ocr = PaddleOCR(
        lang=args.lang,
        use_doc_orientation_classify=False,
        use_doc_unwarping=False,
        use_textline_orientation=False,
    )
    result = ocr.predict(args.image)
    serializable = []
    for item in result:
        if hasattr(item, "json"):
            serializable.append(json.loads(item.json))
        else:
            serializable.append(item)
    print(json.dumps(serializable, ensure_ascii=False, default=str))


if __name__ == "__main__":
    main()
