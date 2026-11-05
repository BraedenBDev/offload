import Foundation
import Vision

// offload ocr: on-device text from images with Apple Vision. Free, offline, resumable.
// Paths come from arguments or stdin, one per line. Output is JSON lines, safe to rerun with --out.
struct OCR {
  static func read(_ path: String) throws -> [String] {
    let r = VNRecognizeTextRequest()
    r.recognitionLevel = .accurate; r.automaticallyDetectsLanguage = true; r.usesLanguageCorrection = true
    try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([r])
    var seen = Set<String>(); var lines: [String] = []
    for o in r.results ?? [] { if let s = o.topCandidates(1).first?.string, seen.insert(s).inserted { lines.append(s) } }
    return lines
  }
  static func run(_ a: [String]) throws {
    var out: String?; var jobs = 4; var paths: [String] = []; var i = 0
    while i < a.count {
      switch a[i] {
      case "--out": i += 1; out = a[i]
      case "--jobs": i += 1; jobs = Int(a[i]) ?? 4
      default: paths.append(a[i])
      }
      i += 1
    }
    if paths.isEmpty { while let l = readLine() { if !l.isEmpty { paths.append(l) } } }
    var done = Set<String>()
    if let out, let t = try? String(contentsOfFile: out, encoding: .utf8) {
      for l in t.split(separator: "\n") { if let j = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any], let p = j["path"] as? String { done.insert(p) } }
    }
    let todo = paths.filter { !done.contains($0) }
    if let out, !FileManager.default.fileExists(atPath: out) { FileManager.default.createFile(atPath: out, contents: nil) }
    let h = out.flatMap { FileHandle(forWritingAtPath: $0) }; _ = try? h?.seekToEnd()
    let lock = NSLock(); let start = Date(); nonisolated(unsafe) var n = 0
    let q = OperationQueue(); q.maxConcurrentOperationCount = jobs
    for p in todo { q.addOperation { autoreleasepool {
      var rec: [String: Any] = ["path": p]
      do { rec["lines"] = try read(p) } catch { rec["error"] = String(describing: error) }
      let d = (try? JSONSerialization.data(withJSONObject: rec)) ?? Data()
      lock.lock(); defer { lock.unlock() }
      if let h { h.write(d); h.write(Data("\n".utf8)) } else { FileHandle.standardOutput.write(d); FileHandle.standardOutput.write(Data("\n".utf8)) }
      n += 1
      if n % 200 == 0 { FileHandle.standardError.write(Data("\(n)/\(todo.count) \(Int(Date().timeIntervalSince(start)))s\n".utf8)) }
    } } }
    q.waitUntilAllOperationsAreFinished()
    FileHandle.standardError.write(Data("ocr done: \(n) new, \(done.count) already done, \(Int(Date().timeIntervalSince(start)))s\n".utf8))
  }
}
