///|
fn main {
  // A minimal module with one defined function and an empty function body.
  let sample = b"\x00asm\x01\x00\x00\x00\x01\x01\x00\x03\x01\x00\x0A\x04\x01\x02\x00\x0B"
  match @wasmbudget.inspect_wasm(sample) {
    Ok(report) => println(report.format())
    Err(_) => abort("sample module could not be scanned")
  }
}
