import CoreML
import CreateML
import Foundation
import NaturalLanguage

enum TextTools {
  static func facts(_ s: String, detector: NSDataDetector?) -> [String: Any] {
    var r: [String: Any] = [:]
    let lr = NLLanguageRecognizer(); lr.processString(s); r["language"] = lr.dominantLanguage?.rawValue ?? "unknown"
    let t = NLTagger(tagSchemes: [.nameType, .sentimentScore]); t.string = s
    var names: [String: Set<String>] = [:]
    t.enumerateTags(in: s.startIndex..<s.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
      if let tag, [NLTag.personalName, .placeName, .organizationName].contains(tag) { names[tag.rawValue, default: []].insert(String(s[range])) }
      return true
    }
    r["names"] = names.mapValues { Array($0).sorted() }
    var scores: [Double] = []
    t.enumerateTags(in: s.startIndex..<s.endIndex, unit: .paragraph, scheme: .sentimentScore, options: []) { tag, _ in
      if let v = tag.flatMap({ Double($0.rawValue) }) { scores.append(v) }
      return true
    }
    if !scores.isEmpty { r["sentiment"] = scores.reduce(0, +) / Double(scores.count) }
    var links: [String] = [], dates: [String] = [], phones: [String] = [], places: [String] = []
    for m in detector?.matches(in: s, range: NSRange(s.startIndex..., in: s)) ?? [] {
      let text = Range(m.range, in: s).map { String(s[$0]) }
      switch m.resultType {
      case .link: if let u = m.url { links.append(u.absoluteString) }
      case .date: if let text { dates.append(text) }
      case .phoneNumber: if let x = m.phoneNumber { phones.append(x) }
      case .address: if let text { places.append(text) }
      default: break
      }
    }
    r["links"] = links; r["dates"] = dates; r["phones"] = phones; r["addresses"] = places
    return r
  }

  static func extract(_ a: [String]) async {
    let types = NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.date.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue
    let detector = try? NSDataDetector(types: types)
    await eachRow(Opts(a)) { facts($0, detector: detector) }
  }

  /// Trains from JSONL rows of {"text", "label"} and writes a compiled model.
  static func train(_ a: [String]) async throws {
    let p = parseArgs(a, values: ["--in", "--out"])
    guard let input = p.values["--in"], let out = p.values["--out"] else { fputs("--in and --out are required\n", stderr); exit(2) }
    guard out.hasSuffix(".mlmodelc") else { fputs("--out must end in .mlmodelc\n", stderr); exit(2) }  // this path gets replaced, so never accept a general folder or file
    var data: [String: [String]] = [:]; var skipped = 0
    for try await l in URL(fileURLWithPath: input).lines {
      if let j = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let t = j["text"] as? String, let c = j["label"] as? String { data[c, default: []].append(t) } else { skipped += 1 }
    }
    if skipped > 0 { fputs("skipped \(skipped) rows without text and label\n", stderr) }
    let start = Date(); let m = try MLTextClassifier(trainingData: data)
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mlmodel"); try m.write(to: tmp)
    let compiled = try await MLModel.compileModel(at: tmp); let dest = URL(fileURLWithPath: out)
    if FileManager.default.fileExists(atPath: out) { _ = try FileManager.default.replaceItemAt(dest, withItemAt: compiled) } else { try FileManager.default.moveItem(at: compiled, to: dest) }
    try? FileManager.default.removeItem(at: tmp)
    writeLine(["model": out, "seconds": Date().timeIntervalSince(start), "training_accuracy": 1 - m.trainingMetrics.classificationError, "validation_accuracy": 1 - m.validationMetrics.classificationError, "rows": data.values.map(\.count).reduce(0, +)])
  }

  static func predict(_ a: [String]) async {
    var rest = a; var model = ""
    if let i = rest.firstIndex(of: "--model"), i + 1 < rest.count { model = rest[i + 1]; rest.removeSubrange(i...(i + 1)) }
    guard let m = try? NLModel(contentsOf: URL(fileURLWithPath: model)) else { fputs("--model must point to a trained model\n", stderr); exit(2) }
    await eachRow(Opts(rest)) { t in ["label": m.predictedLabel(for: t) ?? "", "top": m.predictedLabelHypotheses(for: t, maximumCount: 2)] }
  }
}
