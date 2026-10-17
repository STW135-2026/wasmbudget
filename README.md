# WasmBudget

WasmBudget is a small MoonBit command for checking WebAssembly file-size changes before release. It compares two builds, shows section and larger function-body changes, and can fail a CI job when total growth exceeds a chosen limit. This helps catch size regressions before they reach users and gives developers a starting point for finding what changed.

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

[Wassail](https://github.com/acieroid/wassail) reports section sizes; [wa-info/wa-diff](https://github.com/radekdoulik/wa-info) inspect and compare modules, including function-size comparisons; [Twiggy](https://github.com/AlexEne/twiggy) offers deeper size profiling. [Starshine](https://github.com/jtenner/starshine-mb) is a broader MoonBit WebAssembly toolkit. These projects already cover parts of the problem. WasmBudget keeps to one release check: a total-growth limit for CI, with section and function-body size changes as clues. It does not replace those tools, validate modules fully, or optimize them.

WasmBudget is an independent MoonBit implementation of the [WebAssembly binary format](https://webassembly.github.io/spec/core/binary/modules.html); it does not use those projects' source code.

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

