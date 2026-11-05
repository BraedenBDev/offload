import Foundation
import FoundationModels
import NaturalLanguage
import Translation

// Shared JSONL loop: reads --in, skips ids already in --out, writes one line per row, so every job can resume.
struct Opts {
  var input = "", output = "", idField = "id", textField = "text", instructions = "", maxChars = 9000, permissive = true, to = "en", limit = Int.max
  init(_ a: [String]) {
    var i = 0
    while i < a.count {
      let v = i + 1 < a.count ? a[i + 1] : ""
      switch a[i] {
      case "--in": input = v
      case "--out": output = v
      case "--id": idField = v
      case "--text": textField = v
      case "--instructions": instructions = v.hasPrefix("@") ? ((try? String(contentsOfFile: String(v.dropFirst()), encoding: .utf8)) ?? "") : v
      case "--max-chars": maxChars = Int(v) ?? maxChars
      case "--to": to = v
      case "--limit": limit = Int(v) ?? limit
      case "--default-guardrails": permissive = false; i -= 1
      default: fputs("unknown option \(a[i])\n", stderr); exit(2)
      }
      i += 2
    }
    if input.isEmpty || output.isEmpty { fputs("--in and --out are required\n", stderr); exit(2) }
  }
}
func eachRow(_ o: Opts, _ work: (String, String) async -> [String: Any]) async {
  var done = Set<String>()
  if let t = try? String(contentsOfFile: o.output, encoding: .utf8) { for l in t.split(separator: "\n") { if let j = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let id = j["id"] as? String, j["error"] == nil { done.insert(id) } } }
  if !FileManager.default.fileExists(atPath: o.output) { FileManager.default.createFile(atPath: o.output, contents: nil) }
  guard let h = FileHandle(forWritingAtPath: o.output), let text = try? String(contentsOfFile: o.input, encoding: .utf8) else { fputs("cannot open files\n", stderr); exit(1) }
  _ = try? h.seekToEnd()
  var n = 0, bad = 0; let start = Date()
  for l in text.split(separator: "\n") {
    if n >= o.limit { break }
    guard let j = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let id = j[o.idField] as? String, !done.contains(id) else { continue }
    let t = Date(); var rec = await work(id, String(((j[o.textField] as? String) ?? "").prefix(o.maxChars)))
    rec["id"] = id; rec["ms"] = Int(Date().timeIntervalSince(t) * 1000)
    if rec["error"] != nil { bad += 1 }
    h.write((try? JSONSerialization.data(withJSONObject: rec)) ?? Data()); h.write(Data("\n".utf8)); n += 1
    if n % 50 == 0 { fputs("\(n) done, \(bad) errors, \(Int(Date().timeIntervalSince(start)))s\n", stderr) }
  }
  fputs("finished: \(n) new, \(bad) errors, \(done.count) already done, \(Int(Date().timeIntervalSince(start)))s\n", stderr)
}
enum Local {
  static func kind(_ e: Error) -> String { let s = String(describing: e); if s.contains("xceeds") { return "too_long" }; if s.lowercased().contains("guardrail") || s.lowercased().contains("unsafe") || s.lowercased().contains("sensitive") { return "guardrail" }; if s.lowercased().contains("refus") { return "refusal" }; return String(s.prefix(160)) }
  static func generate(_ a: [String]) async {
    let o = Opts(a); let m = SystemLanguageModel(useCase: .general, guardrails: o.permissive ? .permissiveContentTransformations : .default)
    await eachRow(o) { _, text in
      var t = text
      for _ in 0..<3 {
        do { let r = try await LanguageModelSession(model: m, instructions: o.instructions).respond(to: t); return ["text": r.content, "chars_used": t.count] }
        catch { let k = kind(error); if k == "too_long" { t = String(t.prefix(t.count / 2)); continue }; return ["error": k] }
      }
      return ["error": "too_long"]
    }
  }
  static func vector(_ m: NLContextualEmbedding, _ s: String) -> String? {
    guard !s.isEmpty, let r = try? m.embeddingResult(for: s, language: .english) else { return nil }
    var v = [Float](repeating: 0, count: m.dimension); var n: Float = 0
    r.enumerateTokenVectors(in: s.startIndex..<s.endIndex) { vec, _ in for i in 0..<vec.count { v[i] += Float(vec[i]) }; n += 1; return true }
    if n == 0 { return nil }
    let d = v.map { $0 / n }; return d.withUnsafeBytes { Data($0).base64EncodedString() }
  }
  static func embed(_ a: [String]) async {
    let o = Opts(a); guard let m = NLContextualEmbedding(language: .english), (try? m.load()) != nil else { fputs("embedding model unavailable\n", stderr); exit(1) }
    await eachRow(o) { _, text in if let v = vector(m, text) { return ["vector": v] } else { return ["error": "empty"] } }
  }
  static func embedQuery(_ text: String) {
    guard let m = NLContextualEmbedding(language: .english), (try? m.load()) != nil, let v = vector(m, text) else { exit(1) }
    print(v)
  }
  static func tag(_ a: [String]) async {
    let o = Opts(a); let m = SystemLanguageModel(useCase: .contentTagging, guardrails: .permissiveContentTransformations)
    await eachRow(o) { _, text in
      do { let r = try await LanguageModelSession(model: m, instructions: "Reply with tags in English.").respond(to: text); return ["tags": r.content.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }] } catch { return ["error": kind(error)] }
    }
  }
  static func translate(_ a: [String]) async {
    let o = Opts(a); var sessions: [String: TranslationSession] = [:]; let target = Locale.Language(identifier: o.to)
    await eachRow(o) { _, text in
      let r = NLLanguageRecognizer(); r.processString(text); guard let lang = r.dominantLanguage?.rawValue else { return ["text": text, "from": "unknown"] }
      if lang.hasPrefix(o.to) { return ["text": text, "from": lang] }
      do { let s = sessions[lang] ?? TranslationSession(installedSource: Locale.Language(identifier: lang), target: target); sessions[lang] = s; return ["text": try await s.translate(text).targetText, "from": lang] } catch { return ["error": String(String(describing: error).prefix(160)), "from": lang] }
    }
  }
}
