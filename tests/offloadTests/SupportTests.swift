import Foundation
import FoundationModels
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

@Test func `rowID takes strings and numbers, and nothing else`() {
  #expect(rowID("a") == "a")
  #expect(rowID(NSNumber(value: 7)) == "7")
  #expect(rowID(NSNumber(value: true)) == nil)
  #expect(rowID(NSNull()) == nil)
  #expect(rowID(nil) == nil)
}

@Test func `openAppend starts a new line after an interrupted write`() throws {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: file) }
  try Data(#"{"id":"a","te"#.utf8).write(to: file)
  write(Data("{\"id\":\"b\"}\n".utf8), to: openAppend(file.path))
  #expect(try String(contentsOf: file, encoding: .utf8) == "{\"id\":\"a\",\"te\n{\"id\":\"b\"}\n")
}

@Test func `openAppend leaves a finished file alone`() throws {
  let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: file) }
  try Data("{\"id\":\"a\"}\n".utf8).write(to: file)
  write(Data("{\"id\":\"b\"}\n".utf8), to: openAppend(file.path))
  #expect(try String(contentsOf: file, encoding: .utf8) == "{\"id\":\"a\"}\n{\"id\":\"b\"}\n")
}

@Test func `every unavailable text model reason says what to do`() {
  #expect(textModelProblem(.available) == nil)
  #expect(textModelProblem(.unavailable(.appleIntelligenceNotEnabled))?.contains("System Settings") == true)
  #expect(textModelProblem(.unavailable(.modelNotReady))?.contains("downloading") == true)
  #expect(textModelProblem(.unavailable(.deviceNotEligible))?.contains("can't run") == true)
}

private func rows(_ sizes: Int...) -> [ClaudeMap.Row] {
  sizes.enumerated().map { ClaudeMap.Row(id: "id\($0.offset)", text: String(repeating: "x", count: $0.element)) }
}

@Test func `map batches split on row count and on size`() {
  #expect(ClaudeMap.batches(rows(1, 1, 1), size: 2, maxChars: 100).map(\.count) == [2, 1])
  #expect(ClaudeMap.batches(rows(60, 60, 60), size: 8, maxChars: 100).map(\.count) == [1, 1, 1])
  #expect(ClaudeMap.batches(rows(500), size: 8, maxChars: 100).map(\.count) == [1])  // one big row still goes
  #expect(ClaudeMap.batches([], size: 8, maxChars: 100).isEmpty)
}

@Test func `map prompt uses position keys, so ids never need to survive the model`() {
  let batch = [ClaudeMap.Row(id: "/a/Bob's & co.png", text: "hello")]
  let prompt = ClaudeMap.prompt(batch, tag: "item-x")
  #expect(prompt == "<item-x id=\"r0\">\nhello\n</item-x>")
}

@Test func `map accepts each key once, restores the real id, and drops forgeries and repeats`() {
  let batch = [ClaudeMap.Row(id: "Bob's & co", text: ""), ClaudeMap.Row(id: "dup", text: ""), ClaudeMap.Row(id: "gone", text: "")]
  let items: [[String: Any]] = [["id": "r0", "v": "a"], ["id": "r1", "v": "b"], ["id": "r1", "v": "c"], ["id": "r99", "v": "x"], ["v": "no id"]]
  let got = ClaudeMap.accept(items, batch: batch)
  #expect(got.accepted.count == 1)
  #expect(got.accepted.first?["id"] as? String == "Bob's & co")
  #expect(got.accepted.first?["v"] as? String == "a")
  #expect(got.missing == 2)
}

@Test(arguments: ["You've hit your usage limit", "Error 429", "rate-limited", "Overloaded", "quota exceeded"])
func `map stops on usage limit messages`(message: String) {
  #expect(ClaudeMap.isUsageLimit(message))
}

@Test func `map doesn't mistake other failures for a usage limit`() {
  #expect(!ClaudeMap.isUsageLimit("Invalid schema"))
  #expect(!ClaudeMap.isUsageLimit("no output"))
}

@Test func `map schema forces an id onto every item`() throws {
  let schema = ClaudeMap.responseSchema(item: ["properties": ["v": ["type": "string"]], "required": ["v"]])
  let item = try #require((schema["properties"] as? [String: Any])?["items"] as? [String: Any]).self["items"] as? [String: Any]
  #expect((item?["required"] as? [String]) == ["id", "v"])
  #expect(item?["additionalProperties"] as? Bool == false)
  #expect((item?["properties"] as? [String: Any])?["id"] != nil)
}

@Test func `setup takes Return as yes, and anything else but y as no`() {
  #expect(Setup.isYes(""))
  #expect(Setup.isYes("Y"))
  #expect(Setup.isYes(" yes "))
  #expect(!Setup.isYes("n"))
  #expect(!Setup.isYes("nope"))
  #expect(!Setup.isYes(nil))  // end of input means no, so a closed terminal never agrees to anything
}

@Test func `setup reads languages separated by commas or spaces`() {
  #expect(Setup.languages("es, fr  de,") == ["es", "fr", "de"])
  #expect(Setup.languages(" ").isEmpty)
}

@Test func `report shows each fix and counts what's missing`() {
  let r = Setup.report([
    Need(commands: "transcribe", what: "speech model for en-US", ready: true, fix: ""),
    Need(commands: "generate, tag", what: "Apple Intelligence", ready: false, fix: "Turn it on."),
  ])
  #expect(r.contains("ready    transcribe"))
  #expect(r.contains("missing  generate, tag"))
  #expect(r.contains("Turn it on."))
  #expect(r.contains("1 thing missing"))
}

@Test func `report says when everything is ready`() {
  #expect(Setup.report([Need(commands: "embed", what: "search model", ready: true, fix: "")]).contains("Everything offload needs is ready"))
}
