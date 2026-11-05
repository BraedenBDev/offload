import Foundation
import Vision

enum OCR {
  // VNRecognizeTextRequest on purpose: on dense images the newer RecognizeTextRequest found about half the words
  // in every configuration we tried on macOS 27.0.1. See capabilities.md before changing this.
  static func read(_ path: String, unique: Bool) throws -> [String] {
    let r = VNRecognizeTextRequest()
    r.recognitionLevel = .accurate; r.automaticallyDetectsLanguage = true; r.usesLanguageCorrection = true
    try VNImageRequestHandler(url: URL(fileURLWithPath: path)).perform([r])
    let lines = (r.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    guard unique else { return lines }
    var seen = Set<String>()
    return lines.filter { seen.insert($0).inserted }
  }

  static func run(_ a: [String]) async {
    let p = parseArgs(a, values: ["--out", "--jobs"], flags: ["--unique"])
    let unique = p.flags.contains("--unique")
    await pathLoop(p.rest, out: p.values["--out"], jobs: positiveInt(p, "--jobs", default: 4)) { path in
      // The request blocks, so it runs on a GCD thread instead of holding one of Swift's cooperative threads.
      let result = await withCheckedContinuation { (done: CheckedContinuation<Result<[String], Error>, Never>) in
        DispatchQueue.global(qos: .userInitiated).async {
          autoreleasepool { done.resume(returning: Result { try read(path, unique: unique) }) }
        }
      }
      switch result {
      case .success(let lines): return ["path": path, "lines": lines]
      case .failure(let e): return ["path": path, "error": errText(e)]
      }
    }
  }
}
