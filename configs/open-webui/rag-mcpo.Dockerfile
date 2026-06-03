FROM ghcr.io/open-webui/mcpo:main

COPY system/rag-requirements.txt /tmp/rag-requirements.txt
RUN /usr/local/bin/python -m pip install --no-cache-dir -r /tmp/rag-requirements.txt

WORKDIR /workspace/dotfiles
