///|
fn usage() -> String {
  "WasmBudget - section and function-body size reports for WebAssembly\n\n" +
  "Usage:\n" +
  "  moon run cmd/main --target native -- report <module.wasm> [--json]\n" +
  "  moon run cmd/main --target native -- compare <before.wasm> <after.wasm> [--max-growth <bytes>] [--json]"
}

///|
fn error_message(error : @wasmbudget.WasmError) -> String {
  match error {
    @wasmbudget.TruncatedHeader => "file is shorter than the Wasm header"
    @wasmbudget.InvalidMagic => "file does not start with the Wasm magic bytes"
    @wasmbudget.UnsupportedVersion(version) =>
      "unsupported Wasm binary version " + version.to_string()
    @wasmbudget.TruncatedSection => "truncated section or size field"
    @wasmbudget.InvalidLeb128 => "invalid u32 LEB128 value"
    @wasmbudget.UnsupportedSection(id) =>
      "unsupported WebAssembly section id " + id.to_string()
    @wasmbudget.DuplicateSection(id) =>
      "duplicate standard section " + id.to_string()
    @wasmbudget.InvalidSection(id, message) =>
      "invalid " + id.to_string() + " section: " + message
  }
}

///|
fn scan_file(path : String) -> Result[@wasmbudget.WasmReport, String] {
  match read_binary(path) {
    Err(message) => Err(message)
    Ok(bytes) =>
      match @wasmbudget.inspect_wasm(bytes) {
        Ok(report) => Ok(report)
        Err(error) => Err(path + ": " + error_message(error))
      }
  }
}

///|
fn parse_budget(value : String) -> Result[Int32, String] {
  let result = @string.parse_int(value) catch {
    _ => return Err("max-growth must be a non-negative integer")
  }
  if result < 0 {
    Err("max-growth must be a non-negative integer")
  } else {
    Ok(result)
  }
}

///|
priv struct CompareOptions {
  max_growth : Int32?
  json : Bool
}

///|
fn parse_compare_options(
  args : Array[String],
) -> Result[CompareOptions, String] {
  let mut max_growth = None
  let mut json = false
  let mut index = 4
  while index < args.length() {
    match args[index] {
      "--json" => {
        if json {
          return Err("--json can only be specified once")
        }
        json = true
        index += 1
      }
      "--max-growth" => {
        if max_growth is Some(_) {
          return Err("--max-growth can only be specified once")
        }
        if index + 1 >= args.length() {
          return Err("--max-growth requires a value in bytes")
        }
        match parse_budget(args[index + 1]) {
          Ok(value) => max_growth = Some(value)
          Err(message) => return Err(message)
        }
        index += 2
      }
      option => return Err("unknown compare option: " + option)
    }
  }
  Ok({ max_growth, json, })
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    println(usage())
    return
  }
  match args[1] {
    "report" => {
      if args.length() != 3 && (args.length() != 4 || args[3] != "--json") {
        println(usage())
        fail("report expects one Wasm file and an optional --json")
      }
      let json = args.length() == 4
      match scan_file(args[2]) {
        Ok(report) =>
          if json {
            println(report_json(report).stringify())
          } else {
            println(report.format())
          }
        Err(message) => fail(message)
      }
    }
    "compare" => {
      if args.length() < 4 {
        println(usage())
        fail("compare expects two Wasm files and optional flags")
      }
      let options = match parse_compare_options(args) {
        Ok(options) => options
        Err(message) => fail(message)
      }
      let before = match scan_file(args[2]) {
        Ok(report) => report
        Err(message) => fail(message)
      }
      let after = match scan_file(args[3]) {
        Ok(report) => report
        Err(message) => fail(message)
      }
      let diff = @wasmbudget.compare_wasm(before, after)
      if options.json {
        println(compare_json(diff, options.max_growth).stringify())
      } else {
        println(diff.format())
      }
      match options.max_growth {
        Some(max_growth) if !diff.within_budget(max_growth) => {
          let message = "Wasm growth " +
            diff.delta_total.to_string() +
            " bytes exceeds the budget of " +
            max_growth.to_string()
          if options.json {
            exit_failure(message)
          } else {
            fail(message)
          }
        }
        _ => ()
      }
    }
    _ => {
      println(usage())
      fail("unknown command: " + args[1])
    }
  }
}
