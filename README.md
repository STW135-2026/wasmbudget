# WasmBudget

WasmBudget reports where a WebAssembly binary's bytes are used and compares two builds. It is meant for a familiar CI check: fail a build when the Wasm artifact grows more than the team allows.

It reports standard/custom section sizes and the largest function-body sizes. A comparison shows section deltas and the largest function-body changes. `--max-growth` checks total artifact growth and returns a failing status when the limit is exceeded.

```sh
moon check
moon test
moon build --target wasm --release
moon run cmd/main --target native -- report _build/wasm/release/build/cmd/main/main.wasm
moon run cmd/main --target native -- compare baseline.wasm candidate.wasm --max-growth 4096
moon run examples/scan_sample --target native
```

The last command scans a tiny embedded module and needs no fixture file. The CI workflow also runs this smoke example.

The CLI reads local files on the native target. The scanner library is MoonBit and can be built for Wasm; the command-line filesystem adapter is currently native-only.

## Why another Wasm size tool?

[Twiggy](https://github.com/AlexEne/twiggy) is an established profiler with call-graph analysis. [Starshine](https://github.com/jtenner/starshine-mb) is a much broader MoonBit toolkit for parsing, validating, and rewriting WebAssembly. WasmBudget is deliberately narrower: it turns a before/after artifact-size limit into a small command suitable for a project CI job, with section and body-size clues when the limit is crossed. It does not replace either project, inspect call graphs, or optimize modules.

The implementation is written independently in MoonBit against the [WebAssembly binary format](https://webassembly.github.io/spec/core/binary/modules.html); it does not copy code from those projects.

## Limits

- Supports the version-1 WebAssembly module header and section framing, including custom sections.
- Checks section bounds and parses function-body lengths in the code section. It is not a validator: it does not check instruction typing, index correctness, or execution semantics.
- Function-body comparisons use defined-function order, not stable names or source locations. Renaming, adding, or reordering functions can make individual rows hard to compare; total and section sizes remain the reliable budget signal.
- No source maps, call graph, retained-size analysis, or optimizer is included.

## Development

```sh
moon fmt
moon check --target all
moon test --target all
moon build --target wasm --release
```

See [`docs/PROPOSAL.zh-CN.md`](docs/PROPOSAL.zh-CN.md) for the concise project proposal.

