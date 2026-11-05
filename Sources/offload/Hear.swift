import Foundation
import Speech
import SoundAnalysis
import AVFoundation

enum Hear {
  static func transcribe(_ a: [String]) async {
    var locale = "en-US"; var paths: [String] = []; var out: String?; var i = 0
    while i < a.count { if a[i] == "--locale" { i += 1; locale = a[i] } else if a[i] == "--out" { i += 1; out = a[i] } else { paths.append(a[i]) }; i += 1 }
    await pathLoop(paths, out) { p in
      let t = Date(); var r: [String: Any] = ["path": p]
      do {
        let tr = SpeechTranscriber(locale: Locale(identifier: locale), preset: .transcription)
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [tr]) { try await req.downloadAndInstall() }
        let an = SpeechAnalyzer(modules: [tr]); let f = try AVAudioFile(forReading: URL(fileURLWithPath: p))
        let task = Task { () throws -> String in var s = ""; for try await x in tr.results where x.isFinal { s += String(x.text.characters) }; return s }
        if let last = try await an.analyzeSequence(from: f) { try await an.finalizeAndFinish(through: last) } else { await an.cancelAndFinishNow() }
        r["text"] = try await task.value
      } catch { r["error"] = String(describing: error).prefix(200).description }
      r["seconds"] = Date().timeIntervalSince(t); return r
    }
  }
  final class Obs: NSObject, SNResultsObserving {
    var top: [String: Double] = [:]
    func request(_ q: SNRequest, didProduce res: SNResult) { guard let c = res as? SNClassificationResult else { return }; for x in c.classifications.prefix(3) where x.confidence > 0.3 { top[x.identifier] = max(top[x.identifier] ?? 0, x.confidence) } }
  }
  static func sound(_ a: [String]) {
    for p in a {
      var r: [String: Any] = ["path": p]
      do { let an = try SNAudioFileAnalyzer(url: URL(fileURLWithPath: p)); let o = Obs(); try an.add(SNClassifySoundRequest(classifierIdentifier: .version1), withObserver: o); an.analyze()
        r["sounds"] = o.top.sorted { $0.value > $1.value }.prefix(8).map { ["label": $0.key, "score": $0.value] }
      } catch { r["error"] = String(describing: error).prefix(200).description }
      printJSON(r)
    }
  }
}
