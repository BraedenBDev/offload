import Foundation

// Shared by every command: arguments, resumable JSONL output and batch loops.

struct Args {
  var values: [String: String] = [:]
  var flags: Set<String> = []
  var rest: [String] = []
}

func parseArgs(_ a: [String], values: Set<String>, flags: Set<String> = []) -> Args {
  var r = Args(); var i = 0
  func fail(_ m: String) -> Never { fputs("\(m)\n", stderr); exit(2) }
  while i < a.count {
    let x = a[i]
    if values.contains(x) {
      guard i + 1 < a.count else { fail("\(x) needs a value") }
      r.values[x] = a[i + 1]; i += 2
    } else if flags.contains(x) {
      r.flags.insert(x); i += 1
    } else if x.hasPrefix("--") {
      fail("unknown option \(x)")
    } else {
      r.rest.append(x); i += 1
    }
  }
  return r
}

func pathsOrStdin(_ given: [String]) -> [String] {
  if !given.isEmpty { return given }
  var paths: [String] = []
  while let l = readLine() { if !l.isEmpty { paths.append(l) } }
  return paths
}

func errText(_ e: Error) -> String { String(String(describing: e).prefix(200)) }

/// A positive whole-number option, or the default. Anything else stops with a usage error.
func positiveInt(_ p: Args, _ name: String, default fallback: Int) -> Int {
  guard let raw = p.values[name] else { return fallback }
  guard let n = Int(raw), n > 0 else { fputs("\(name) needs a positive whole number\n", stderr); exit(2) }
  return n
}

func jsonLine(_ o: [String: Any]) -> Data {
  var d = (try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes])) ?? Data()
  d.append(0x0A)
  return d
}

func write(_ d: Data, to h: FileHandle) {
  do { try h.write(contentsOf: d) } catch { fputs("cannot write output: \(errText(error))\n", stderr); exit(1) }
}

func writeLine(_ o: [String: Any], to h: FileHandle = .standardOutput) { write(jsonLine(o), to: h) }

/// Keys of rows that finished. Rows with an error stay out, so a rerun retries them.
func doneKeys(_ path: String, _ key: String) async -> Set<String> {
  var done = Set<String>()
  do {
    for try await l in URL(fileURLWithPath: path).lines {
      if let j = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let k = j[key] as? String, j["error"] == nil { done.insert(k) }
    }
  } catch { return done }  // no output file yet
  return done
}

func openAppend(_ path: String) -> FileHandle {
  if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
  guard let h = FileHandle(forWritingAtPath: path) else { fputs("cannot write \(path)\n", stderr); exit(1) }
  _ = try? h.seekToEnd()
  return h
}

/// Runs work over paths, up to `jobs` at a time. With an output file it appends JSON lines and skips finished paths.
/// Each task serialises its own result, so nothing mutable crosses between tasks. Exits 1 if any path failed.
func pathLoop(_ given: [String], out: String?, jobs: Int = 1, _ work: @escaping @Sendable (String) async -> [String: Any]) async {
  let done = if let out { await doneKeys(out, "path") } else { Set<String>() }
  let todo = pathsOrStdin(given).filter { !done.contains($0) }
  let h = out.map(openAppend) ?? .standardOutput
  @Sendable func task(_ path: String) async -> (line: Data, failed: Bool) {
    let r = await work(path)
    return (jsonLine(r), r["error"] != nil)
  }
  var n = 0, bad = 0; let start = Date()
  await withTaskGroup(of: (line: Data, failed: Bool).self) { group in
    var next = todo.makeIterator()
    for _ in 0..<jobs { if let p = next.next() { group.addTask { await task(p) } } }
    while let r = await group.next() {
      write(r.line, to: h); n += 1
      if r.failed { bad += 1 }
      if n % 200 == 0 { fputs("\(n)/\(todo.count) \(Int(Date().timeIntervalSince(start)))s\n", stderr) }
      if let p = next.next() { group.addTask { await task(p) } }
    }
  }
  fputs("finished: \(n) new, \(bad) errors, \(done.count) already done, \(Int(Date().timeIntervalSince(start)))s\n", stderr)
  if bad > 0 { exit(1) }
}

struct Opts {
  let input, output, idField, textField, instructions, to: String
  let maxChars, limit: Int
  let permissive: Bool

  init(_ a: [String]) {
    let p = parseArgs(a, values: ["--in", "--out", "--id", "--text", "--instructions", "--max-chars", "--to", "--limit"], flags: ["--default-guardrails"])
    func fail(_ m: String) -> Never { fputs("\(m)\n", stderr); exit(2) }
    if !p.rest.isEmpty { fail("unexpected argument \(p.rest[0])") }
    guard let i = p.values["--in"], let o = p.values["--out"] else { fail("--in and --out are required") }
    input = i; output = o
    idField = p.values["--id"] ?? "id"; textField = p.values["--text"] ?? "text"; to = p.values["--to"] ?? "en"
    maxChars = positiveInt(p, "--max-chars", default: 9000); limit = positiveInt(p, "--limit", default: Int.max)
    permissive = !p.flags.contains("--default-guardrails")
    if let v = p.values["--instructions"], v.hasPrefix("@") {
      guard let t = try? String(contentsOfFile: String(v.dropFirst()), encoding: .utf8) else { fail("cannot read instructions from \(v.dropFirst())") }
      instructions = t
    } else { instructions = p.values["--instructions"] ?? "" }
  }
}

/// Runs work over JSONL rows in order, appending to the output and skipping finished ids. Exits 1 if any row failed.
func eachRow(_ o: Opts, _ work: (String) async -> [String: Any]) async {
  let done = await doneKeys(o.output, "id"); let h = openAppend(o.output)
  var n = 0, bad = 0; let start = Date()
  do {
    for try await l in URL(fileURLWithPath: o.input).lines {
      if n >= o.limit { break }
      guard let j = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let id = j[o.idField] as? String, !done.contains(id) else { continue }
      let t = Date()
      var rec: [String: Any] = if let text = j[o.textField] as? String { await work(String(text.prefix(o.maxChars))) } else { ["error": "row has no \(o.textField) field"] }
      rec["id"] = id; rec["ms"] = Int(Date().timeIntervalSince(t) * 1000)
      if rec["error"] != nil { bad += 1 }
      writeLine(rec, to: h); n += 1
      if n % 50 == 0 { fputs("\(n) done, \(bad) errors, \(Int(Date().timeIntervalSince(start)))s\n", stderr) }
    }
  } catch { fputs("cannot read \(o.input): \(errText(error))\n", stderr); exit(1) }
  fputs("finished: \(n) new, \(bad) errors, \(done.count) already done, \(Int(Date().timeIntervalSince(start)))s\n", stderr)
  if bad > 0 { exit(1) }
}
