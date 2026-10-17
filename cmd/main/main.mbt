///|
fn usage() -> String {
  "WasmBudget - section and function-body size reports for WebAssembly\n\n" +
  "Usage:\n" +
  "  moon run cmd/main --target native -- report <module.wasm>\n" +
  "  moon run cmd/main --target native -- compare <before.wasm> <after.wasm> [--max-growth <bytes>]"
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
fn main {
  let args = @env.args()
  if args.length() < 2 {
    println(usage())
    return
  }
  match args[1] {
    "report" => {
      if args.length() != 3 {
        println(usage())
        fail("report expects one Wasm file")
      }
      match scan_file(args[2]) {
        Ok(report) => println(report.format())
        Err(message) => fail(message)
      }
    }
    "compare" => {
      if args.length() != 4 && args.length() != 6 {
        println(usage())
        fail("compare expects two Wasm files and an optional budget")
      }
      let budget = if args.length() == 6 {
        if args[4] != "--max-growth" {
          println(usage())
          fail("unknown compare option: " + args[4])
        }
        match parse_budget(args[5]) {
          Ok(value) => Some(value)
          Err(message) => fail(message)
        }
      } else {
        None
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
      println(diff.format())
      match budget {
        Some(max_growth) if !diff.within_budget(max_growth) =>
          fail(
            "Wasm growth " +
            diff.delta_total.to_string() +
            " bytes exceeds the budget of " +
            max_growth.to_string(),
          )
        _ => ()
      }
    }
    _ => {
      println(usage())
      fail("unknown command: " + args[1])
    }
  }
}
