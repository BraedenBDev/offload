import AVFoundation
import Foundation
import SoundAnalysis
import Speech

enum Hear {
  /// Downloads the speech model for this locale if it's missing. Also used by `setup`.
  static func installSpeech(_ locale: Locale) async throws {
    if let req = try await AssetInventory.assetInstallationRequest(supporting: [SpeechTranscriber(locale: locale, preset: .transcription)]) { try await req.downloadAndInstall() }
  }

  static func transcribe(_ a: [String]) async {
    let p = parseArgs(a, values: ["--locale", "--out"])
    let wanted = Locale(identifier: p.values["--locale"] ?? "en-US")
    guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else { fputs("speech doesn't support \(wanted.identifier). Try a language and region such as en-US or fr-FR.\n", stderr); exit(2) }
    do { try await installSpeech(locale) } catch { fputs("cannot download the speech model for \(locale.identifier(.bcp47)): \(errText(error))\nCheck the internet connection, then run offload setup --yes --locale \(locale.identifier(.bcp47)).\n", stderr); exit(1) }
    await pathLoop(p.rest, out: p.values["--out"]) { path in
      let t = Date(); var r: [String: Any] = ["path": path]
      do {
        let tr = SpeechTranscriber(locale: locale, preset: .transcription)
        let an = SpeechAnalyzer(modules: [tr]); let f = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        try await an.prepareToAnalyze(in: await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [tr]))
        let task = Task { () throws -> String in
          var s = ""
          for try await x in tr.results where x.isFinal { s += String(x.text.characters) }
          return s
        }
        if let last = try await an.analyzeSequence(from: f) { try await an.finalizeAndFinish(through: last) } else { await an.cancelAndFinishNow() }
        r["text"] = try await task.value
      } catch { r["error"] = errText(error) }
      r["seconds"] = Date().timeIntervalSince(t)
      return r
    }
  }

  private final class Top: NSObject, SNResultsObserving {
    var top: [String: Double] = [:]
    func request(_ q: SNRequest, didProduce res: SNResult) {
      guard let c = res as? SNClassificationResult else { return }
      for x in c.classifications.prefix(3) where x.confidence > 0.3 { top[x.identifier] = max(top[x.identifier] ?? 0, x.confidence) }
    }
  }

  static func sound(_ a: [String]) async {
    let p = parseArgs(a, values: ["--out"])
    await pathLoop(p.rest, out: p.values["--out"]) { path in
      var r: [String: Any] = ["path": path]
      do {
        let an = try SNAudioFileAnalyzer(url: URL(fileURLWithPath: path)); let o = Top()
        try an.add(SNClassifySoundRequest(classifierIdentifier: .version1), withObserver: o)
        an.analyze()
        r["sounds"] = o.top.sorted { $0.value > $1.value }.prefix(8).map { ["label": $0.key, "score": $0.value] }
      } catch { r["error"] = errText(error) }
      return r
    }
  }
}
