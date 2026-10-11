"""Persist stage evidence before running; preserve the original command exit status."""
import json
from pathlib import Path
import subprocess
import sys
import time


def run(stage, command, directory=Path("build")):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{stage}-status.json"
    start = time.time()
    record = {"stage": stage, "status": "running", "started": start}
    path.write_text(json.dumps(record))
    try:
        with (directory / f"{stage}.log").open("w") as log:
            process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                log.write(line)
                log.flush()
                print(line, end="", flush=True)
            process.stdout.close()
            code = process.wait()
    except OSError as error:
        record["error"] = type(error).__name__
        code = 127
    record.update(status="success" if code == 0 else "failure", exit_code=code,
                  duration_seconds=round(time.time() - start, 2))
    path.write_text(json.dumps(record))
    return code


if __name__ == "__main__":
    sys.exit(run(sys.argv[1], sys.argv[2:]))
