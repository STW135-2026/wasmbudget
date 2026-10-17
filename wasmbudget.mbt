///|
/// One WebAssembly section. `payload_size` excludes the section ID and size
/// prefix; `encoded_size` includes both.
pub(all) struct WasmSection {
  id : Int
  name : String
  offset : Int
  payload_size : Int
  encoded_size : Int
  item_count : UInt64?
}

///|
/// Size of one function body in the code section. The index counts defined
/// bodies only; imported function indices are not resolved by this scanner.
pub(all) struct WasmFunctionBody {
  defined_index : Int
  body_size : Int
  encoded_size : Int
}

///|
/// Structural summary of a WebAssembly version-1 binary module.
pub(all) struct WasmReport {
  total_size : Int
  sections : Array[WasmSection]
  function_bodies : Array[WasmFunctionBody]
}

///|
/// Per-section size change between a baseline and a candidate module.
pub(all) struct SectionDelta {
  name : String
  before_bytes : Int
  after_bytes : Int
  delta_bytes : Int
}

///|
/// Per-defined-function body size change. Functions are matched by their
/// zero-based order in the code section, not by debug names.
pub(all) struct FunctionDelta {
  defined_index : Int
  before_bytes : Int
  after_bytes : Int
  delta_bytes : Int
}

///|
/// Comparison of two module reports.
pub(all) struct WasmDiff {
  before_total : Int
  after_total : Int
  delta_total : Int
  sections : Array[SectionDelta]
  functions : Array[FunctionDelta]
}

///|
/// Errors detected while scanning a WebAssembly binary's module header and
/// section boundaries. This is a size scanner, not a validating engine.
pub(all) enum WasmError {
  TruncatedHeader
  InvalidMagic
  UnsupportedVersion(UInt64)
  TruncatedSection
  InvalidLeb128
  UnsupportedSection(Int)
  DuplicateSection(Int)
  InvalidSection(Int, String)
}

///|
priv struct WasmU32 {
  value : UInt64
  next : Int
}

///|
fn wasm_read_u32(
  bytes : Bytes,
  offset : Int,
  limit : Int,
) -> Result[WasmU32, WasmError] {
  if offset < 0 || limit > bytes.length() || offset >= limit {
    return Err(TruncatedSection)
  }
  let mut cursor = offset
  let mut value : UInt64 = 0
  for index in 0..<5 {
    if cursor >= limit {
      return Err(TruncatedSection)
    }
    let byte = bytes.at(cursor).to_uint64()
    cursor += 1
    let payload = byte & 0x7F
    if index == 4 && payload > 0x0F {
      return Err(InvalidLeb128)
    }
    value = value | (payload << (index * 7))
    if (byte & 0x80) == 0 {
      return Ok({ value, next: cursor, })
    }
  }
  Err(InvalidLeb128)
}

///|
fn wasm_section_name(id : Int) -> String {
  match id {
    0 => "custom"
    1 => "type"
    2 => "import"
    3 => "function"
    4 => "table"
    5 => "memory"
    6 => "global"
    7 => "export"
    8 => "start"
    9 => "element"
    10 => "code"
    11 => "data"
    12 => "data-count"
    13 => "tag"
    _ => "unknown"
  }
}

///|
fn wasm_vector_count(
  bytes : Bytes,
  section_id : Int,
  payload_start : Int,
  payload_end : Int,
) -> Result[WasmU32, WasmError] {
  if payload_start >= payload_end {
    return Err(InvalidSection(section_id, "missing vector count"))
  }
  wasm_read_u32(bytes, payload_start, payload_end)
}

///|
fn wasm_custom_name(
  bytes : Bytes,
  payload_start : Int,
  payload_end : Int,
) -> Result[(String, Int), WasmError] {
  let length = match wasm_read_u32(bytes, payload_start, payload_end) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if length.value > (payload_end - length.next).to_uint64() {
    return Err(InvalidSection(0, "custom section name exceeds section size"))
  }
  let name_start = length.next
  let name_end = name_start + length.value.to_int()
  let name_bytes = bytes.exact_view(start=name_start, end=name_end).to_owned()
  Ok((@utf8.decode_lossy(name_bytes), name_end))
}

