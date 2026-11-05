import Foundation
import FoundationModels
import NaturalLanguage
import Translation

enum Local {
  private static func kind(_ e: Error) -> String {
    guard let m = e as? LanguageModelError else { return errText(e) }
    switch m {
    case .contextSizeExceeded: return "too_long"
    case .guardrailViolation: return "guardrail"
    case .refusal: return "refusal"
    case .rateLimited: return "rate_limited"
    case .timeout: return "timeout"
    case .unsupportedLanguageOrLocale: return "unsupported_language"
    default: return errText(e)
    }
  }

  static func generate(_ a: [String]) async {
    let o = Opts(a)
    if o.instructions.isEmpty { fputs("--instructions is required\n", stderr); exit(2) }
    let m = SystemLanguageModel(useCase: .general, guardrails: o.permissive ? .permissiveContentTransformations : .default)
    LanguageModelSession(model: m, instructions: o.instructions).prewarm()
    await eachRow(o) { text in
      var t = text
      for _ in 0..<3 {
        do {
          let r = try await LanguageModelSession(model: m, instructions: o.instructions).respond(to: t)
          return ["text": r.content, "chars_used": t.count]
        } catch LanguageModelError.contextSizeExceeded(let e) {
          t = String(t.prefix(t.count * e.contextSize * 8 / 10 / max(e.tokenCount, 1)))  // leaves room for the reply
        } catch { return ["error": kind(error)] }
      }
      return ["error": "too_long"]
    }
  }

  static func tag(_ a: [String]) async {
    let o = Opts(a); let m = SystemLanguageModel(useCase: .contentTagging, guardrails: o.permissive ? .permissiveContentTransformations : .default)
    await eachRow(o) { text in
      do {
        let r = try await LanguageModelSession(model: m, instructions: "Reply with tags in English.").respond(to: text)
        return ["tags": r.content.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }]
      } catch { return ["error": kind(error)] }
    }
  }

  private static func vector(_ m: NLContextualEmbedding, _ s: String) -> String? {
    guard !s.isEmpty, let r = try? m.embeddingResult(for: s, language: .english) else { return nil }
    var v = [Float](repeating: 0, count: m.dimension); var n: Float = 0
    r.enumerateTokenVectors(in: s.startIndex..<s.endIndex) { vec, _ in
      for i in 0..<vec.count { v[i] += Float(vec[i]) }
      n += 1
      return true
    }
    if n == 0 { return nil }
    return v.map { $0 / n }.withUnsafeBytes { Data($0).base64EncodedString() }
  }

  private static func embedder() async -> NLContextualEmbedding {
    guard let m = NLContextualEmbedding(language: .english) else { fputs("embedding model unavailable\n", stderr); exit(1) }
    if !m.hasAvailableAssets { _ = try? await m.requestAssets() }
    guard (try? m.load()) != nil else { fputs("embedding model failed to load\n", stderr); exit(1) }
    return m
  }

  static func embed(_ a: [String]) async {
    let o = Opts(a); let m = await embedder()
    await eachRow(o) { text in vector(m, text).map { ["vector": $0] } ?? ["error": "empty"] }
  }

  static func embedQuery(_ a: [String]) async {
    guard let v = vector(await embedder(), a.joined(separator: " ")) else { exit(1) }
    print(v)
  }

  static func translate(_ a: [String]) async {
    let o = Opts(a); var sessions: [String: TranslationSession] = [:]; let target = Locale.Language(identifier: o.to)
    await eachRow(o) { text in
      let r = NLLanguageRecognizer(); r.processString(text)
      guard let lang = r.dominantLanguage?.rawValue else { return ["text": text, "from": "unknown"] }
      if Locale.Language(identifier: lang).languageCode == target.languageCode { return ["text": text, "from": lang] }
      do {
        let s = sessions[lang] ?? TranslationSession(installedSource: Locale.Language(identifier: lang), target: target)
        sessions[lang] = s
        return ["text": try await s.translate(text).targetText, "from": lang]
      } catch { return ["error": errText(error), "from": lang] }
    }
  }
}
