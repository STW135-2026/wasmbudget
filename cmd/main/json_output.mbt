///|
fn report_json(report : @wasmbudget.WasmReport) -> Json {
  let sections = report.sections.map(fn(section) -> Json {
    let item_count : Json = match section.item_count {
      // The scanner reads section counts as u32; their integer values fit
      // exactly in a JSON number represented internally by a Double.
      Some(count) => Json::number(count.to_double())
      None => Json::null()
    }
    {
      "id": @json.to_json(section.id),
      "name": @json.to_json(section.name),
      "offset": @json.to_json(section.offset),
      "payload_bytes": @json.to_json(section.payload_size),
      "encoded_bytes": @json.to_json(section.encoded_size),
      "item_count": item_count,
    }
  })
  let function_bodies = report.function_bodies.map(fn(body) -> Json {
    {
      "defined_index": @json.to_json(body.defined_index),
      "body_bytes": @json.to_json(body.body_size),
      "encoded_bytes": @json.to_json(body.encoded_size),
    }
  })
  {
    "schema_version": 1,
    "command": "report",
    "total_bytes": @json.to_json(report.total_size),
    "sections": Json::array(sections),
    "function_bodies": Json::array(function_bodies),
  }
}

///|
fn compare_json(diff : @wasmbudget.WasmDiff, max_growth : Int32?) -> Json {
  let budget : Json = match max_growth {
    Some(limit) =>
      {
        "max_growth_bytes": @json.to_json(limit),
        "passed": @json.to_json(diff.within_budget(limit)),
      }
    None => Json::null()
  }
  let sections = diff.sections.map(fn(section) -> Json {
    {
      "name": @json.to_json(section.name),
      "before_bytes": @json.to_json(section.before_bytes),
      "after_bytes": @json.to_json(section.after_bytes),
      "delta_bytes": @json.to_json(section.delta_bytes),
    }
  })
  let function_changes = diff.functions.map(fn(body) -> Json {
    {
      "defined_index": @json.to_json(body.defined_index),
      "before_bytes": @json.to_json(body.before_bytes),
      "after_bytes": @json.to_json(body.after_bytes),
      "delta_bytes": @json.to_json(body.delta_bytes),
    }
  })
  {
    "schema_version": 1,
    "command": "compare",
    "before_bytes": @json.to_json(diff.before_total),
    "after_bytes": @json.to_json(diff.after_total),
    "delta_bytes": @json.to_json(diff.delta_total),
    "budget": budget,
    "sections": Json::array(sections),
    "function_changes": Json::array(function_changes),
  }
}
