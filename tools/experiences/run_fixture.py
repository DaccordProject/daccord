"""Run client tests against temporary, real curated-directory/community servers.

The fixed keys are public test fixtures. Production credentials are never used.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
from urllib.error import URLError
from urllib.request import Request, urlopen

PUBLIC_KEY = "8a88e3dd7409f195fd52db2d3cba5d72ca6709bf1d94121bf3748801b40f6f5c"


def free_port():
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def healthy(url, process):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Fixture process exited: {process.returncode}")
        try:
            with urlopen(url + "/health", timeout=2) as response:
                if response.status == 200:
                    return
        except (URLError, TimeoutError):
            pass
        time.sleep(0.2)
    raise RuntimeError("Fixture did not become healthy")


def run(args):
    processes = []
    with tempfile.TemporaryDirectory(prefix="accord-experiences-") as temporary:
        directory = Path(temporary)
        try:
            master_url = f"http://127.0.0.1:{free_port()}"
            master_env = dict(os.environ, PORT=master_url.rsplit(":", 1)[1],
                              DATABASE_URL=f"sqlite:{directory}/master.db?mode=rwc",
                              EXPERIENCE_REVIEW_TOKEN="x" * 32,
                              EXPERIENCE_SIGNING_KEY="01" * 32,
                              EXPERIENCE_SIGNING_KEY_ID="ci", RUST_LOG="warn")
            with (directory / "master.log").open("w") as log:
                master = subprocess.Popen([str(Path(args.master_bin).resolve())], env=master_env, stdout=log, stderr=log)
            processes.append(master)
            healthy(master_url, master)
            packages = Path(__file__).resolve().parent / "packages"
            for game in ("chess", "pong"):
                payload = base64.b64encode((packages / f"{game}.json").read_bytes()).decode()
                request = Request(master_url + "/api/v1/experiences", method="POST",
                                  data=json.dumps({"payload": payload}).encode(),
                                  headers={"Content-Type": "application/json", "Authorization": "Bearer " + "x" * 32})
                with urlopen(request, timeout=10) as response:
                    assert response.status == 200
            server_url = f"http://127.0.0.1:{free_port()}"
            server_env = dict(os.environ, PORT=server_url.rsplit(":", 1)[1], ACCORD_BIND="127.0.0.1",
                              DATABASE_URL=f"sqlite:{directory}/community.db?mode=rwc",
                              ACCORD_STORAGE_PATH=str(directory / "cdn"), ACCORD_TEST_MODE="1",
                              EXPERIENCES_ENABLED="true", EXPERIENCE_DIRECTORY_URL=master_url,
                              EXPERIENCE_TRUSTED_KEYS=json.dumps({"ci": PUBLIC_KEY}), RUST_LOG="warn")
            with (directory / "server.log").open("w") as log:
                server = subprocess.Popen([str(Path(args.server_bin).resolve())], env=server_env, stdout=log, stderr=log)
            processes.append(server)
            healthy(server_url, server)
            print("Testing the real curated directory and community server", flush=True)
            command = args.command[1:] if args.command[0] == "--" else args.command
            result = subprocess.run(command, env=dict(os.environ, ACCORD_TEST_SERVER_URL=server_url,
                                                     ACCORD_TEST_EXPERIENCES="1"), check=False)
            if result.returncode:
                for name in ("master.log", "server.log"):
                    print((directory / name).read_text()[-8000:], flush=True)
            return result.returncode
        except Exception:
            for name in ("master.log", "server.log"):
                path = directory / name
                if path.exists():
                    print(path.read_text()[-8000:], flush=True)
            raise
        finally:
            for process in reversed(processes):
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--master-bin", required=True)
    parser.add_argument("--server-bin", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    arguments = parser.parse_args()
    if not arguments.command:
        parser.error("Provide a client test command after --")
    raise SystemExit(run(arguments))
