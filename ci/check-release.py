"""Reject a Release binary if the compile-only offline smoke seam leaked into it."""
from pathlib import Path
import sys


def verify(binary):
    forbidden = (b'CISmokeMode', b'--ci-smoke', b'Offline CI smoke', b'ci-smoke-offline')
    return not any(marker in binary for marker in forbidden)


if __name__ == '__main__':
    if not verify(Path(sys.argv[1]).read_bytes()):
        raise SystemExit('CI smoke seam unexpectedly present in Release binary')
    print('Release binary excludes the CI smoke seam')
