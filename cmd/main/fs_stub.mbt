///|
fn read_binary(path : String) -> Result[Bytes, String] {
  ignore(@utf8.encode(path))
  Err("local file access is available only on native targets")
}

///|
fn[T] fail(message : String) -> T {
  exit_failure(message)
}

///|
fn[T] exit_failure(message : String) -> T {
  abort(message)
}
