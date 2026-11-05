import Foundation
import NaturalLanguage
import CreateML
import CoreML

enum TextTools {
  static func facts(_ s: String) -> [String: Any] {
    var r: [String: Any] = [:]; let lr = NLLanguageRecognizer(); lr.processString(s); r["language"] = lr.dominantLanguage?.rawValue ?? "unknown"
    let t = NLTagger(tagSchemes: [.nameType, .sentimentScore]); t.string = s; var names: [String: Set<String>] = [:]
    t.enumerateTags(in: s.startIndex..<s.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, rg in
      if let tag, [NLTag.personalName, .placeName, .organizationName].contains(tag) { names[tag.rawValue, default: []].insert(String(s[rg])) }; return true }
    r["names"] = names.mapValues { Array($0).sorted() }
    r["sentiment"] = Double(t.tag(at: s.startIndex, unit: .paragraph, scheme: .sentimentScore).0?.rawValue ?? "")
    var links: [String] = [], dates: [String] = [], phones: [String] = [], places: [String] = []
    if let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.date.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {
      for m in d.matches(in: s, range: NSRange(s.startIndex..., in: s)) { switch m.resultType { case .link: if let u = m.url { links.append(u.absoluteString) }; case .date: if let x = Range(m.range, in: s) { dates.append(String(s[x])) }; case .phoneNumber: if let x = m.phoneNumber { phones.append(x) }; case .address: if let x = Range(m.range, in: s) { places.append(String(s[x])) }; default: break } }
    }
    r["links"] = links; r["dates"] = dates; r["phones"] = phones; r["addresses"] = places; return r
  }
  static func extract(_ a: [String]) async { let o = Opts(a); await eachRow(o) { _, t in facts(t) } }
  // Train a text classifier from labelled rows. JSONL: {"text":..., "label":...}.
  static func train(_ a: [String]) throws {
    var input = "", out = "", i = 0
    while i < a.count { if a[i] == "--in" { i += 1; input = a[i] } else if a[i] == "--out" { i += 1; out = a[i] }; i += 1 }
    var data: [String: [String]] = [:]
    for l in try String(contentsOfFile: input, encoding: .utf8).split(separator: "\n") { if let j = try JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let t = j["text"] as? String, let c = j["label"] as? String { data[c, default: []].append(t) } }
    let t0 = Date(); let m = try MLTextClassifier(trainingData: data); let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mlmodel"); try m.write(to: tmp)
    let compiled = try MLModel.compileModel(at: tmp); let dest = URL(fileURLWithPath: out); try? FileManager.default.removeItem(at: dest); try FileManager.default.moveItem(at: compiled, to: dest); try? FileManager.default.removeItem(at: tmp)
    printJSON(["model": out, "seconds": Date().timeIntervalSince(t0), "training_accuracy": 1 - m.trainingMetrics.classificationError, "validation_accuracy": 1 - m.validationMetrics.classificationError, "rows": data.values.map(\.count).reduce(0, +)])
  }
  static func predict(_ a: [String]) async {
    var model = ""; var rest: [String] = []; var i = 0
    while i < a.count { if a[i] == "--model" { i += 1; model = a[i] } else { rest.append(a[i]) }; i += 1 }
    guard let m = try? NLModel(contentsOf: URL(fileURLWithPath: model)) else { fputs("cannot load model\n", stderr); exit(1) }
    await eachRow(Opts(rest)) { _, t in let h = m.predictedLabelHypotheses(for: t, maximumCount: 2); return ["label": m.predictedLabel(for: t) ?? "", "top": h] }
  }
}
