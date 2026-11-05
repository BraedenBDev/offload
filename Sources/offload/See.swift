import AppKit
import Foundation
import PDFKit
import Vision

enum See {
  static let allOps: Set<String> = ["classify", "barcode", "quality", "faces", "people", "animals"]

  static func analyze(_ path: String, _ ops: Set<String>) async -> [String: Any] {
    var r: [String: Any] = ["path": path]
    let image = ImageRequestHandler(URL(fileURLWithPath: path))  // one handler, so several requests share one decode
    do {
      if ops.contains("classify") {
        r["labels"] = try await image.perform(ClassifyImageRequest()).filter { $0.confidence > 0.2 }.prefix(10).map { ["label": $0.identifier, "score": Double($0.confidence)] }
      }
      if ops.contains("barcode") { r["barcodes"] = try await image.perform(DetectBarcodesRequest()).compactMap { $0.payloadString } }
      if ops.contains("quality") {
        let o = try await image.perform(CalculateImageAestheticsScoresRequest())
        r["quality"] = Double(o.overallScore); r["utility"] = o.isUtility
      }
      if ops.contains("faces") { r["faces"] = try await image.perform(DetectFaceRectanglesRequest()).count }
      if ops.contains("people") { r["people"] = try await image.perform(DetectHumanRectanglesRequest()).count }
      if ops.contains("animals") { r["animals"] = try await image.perform(RecognizeAnimalsRequest()).flatMap { $0.labels.map { $0.identifier } } }
    } catch { r["error"] = errText(error) }
    return r
  }

  static func look(_ a: [String]) async {
    let p = parseArgs(a, values: ["--ops", "--out", "--jobs"])
    let ops = p.values["--ops"].map { Set($0.split(separator: ",").map(String.init)) } ?? allOps
    if ops.isEmpty { fputs("--ops needs at least one of \(allOps.sorted().joined(separator: ","))\n", stderr); exit(2) }
    if let bad = ops.subtracting(allOps).first { fputs("unknown op \(bad); use \(allOps.sorted().joined(separator: ","))\n", stderr); exit(2) }
    await pathLoop(p.rest, out: p.values["--out"], jobs: positiveInt(p, "--jobs", default: 4)) { await analyze($0, ops) }
  }

  // ponytail: compares every pair, so keep it under about 5,000 images; add clustering if bigger jobs need it.
  static func similar(_ a: [String]) async {
    let p = parseArgs(a, values: ["--max-distance"])
    var limit: Float = 0.25
    if let raw = p.values["--max-distance"] {
      guard let v = Float(raw), v.isFinite, v >= 0 else { fputs("--max-distance needs a number of 0 or more\n", stderr); exit(2) }
      limit = v
    }
    var prints: [(String, FeaturePrintObservation)] = []; var unread = 0
    for path in pathsOrStdin(p.rest) {
      if let o = try? await GenerateImageFeaturePrintRequest().perform(on: URL(fileURLWithPath: path)) { prints.append((path, o)) } else { unread += 1 }
    }
    for x in prints.indices {
      for y in prints.indices where y > x {
        if let d = try? prints[x].1.distance(to: prints[y].1), Float(d) <= limit { writeLine(["a": prints[x].0, "b": prints[y].0, "distance": d]) }
      }
    }
    fputs("compared \(prints.count) images, \(unread) unreadable\n", stderr)
    if unread > 0 { exit(1) }
  }

  private static func render(_ page: PDFPage) -> CGImage? {
    let b = page.bounds(for: .mediaBox)
    return page.thumbnail(of: NSSize(width: b.width * 2, height: b.height * 2), for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil)
  }

  private static func read(_ image: CGImage?, path: String, page: Int) async -> [String: Any] {
    var r: [String: Any] = ["path": path, "page": page]
    guard let image else { r["error"] = "could not read this page"; return r }
    do {
      if let d = try await RecognizeDocumentsRequest().perform(on: image).first?.document {
        r["text"] = d.text.transcript
        r["tables"] = d.tables.map { $0.rows.map { $0.map { $0.content.text.transcript } } }
        r["lists"] = d.lists.map { $0.items.map { $0.itemString } }
      }
    } catch { r["error"] = errText(error) }
    return r
  }

  /// Prints one line per page as it goes, so large PDFs don't pile up in memory.
  static func doc(_ a: [String]) async {
    var bad = 0
    for path in pathsOrStdin(parseArgs(a, values: []).rest) {
      let url = URL(fileURLWithPath: path)
      if path.lowercased().hasSuffix(".pdf") {
        guard let d = PDFDocument(url: url) else { writeLine(["path": path, "error": "could not open this PDF"]); bad += 1; continue }
        for n in 0..<d.pageCount {
          let r = await read(d.page(at: n).flatMap(render), path: path, page: n + 1)
          if r["error"] != nil { bad += 1 }
          writeLine(r)
        }
      } else {
        let image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        let r = await read(image, path: path, page: 1)
        if r["error"] != nil { bad += 1 }
        writeLine(r)
      }
    }
    if bad > 0 { exit(1) }
  }
}