///|
fn wasm_code_bodies(
  bytes : Bytes,
  payload_start : Int,
  payload_end : Int,
) -> Result[(UInt64, Array[WasmFunctionBody]), WasmError] {
  let count = match wasm_vector_count(bytes, 10, payload_start, payload_end) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mut cursor = count.next
  if count.value > (payload_end - cursor).to_uint64() {
    return Err(InvalidSection(10, "function count exceeds code section size"))
  }
  let bodies : Array[WasmFunctionBody] = []
  let mut index : UInt64 = 0
  while index < count.value {
    let body_prefix_start = cursor
    let size = match wasm_read_u32(bytes, cursor, payload_end) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    cursor = size.next
    if size.value > (payload_end - cursor).to_uint64() {
      return Err(InvalidSection(10, "function body exceeds code section size"))
    }
    let body_size = size.value.to_int()
    bodies.push({
      defined_index: index.to_int(),
      body_size,
      encoded_size: size.next - body_prefix_start + body_size,
    })
    cursor += body_size
    index += 1
  }
  if cursor != payload_end {
    return Err(InvalidSection(10, "trailing bytes after function bodies"))
  }
  Ok((count.value, bodies))
}

///|
/// Scan a WebAssembly version-1 module and report section sizes and code-body
/// sizes. Section lengths and vector counts are checked before advancing. This
/// does not validate instructions, types, imports, or execution semantics.
pub fn inspect_wasm(bytes : Bytes) -> Result[WasmReport, WasmError] {
  if bytes.length() < 8 {
    return Err(TruncatedHeader)
  }
  if bytes.at(0).to_uint() != 0 ||
    bytes.at(1).to_uint() != 97 ||
    bytes.at(2).to_uint() != 115 ||
    bytes.at(3).to_uint() != 109 {
    return Err(InvalidMagic)
  }
  let version : UInt64 = bytes.at(4).to_uint64() |
    (bytes.at(5).to_uint64() << 8) |
    (bytes.at(6).to_uint64() << 16) |
    (bytes.at(7).to_uint64() << 24)
  if version != 1 {
    return Err(UnsupportedVersion(version))
  }
  let sections : Array[WasmSection] = []
  let bodies : Array[WasmFunctionBody] = []
  let seen : Array[Bool] = []
  for _ in 0..<14 {
    seen.push(false)
  }
  let mut cursor = 8
  while cursor < bytes.length() {
    let section_offset = cursor
    let id = bytes.at(cursor).to_int()
    cursor += 1
    if id < 0 || id > 13 {
      return Err(UnsupportedSection(id))
    }
    if id > 0 {
      if seen[id] {
        return Err(DuplicateSection(id))
      }
      seen[id] = true
    }
    let size = match wasm_read_u32(bytes, cursor, bytes.length()) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let payload_start = size.next
    if size.value > (bytes.length() - payload_start).to_uint64() {
      return Err(TruncatedSection)
    }
    let payload_size = size.value.to_int()
    let payload_end = payload_start + payload_size
    let section_name = if id == 0 {
      match wasm_custom_name(bytes, payload_start, payload_end) {
        Ok((name, _)) => "custom:" + name
        Err(error) => return Err(error)
      }
    } else {
      wasm_section_name(id)
    }
    let mut item_count : UInt64? = None
    if id == 10 {
      let (count, parsed_bodies) = match
        wasm_code_bodies(bytes, payload_start, payload_end) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      item_count = Some(count)
      for body in parsed_bodies {
        bodies.push(body)
      }
    } else if id == 8 {
      if payload_start >= payload_end {
        return Err(InvalidSection(id, "missing start function index"))
      }
      let start = match wasm_read_u32(bytes, payload_start, payload_end) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      if start.next != payload_end {
        return Err(
          InvalidSection(id, "trailing bytes after start function index"),
        )
      }
    } else if id >= 1 && id <= 13 {
      let count = match
        wasm_vector_count(bytes, id, payload_start, payload_end) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      item_count = Some(count.value)
      if id == 12 && count.next != payload_end {
        return Err(InvalidSection(id, "trailing bytes after data count"))
      }
    }
    cursor = payload_end
    sections.push({
      id,
      name: section_name,
      offset: section_offset,
      payload_size,
      encoded_size: payload_end - section_offset,
      item_count,
    })
  }
  Ok({ total_size: bytes.length(), sections, function_bodies: bodies, })
}

///|
fn wasm_name_index(names : Array[String], name : String) -> Int? {
  for index in 0..<names.length() {
    if names[index] == name {
      return Some(index)
    }
  }
  None
}

