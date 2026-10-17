///|
fn read_binary(path : String) -> Result[Bytes, String] {
  ignore(@utf8.encode(path))
  Err("local file access is available only on native targets")
}
