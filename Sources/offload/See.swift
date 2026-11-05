import Foundation
import Vision
import PDFKit
import AppKit

// Image understanding with Apple Vision. All local.
enum See {
  static func analyze(_ url: URL, _ ops: Set<String>) async -> [String: Any] {
    var r: [String: Any] = ["path": url.path]
    do {
      if ops.contains("classify") { r["labels"] = try await ClassifyImageRequest().perform(on: url).filter { $0.confidence > 0.2 }.prefix(10).map { ["label": $0.identifier, "score": Double($0.confidence)] } }
      if ops.contains("barcode") { r["barcodes"] = try await DetectBarcodesRequest().perform(on: url).compactMap { $0.payloadString } }
      if ops.contains("quality") { let o = try await CalculateImageAestheticsScoresRequest().perform(on: url); r["quality"] = Double(o.overallScore); r["utility"] = o.isUtility }
      if ops.contains("faces") { r["faces"] = try await DetectFaceRectanglesRequest().perform(on: url).count }
      if ops.contains("people") { r["people"] = try await DetectHumanRectanglesRequest().perform(on: url).count }
      if ops.contains("animals") { r["animals"] = try await RecognizeAnimalsRequest().perform(on: url).flatMap { $0.labels.map { $0.identifier } } }
    } catch { r["error"] = String(describing: error).prefix(200).description }
    return r
  }
  static func look(_ a: [String]) async {
    var ops: Set<String> = ["classify", "barcode", "quality", "faces", "people", "animals"]; var paths: [String] = []; var out: String?; var i = 0
    while i < a.count { if a[i] == "--ops" { i += 1; ops = Set(a[i].split(separator: ",").map(String.init)) } else if a[i] == "--out" { i += 1; out = a[i] } else { paths.append(a[i]) }; i += 1 }
    await pathLoop(paths, out) { p in await analyze(URL(fileURLWithPath: p), ops) }
  }
  // Near-duplicate images. ponytail: compares every pair, so keep it under about 5,000 images; add clustering if bigger jobs need it.
  static func similar(_ a: [String]) async {
    var limit: Float = 0.25; var paths: [String] = []; var i = 0
    while i < a.count { if a[i] == "--max-distance" { i += 1; limit = Float(a[i]) ?? limit } else { paths.append(a[i]) }; i += 1 }
    if paths.isEmpty { while let l = readLine() { if !l.isEmpty { paths.append(l) } } }
    var prints: [(String, FeaturePrintObservation)] = []
    for p in paths { if let o = try? await GenerateImageFeaturePrintRequest().perform(on: URL(fileURLWithPath: p)) { prints.append((p, o)) } }
    for x in prints.indices { for y in prints.indices where y > x { if let d = try? prints[x].1.distance(to: prints[y].1), Float(d) <= limit { printJSON(["a": prints[x].0, "b": prints[y].0, "distance": d]) } } }
    fputs("compared \(prints.count) images\n", stderr)
  }
  // Documents and PDFs: text, tables and lists with structure kept.
  static func doc(_ a: [String]) async {
    for p in a {
      let url = URL(fileURLWithPath: p); var images: [CGImage] = []
      if p.lowercased().hasSuffix(".pdf"), let d = PDFDocument(url: url) {
        for n in 0..<d.pageCount { if let pg = d.page(at: n) { let b = pg.bounds(for: .mediaBox); let im = pg.thumbnail(of: NSSize(width: b.width * 2, height: b.height * 2), for: .mediaBox); if let c = im.cgImage(forProposedRect: nil, context: nil, hints: nil) { images.append(c) } } }
      } else if let s = CGImageSourceCreateWithURL(url as CFURL, nil), let c = CGImageSourceCreateImageAtIndex(s, 0, nil) { images.append(c) }
      for (n, c) in images.enumerated() {
        var r: [String: Any] = ["path": p, "page": n + 1]
        do {
          if let d = try await RecognizeDocumentsRequest().perform(on: c).first?.document {
            r["text"] = d.text.transcript; r["tables"] = d.tables.map { $0.rows.map { $0.map { $0.content.text.transcript } } }; r["lists"] = d.lists.map { $0.items.map { $0.itemString } }
          }
        } catch { r["error"] = String(describing: error).prefix(200).description }
        printJSON(r)
      }
    }
  }
}
// Runs work over paths from arguments or stdin. With --out it appends JSON lines and skips paths already done, so jobs resume.
func pathLoop(_ given: [String], _ out: String?, _ work: (String) async -> [String: Any]) async {
  var paths = given; if paths.isEmpty { while let l = readLine() { if !l.isEmpty { paths.append(l) } } }
  var done = Set<String>(); var h: FileHandle?
  if let out {
    if let t = try? String(contentsOfFile: out, encoding: .utf8) { for l in t.split(separator: "\n") { if let j = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let p = j["path"] as? String, j["error"] == nil { done.insert(p) } } }
    if !FileManager.default.fileExists(atPath: out) { FileManager.default.createFile(atPath: out, contents: nil) }
    h = FileHandle(forWritingAtPath: out); _ = try? h?.seekToEnd()
  }
  var n = 0; let start = Date()
  for p in paths where !done.contains(p) {
    let r = await work(p); n += 1
    if let h, let d = try? JSONSerialization.data(withJSONObject: r, options: [.withoutEscapingSlashes]) { h.write(d); h.write(Data("\n".utf8)) } else { printJSON(r) }
    if n % 100 == 0 { fputs("\(n) done, \(Int(Date().timeIntervalSince(start)))s\n", stderr) }
  }
  fputs("finished: \(n) new, \(done.count) already done, \(Int(Date().timeIntervalSince(start)))s\n", stderr)
}
func printJSON(_ o: [String: Any]) { if let d = try? JSONSerialization.data(withJSONObject: o, options: [.withoutEscapingSlashes]) { FileHandle.standardOutput.write(d); FileHandle.standardOutput.write(Data("\n".utf8)) } }
