///|
#external
priv type CFile

///|
#borrow(ptr)
extern "c" fn is_null(ptr : CFile) -> Int32 = "moonbit_is_null"

///|
#borrow(path, mode)
extern "c" fn fopen_ffi(path : Bytes, mode : Bytes) -> CFile = "moonbit_fopen_ffi"

///|
#borrow(ptr, stream)
extern "c" fn fread_ffi(
  ptr : Bytes,
  size : Int32,
  count : Int32,
  stream : CFile,
) -> Int32 = "moonbit_fread_ffi"

///|
#borrow(stream)
extern "c" fn fseek_ffi(
  stream : CFile,
  offset : Int32,
  whence : Int32,
) -> Int32 = "moonbit_fseek_ffi"

///|
#borrow(stream)
extern "c" fn ftell_ffi(stream : CFile) -> Int32 = "moonbit_ftell_ffi"

///|
#borrow(stream)
extern "c" fn fclose_ffi(stream : CFile) -> Int32 = "moonbit_fclose_ffi"

///|
extern "c" fn make_bytes_raw(length : Int32) -> Bytes = "moonbit_make_bytes_raw"

///|
extern "c" fn process_exit(status : Int32) -> Unit = "exit"

///|
fn c_string(value : String) -> Bytes {
  let encoded = @utf8.encode(value)
  let result = FixedArray::make(encoded.length() + 1, b'\x00')
  for index in 0..<encoded.length() {
    result[index] = encoded.at(index)
  }
  result.unsafe_reinterpret_as_bytes()
}

///|
fn read_binary(path : String) -> Result[Bytes, String] {
  let file = fopen_ffi(c_string(path), c_string("rb"))
  if is_null(file) != 0 {
    return Err("cannot open file: " + path)
  }
  if fseek_ffi(file, 0, 2) != 0 {
    ignore(fclose_ffi(file))
    return Err("cannot seek in file: " + path)
  }
  let length = ftell_ffi(file)
  if length < 0 || fseek_ffi(file, 0, 0) != 0 {
    ignore(fclose_ffi(file))
    return Err("cannot determine file size: " + path)
  }
  let buffer = make_bytes_raw(length)
  let count = fread_ffi(buffer, 1, length, file)
  let closed = fclose_ffi(file)
  if count != length {
    return Err("short read while loading file: " + path)
  }
  if closed != 0 {
    return Err("failed to close file after reading: " + path)
  }
  Ok(buffer.exact_view(start=0, end=length).to_owned())
}

///|
fn[T] fail(message : String) -> T {
  println("error: " + message)
  process_exit(1)
  abort(message)
}