///|
/// Compare two scan results by total size, section name, and defined body
/// index. Function growth entries are sorted largest-first.
pub fn compare_wasm(before : WasmReport, after : WasmReport) -> WasmDiff {
  let section_names : Array[String] = []
  let before_sizes : Array[Int] = []
  let after_sizes : Array[Int] = []
  for section in before.sections {
    let index = match wasm_name_index(section_names, section.name) {
      Some(index) => index
      None => {
        section_names.push(section.name)
        before_sizes.push(0)
        after_sizes.push(0)
        section_names.length() - 1
      }
    }
    before_sizes[index] += section.encoded_size
  }
  for section in after.sections {
    let index = match wasm_name_index(section_names, section.name) {
      Some(index) => index
      None => {
        section_names.push(section.name)
        before_sizes.push(0)
        after_sizes.push(0)
        section_names.length() - 1
      }
    }
    after_sizes[index] += section.encoded_size
  }
  let section_deltas : Array[SectionDelta] = []
  for name in section_names {
    let before_size = match wasm_name_index(section_names, name) {
      Some(index) => before_sizes[index]
      None => 0
    }
    let after_size = match wasm_name_index(section_names, name) {
      Some(index) => after_sizes[index]
      None => 0
    }
    section_deltas.push({
      name,
      before_bytes: before_size,
      after_bytes: after_size,
      delta_bytes: after_size - before_size,
    })
  }
  section_deltas.sort_by(fn(a, b) { String::lexical_compare(a.name, b.name) })
  let function_count = if before.function_bodies.length() >
    after.function_bodies.length() {
    before.function_bodies.length()
  } else {
    after.function_bodies.length()
  }
  let function_deltas : Array[FunctionDelta] = []
  for index in 0..<function_count {
    let before_size = if index < before.function_bodies.length() {
      before.function_bodies[index].body_size
    } else {
      0
    }
    let after_size = if index < after.function_bodies.length() {
      after.function_bodies[index].body_size
    } else {
      0
    }
    if before_size != after_size {
      function_deltas.push({
        defined_index: index,
        before_bytes: before_size,
        after_bytes: after_size,
        delta_bytes: after_size - before_size,
      })
    }
  }
  function_deltas.sort_by(fn(a, b) {
    if a.delta_bytes > b.delta_bytes {
      -1
    } else if a.delta_bytes < b.delta_bytes {
      1
    } else {
      a.defined_index - b.defined_index
    }
  })
  {
    before_total: before.total_size,
    after_total: after.total_size,
    delta_total: after.total_size - before.total_size,
    sections: section_deltas,
    functions: function_deltas,
  }
}

///|
/// Return whether the total module growth is at or below `max_growth_bytes`.
pub fn WasmDiff::within_budget(self : WasmDiff, max_growth_bytes : Int) -> Bool {
  max_growth_bytes >= 0 && self.delta_total <= max_growth_bytes
}

///|
/// Format a section summary and up to five largest function bodies.
pub fn WasmReport::format(self : WasmReport) -> String {
  let mut output = "Wasm size: " + self.total_size.to_string() + " bytes\n"
  output += "Section                 bytes     items\n"
  for section in self.sections {
    let count = match section.item_count {
      Some(value) => value.to_string()
      None => "-"
    }
    output += section.name +
      "  " +
      section.encoded_size.to_string() +
      "  " +
      count +
      "\n"
  }
  if !self.function_bodies.is_empty() {
    let indices : Array[Int] = []
    for index in 0..<self.function_bodies.length() {
      indices.push(index)
    }
    indices.sort_by(fn(a, b) {
      self.function_bodies[b].body_size - self.function_bodies[a].body_size
    })
    output += "Largest function bodies (defined index):\n"
    let limit = if indices.length() < 5 { indices.length() } else { 5 }
    for position in 0..<limit {
      let body = self.function_bodies[indices[position]]
      output += "  #" +
        body.defined_index.to_string() +
        ": " +
        body.body_size.to_string() +
        " bytes\n"
    }
  }
  output
}

///|
/// Format a baseline comparison for logs or CI output.
pub fn WasmDiff::format(self : WasmDiff) -> String {
  let mut output = "Wasm total: " +
    self.before_total.to_string() +
    " -> " +
    self.after_total.to_string() +
    " bytes (" +
    (if self.delta_total >= 0 { "+" } else { "" }) +
    self.delta_total.to_string() +
    ")\n"
  output += "Section                 before    after     delta\n"
  for section in self.sections {
    output += section.name +
      "  " +
      section.before_bytes.to_string() +
      "  " +
      section.after_bytes.to_string() +
      "  " +
      (if section.delta_bytes >= 0 { "+" } else { "" }) +
      section.delta_bytes.to_string() +
      "\n"
  }
  if !self.functions.is_empty() {
    let limit = if self.functions.length() < 10 {
      self.functions.length()
    } else {
      10
    }
    output += "Largest function-body changes (defined index):\n"
    for index in 0..<limit {
      let function = self.functions[index]
      output += "  #" +
        function.defined_index.to_string() +
        ": " +
        function.before_bytes.to_string() +
        " -> " +
        function.after_bytes.to_string() +
        " (" +
        (if function.delta_bytes >= 0 { "+" } else { "" }) +
        function.delta_bytes.to_string() +
        ")\n"
    }
    if self.functions.length() > limit {
      output += "  ... " +
        (self.functions.length() - limit).to_string() +
        " more changes\n"
    }
  }
  output
}
