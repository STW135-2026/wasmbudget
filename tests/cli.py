"""Native CLI smoke tests using two small, valid Wasm modules."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile


def section(section_id: int, payload: bytes) -> bytes:
    # Test fixtures are small enough for a one-byte unsigned LEB128 prefix.
    assert len(payload) < 128
    return bytes([section_id, len(payload)]) + payload


def module(nops: int, custom_name: str) -> bytes:
    name = custom_name.encode()
    body = b"\x00" + b"\x01" * nops + b"\x0b"  # no locals, nops, end
    return (
        b"\x00asm\x01\x00\x00\x00"
        + section(1, b"\x01\x60\x00\x00")  # one type: () -> ()
        + section(3, b"\x01\x00")  # one function using type 0
        + section(10, bytes([1, len(body)]) + body)
        + section(0, bytes([len(name)]) + name)
    )


def main(binary: Path) -> None:
    def run(*args: object, status: int = 0) -> str:
        argv = [str(binary), *(str(arg) for arg in args)]
        result = subprocess.run(argv, text=True, encoding="utf-8", capture_output=True)
        if result.returncode != status:
            raise AssertionError(
                f"{argv}: expected exit {status}, got {result.returncode}\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )
        return result.stdout

    with tempfile.TemporaryDirectory(prefix="wasmbudget-") as dirname:
        baseline = Path(dirname) / "baseline with spaces.wasm"
        candidate = Path(dirname) / "candidate.wasm"
        custom_name = 'release"\\版本'
        baseline.write_bytes(module(0, custom_name))
        candidate.write_bytes(module(2, custom_name))
        before_bytes, after_bytes = (p.stat().st_size for p in (baseline, candidate))

        report = json.loads(run("report", candidate, "--json"))
        assert (report["schema_version"], report["command"]) == (1, "report")
        assert report["total_bytes"] == after_bytes
        assert report["function_bodies"] == [
            {"defined_index": 0, "body_bytes": 4, "encoded_bytes": 5}
        ]
        assert report["sections"][-1]["name"] == "custom:" + custom_name
        assert report["sections"][-1]["item_count"] is None
        assert report["sections"][0]["item_count"] == 1
        assert "Wasm size:" in run("report", candidate)

        def comparison(*flags: object, status: int = 0) -> dict:
            return json.loads(run("compare", baseline, candidate, *flags, status=status))

        diff = comparison("--json", "--max-growth", 1, status=1)
        assert (diff["schema_version"], diff["command"]) == (1, "compare")
        assert (diff["before_bytes"], diff["after_bytes"], diff["delta_bytes"]) == (
            before_bytes,
            after_bytes,
            2,
        )
        assert diff["budget"] == {"max_growth_bytes": 1, "passed": False}
        assert diff["function_changes"] == [
            {"defined_index": 0, "before_bytes": 2, "after_bytes": 4, "delta_bytes": 2}
        ]
        code = next(row for row in diff["sections"] if row["name"] == "code")
        assert code == {"name": "code", "before_bytes": 6, "after_bytes": 8, "delta_bytes": 2}
        assert comparison("--max-growth", 2, "--json")["budget"] == {
            "max_growth_bytes": 2,
            "passed": True,
        }
        assert comparison("--json")["budget"] is None
        shrinking = json.loads(
            run("compare", candidate, baseline, "--json", "--max-growth", 0)
        )
        assert shrinking["delta_bytes"] == -2
        assert shrinking["budget"] == {"max_growth_bytes": 0, "passed": True}

        # Keep the original text output, including the error and exit status.
        assert "Wasm total:" in run("compare", baseline, candidate, "--max-growth", 2)
        rejected = run("compare", baseline, candidate, "--max-growth", 1, status=1)
        assert "Wasm total:" in rejected
        assert "error: Wasm growth 2 bytes exceeds the budget of 1" in rejected
        for flags in (
            ("--json", "--json"),
            ("--max-growth",),
            ("--max-growth", 1, "--max-growth", 2),
            ("--max-growth", -1),
        ):
            run("compare", baseline, candidate, *flags, status=1)

    print("PASS: native CLI JSON, budget boundaries, and legacy text behavior")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
