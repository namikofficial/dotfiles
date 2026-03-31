#!/usr/bin/env python3

import os
import socket
import sys
from pathlib import Path


IPC_SOCKET_PATH = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "noxflow" / "clipboard-ui.sock"


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "ping"
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.connect(str(IPC_SOCKET_PATH))
        sock.sendall((command + "\n").encode("utf-8"))
        sock.recv(32)
    except OSError:
        return 1
    finally:
        sock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
