import Foundation
import Testing
@testable import offload

@Test func `parseArgs separates values, flags and paths`() {
  let p = parseArgs(["--out", "f.jsonl", "--unique", "a.png", "b.png"], values: ["--out"], flags: ["--unique"])
  #expect(p.values["--out"] == "f.jsonl")
  #expect(p.flags == ["--unique"])
  #expect(p.rest == ["a.png", "b.png"])
}

@Test func `parseArgs stops on unknown options`() async {
  await #expect(processExitsWith: .exitCode(2)) { _ = parseArgs(["--nope"], values: []) }
  await #expect(processExitsWith: .exitCode(2)) { _ = parseArgs(["--out"], values: ["--out"]) }
}

@Test(arguments: ["\n", "\r\n"])
func `doneKeys skips failed rows and reads either line ending`(ending: String) async throws {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: file) }
  let rows = [#"{"id":"a","text":"ok"}"#, #"{"id":"b","error":"guardrail"}"#, "not json", #"{"id":"c"}"#]
  try (rows.joined(separator: ending) + ending).write(to: file, atomically: true, encoding: .utf8)
  #expect(await doneKeys(file.path, "id") == ["a", "c"])
}

@Test func `doneKeys treats a missing file as nothing done`() async {
  #expect(await doneKeys("/nonexistent/offload-test.jsonl", "id").isEmpty)
}

@Test func `every command is listed in the help text`() {
  for c in commands { #expect(usage.contains("offload \(c.name)")) }
}
