///|
test "inspect an empty module and standard sections" {
  let empty = @wasmbudget.inspect_wasm(b"\x00asm\x01\x00\x00\x00").unwrap()
  assert_eq(empty.total_size, 8)
  assert_eq(empty.sections.length(), 0)

  let wasm_bytes = b"\x00asm\x01\x00\x00\x00\x01\x01\x00\x03\x01\x00\x0A\x04\x01\x02\x00\x0B"
  let report = @wasmbudget.inspect_wasm(wasm_bytes).unwrap()
  assert_eq(report.total_size, 20)
  assert_eq(report.sections.length(), 3)
  assert_eq(report.sections[0].name, "type")
  assert_eq(report.sections[0].item_count, Some(0))
  assert_eq(report.sections[2].name, "code")
  assert_eq(report.sections[2].payload_size, 4)
  assert_eq(report.sections[2].encoded_size, 6)
  assert_eq(report.function_bodies.length(), 1)
  assert_eq(report.function_bodies[0].defined_index, 0)
  assert_eq(report.function_bodies[0].body_size, 2)
  assert_eq(report.function_bodies[0].encoded_size, 3)
}

///|
test "read custom section names and retain duplicate custom sections" {
  let wasm_bytes = b"\x00asm\x01\x00\x00\x00\x00\x05\x04name\x00\x05\x04name"
  let report = @wasmbudget.inspect_wasm(wasm_bytes).unwrap()
  assert_eq(report.sections.length(), 2)
  assert_eq(report.sections[0].name, "custom:name")
  assert_eq(report.sections[0].payload_size, 5)
  assert_eq(report.sections[0].encoded_size, 7)
  assert_eq(report.sections[1].name, "custom:name")
}

///|
test "compare code growth and enforce a total-size budget" {
  let before = @wasmbudget.inspect_wasm(
    b"\x00asm\x01\x00\x00\x00\x01\x01\x00\x03\x01\x00\x0A\x04\x01\x02\x00\x0B",
  ).unwrap()
  let after = @wasmbudget.inspect_wasm(
    b"\x00asm\x01\x00\x00\x00\x01\x01\x00\x03\x01\x00\x0A\x05\x01\x03\x00\x01\x0B",
  ).unwrap()
  let diff = @wasmbudget.compare_wasm(before, after)
  assert_eq(diff.before_total, 20)
  assert_eq(diff.after_total, 21)
  assert_eq(diff.delta_total, 1)
  assert_true(diff.within_budget(1))
  assert_true(!diff.within_budget(0))
  assert_true(!diff.within_budget(-1))
  assert_eq(diff.functions.length(), 1)
  assert_eq(diff.functions[0].defined_index, 0)
  assert_eq(diff.functions[0].before_bytes, 2)
  assert_eq(diff.functions[0].after_bytes, 3)
  assert_eq(diff.functions[0].delta_bytes, 1)
  let mut code_delta = 0
  for section in diff.sections {
    if section.name == "code" {
      code_delta = section.delta_bytes
    }
  }
  assert_eq(code_delta, 1)
}

///|
test "reject bad headers, duplicate sections, and truncated sizes" {
  assert_true(
    @wasmbudget.inspect_wasm(b"short") is Err(@wasmbudget.TruncatedHeader),
  )
  assert_true(
    @wasmbudget.inspect_wasm(b"nope\x01\x00\x00\x00")
    is Err(@wasmbudget.InvalidMagic),
  )
  assert_true(
    @wasmbudget.inspect_wasm(b"\x00asm\x02\x00\x00\x00")
    is Err(@wasmbudget.UnsupportedVersion(_)),
  )
  assert_true(
    @wasmbudget.inspect_wasm(b"\x00asm\x01\x00\x00\x00\x01\x80")
    is Err(@wasmbudget.TruncatedSection),
  )
  let duplicate = b"\x00asm\x01\x00\x00\x00\x01\x01\x00\x01\x01\x00"
  assert_true(
    @wasmbudget.inspect_wasm(duplicate) is Err(@wasmbudget.DuplicateSection(1)),
  )
}

///|
test "reject invalid LEB128 and malformed code body boundaries" {
  let bad_leb = b"\x00asm\x01\x00\x00\x00\x01\xFF\xFF\xFF\xFF\x7F"
  assert_true(
    @wasmbudget.inspect_wasm(bad_leb) is Err(@wasmbudget.InvalidLeb128),
  )
  let truncated_body = b"\x00asm\x01\x00\x00\x00\x0A\x02\x01\x02"
  assert_true(
    @wasmbudget.inspect_wasm(truncated_body)
    is Err(@wasmbudget.InvalidSection(10, _)),
  )
}
