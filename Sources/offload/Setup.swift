import AppKit
import Foundation
import FoundationModels
import NaturalLanguage
import Speech
import Translation

/// One thing some commands need from the Mac, and how to get it.
struct Need {
  let commands, what: String
  let ready: Bool
  let fix: String
}

/// What's stopping the on-device text model and how to fix it, or nil when it's ready.
func textModelProblem(_ a: SystemLanguageModel.Availability = SystemLanguageModel(useCase: .general).availability) -> String? {
  switch a {
  case .available: nil
  case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is off. Turn it on in System Settings, under Apple Intelligence & Siri, then wait for its model to download."
  case .unavailable(.modelNotReady): "The on-device model is still downloading. Keep the Mac online and try again later."
  case .unavailable(.deviceNotEligible): "This Mac can't run Apple Intelligence, so generate and tag won't work. Every other command does."
  case .unavailable(let reason): "The on-device model is unavailable: \(reason)"
  }
}

enum Setup {
  static let claudeInstall = "curl -fsSL https://claude.ai/install.sh | bash"
  static let translationFix = "Add languages in System Settings, under General, Language & Region, Translation Languages."
  static let pages = [
    "intelligence": (name: "Apple Intelligence & Siri", url: "x-apple.systempreferences:com.apple.Siri-Settings.extension"),
    "translation": (name: "Language & Region", url: "x-apple.systempreferences:com.apple.Localization-Settings.extension"),
  ]

  static func isYes(_ answer: String?) -> Bool {
    guard let a = answer?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
    return a.isEmpty || a == "y" || a == "yes"
  }

  static func languages(_ s: String) -> [String] { s.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init) }

  static func report(_ needs: [Need]) -> String {
    var lines = ["ready    ocr, look, similar, doc, sound, extract, train-text, predict: built into macOS"]
    for n in needs {
      lines.append("\(n.ready ? "ready  " : "missing")  \(n.commands): \(n.what)")
      if !n.ready { lines.append("         Fix: \(n.fix)") }
    }
    let missing = needs.filter { !$0.ready }.count
    lines += ["", missing == 0 ? "Everything offload needs is ready." : "\(missing) \(missing == 1 ? "thing" : "things") missing. Run offload setup in a terminal for help with each, or follow the fixes above."]
    return lines.joined(separator: "\n")
  }

  private static func name(_ code: String) -> String { Locale.current.localizedString(forIdentifier: code) ?? code }

  private static func speechLocale(_ wanted: Locale) async -> (locale: Locale?, installed: Bool) {
    guard let l = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else { return (nil, false) }
    let id = l.identifier(.bcp47)
    return (l, await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == id })
  }

  private static func translationInstalled(to target: Locale.Language) async -> [String] {
    let av = LanguageAvailability(); var installed: [String] = []
    for l in await av.supportedLanguages where await av.status(from: l, to: target) == .installed { installed.append(l.minimalIdentifier) }
    return installed.sorted()
  }

  private static func claudeState() -> (path: URL?, signedIn: Bool) {
    guard let claude = ClaudeMap.findClaude() else { return (nil, false) }
    let p = Process(), out = Pipe()  // the reply is a few hundred bytes, so a pipe can't fill
    p.executableURL = claude; p.arguments = ["auth", "status"]; p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice  // a terminal here makes claude wait for input
    guard (try? p.run()) != nil else { return (claude, false) }
    let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (claude, ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["loggedIn"] as? Bool ?? false)
  }

  static func needs(locale: Locale, to: String) async -> [Need] {
    let speech = await speechLocale(locale)
    let search = NLContextualEmbedding(language: .english)?.hasAvailableAssets ?? false
    let translate = await translationInstalled(to: Locale.Language(identifier: to))
    let claude = claudeState()
    return [
      Need(commands: "transcribe", what: speech.locale == nil ? "speech for \(locale.identifier), which isn't supported" : "speech model for \(speech.locale!.identifier(.bcp47))", ready: speech.installed,
           fix: speech.locale == nil ? "Pick another language with --locale." : "Run offload setup --yes to download it. It also downloads on first use."),
      Need(commands: "embed, embed-query", what: "search model", ready: search, fix: "Run offload setup --yes to download it."),
      Need(commands: "generate, tag", what: "Apple Intelligence", ready: textModelProblem() == nil, fix: textModelProblem() ?? ""),
      Need(commands: "translate", what: translate.isEmpty ? "no languages installed for \(to)" : "\(translate.count) languages installed for \(to)", ready: !translate.isEmpty, fix: translationFix),
      Need(commands: "map", what: claude.path == nil ? "Claude Code" : "Claude Code, \(claude.signedIn ? "signed in" : "not signed in")", ready: claude.signedIn,
           fix: claude.path == nil ? "Install Claude Code with: \(claudeInstall)" : "Run claude once and sign in."),
    ]
  }

  static func doctor(_ a: [String]) async {
    let p = parseArgs(a, values: ["--to", "--locale"])
    let to = p.values["--to"] ?? "en", locale = Locale(identifier: p.values["--locale"] ?? "en-US")
    let v = ProcessInfo.processInfo.operatingSystemVersion
    print("offload \(version) on macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)\n")
    print(report(await needs(locale: locale, to: to)))
    print("\nDetails")
    print("text model: \(textModelProblem().map { "unavailable. \($0)" } ?? "available")")
    print("speech installed: \((await SpeechTranscriber.installedLocales).map { $0.identifier(.bcp47) }.sorted().joined(separator: " "))")
    let av = LanguageAvailability(); let target = Locale.Language(identifier: to); var downloadable: [String] = []
    for l in await av.supportedLanguages where await av.status(from: l, to: target) == .supported { downloadable.append(l.minimalIdentifier) }
    print("translate to \(to), installed: \(await translationInstalled(to: target).joined(separator: " "))")
    print("translate to \(to), can download: \(downloadable.sorted().joined(separator: " "))")
    print("meaning search assets: \(NLContextualEmbedding(language: .english)?.hasAvailableAssets ?? false)")
  }

  /// Walks through each missing dependency. In a terminal it asks before each step and waits while you change System Settings.
  /// With --yes it downloads what it can without asking. Run by another program, it only reports, so it never waits on input nobody will type.
  static func run(_ a: [String]) async {
    let p = parseArgs(a, values: ["--locale", "--to", "--languages", "--open"], flags: ["--yes"])
    if !p.rest.isEmpty { fputs("unexpected argument \(p.rest[0])\n", stderr); exit(2) }
    if let page = p.values["--open"] {
      guard let target = pages[page] else { fputs("--open takes \(pages.keys.sorted().joined(separator: " or "))\n", stderr); exit(2) }
      open(target); return
    }
    let yes = p.flags.contains("--yes"), interactive = !yes && isatty(0) != 0
    let to = p.values["--to"] ?? "en"
    func confirm(_ q: String) -> Bool {
      if yes { return true }
      guard interactive else { return false }
      print("\(q) [Y/n] ", terminator: ""); fflush(nil)
      return isYes(readLine())
    }
    func askText(_ q: String) -> String? {
      guard interactive else { return nil }
      print(q, terminator: ""); fflush(nil)
      return readLine()?.trimmingCharacters(in: .whitespaces)
    }
    func waitFor(_ what: String) { if interactive { print("\(what), then press Return. ", terminator: ""); fflush(nil); _ = readLine() } }

    if !yes && !interactive { print("offload setup asks questions, so run it in a terminal. To download what it can without asking, run offload setup --yes.\n") }
    if interactive { print("offload setup checks what each command needs and helps you get it. Press Return to accept a [Y/n] question.\n") }

    // Speech
    var locale = Locale(identifier: p.values["--locale"] ?? "en-US")
    if p.values["--locale"] == nil, let typed = askText("Which language is your audio in? Press Return for en-US, or type one such as fr-FR: "), !typed.isEmpty { locale = Locale(identifier: typed) }
    let speech = await speechLocale(locale)
    if let l = speech.locale {
      if speech.installed { print("ready: speech model for \(l.identifier(.bcp47))") } else if confirm("Download the speech model for \(name(l.identifier(.bcp47)))?") {
        print("downloading the speech model for \(l.identifier(.bcp47))")
        do { try await Hear.installSpeech(l); print("ready: speech model for \(l.identifier(.bcp47))") } catch { print("could not download it: \(errText(error)). Check the internet connection and try again.") }
      } else { print("missing: speech model for \(l.identifier(.bcp47)). transcribe downloads it on first use.") }
    } else { print("missing: speech doesn't support \(locale.identifier). Try another, such as en-US or fr-FR.") }

    // Search
    if let m = NLContextualEmbedding(language: .english) {
      if m.hasAvailableAssets { print("ready: search model") } else if confirm("Download the search model for embed?") {
        print("downloading the search model")
        _ = try? await m.requestAssets()
        print(m.hasAvailableAssets ? "ready: search model" : "could not download the search model. Check the internet connection and try again.")
      } else { print("missing: search model. embed downloads it on first use.") }
    }

    // Apple Intelligence
    if let problem = textModelProblem() {
      print("missing for generate and tag: \(problem)")
      if SystemLanguageModel(useCase: .general).availability == .unavailable(.appleIntelligenceNotEnabled) {
        if interactive, confirm("Open System Settings at \(pages["intelligence"]!.name)?") {
          open(pages["intelligence"]!); waitFor("Turn on Apple Intelligence")
          print(textModelProblem().map { "still missing: \($0)" } ?? "ready: Apple Intelligence")
        } else if !interactive { print("To open that page, run offload setup --open intelligence") }
      }
    } else { print("ready: Apple Intelligence") }

    // Translation
    let target = Locale.Language(identifier: to)
    var wanted = Setup.languages(p.values["--languages"] ?? "")
    if p.values["--languages"] == nil, let typed = askText("Which languages will you translate from into \(to)? Separate them with spaces, or press Return to skip: ") { wanted = Setup.languages(typed) }
    let av = LanguageAvailability()
    func missingLanguages() async -> [String] {
      var missing: [String] = []
      for code in wanted {
        switch await av.status(from: Locale.Language(identifier: code), to: target) {
        case .installed: print("ready: translating \(name(code)) into \(name(to))")
        case .supported: missing.append(code)
        default: print("not possible: Apple can't translate \(name(code)) into \(name(to))")
        }
      }
      return missing
    }
    var missing = await missingLanguages()
    let none = await translationInstalled(to: target).isEmpty
    if !missing.isEmpty || (wanted.isEmpty && none) {
      let names = missing.isEmpty ? "the languages you need" : missing.map(name).joined(separator: ", ")
      print("missing for translate: \(names). Apple only lets System Settings download these.")
      if interactive, confirm("Open System Settings at \(pages["translation"]!.name)?") {
        open(pages["translation"]!); waitFor("Under Translation Languages, download \(names)")
        missing = await missingLanguages()
        if !missing.isEmpty { print("still missing: \(missing.map(name).joined(separator: ", ")). Downloads can take a minute; rerun offload setup to check.") }
      } else if !interactive { print("\(translationFix) To open that page, run offload setup --open translation") }
    } else if wanted.isEmpty { print("ready: translate has languages installed. Name yours with --languages to check them.") }

    // Claude Code, for map
    let claude = claudeState()
    if claude.path == nil {
      print("missing for map: Claude Code.")
      if interactive, confirm("Install Claude Code now with Anthropic's installer?") {
        let i = Process(); i.executableURL = URL(fileURLWithPath: "/bin/bash"); i.arguments = ["-c", claudeInstall]
        do { try i.run(); i.waitUntilExit() } catch { print("could not run the installer: \(errText(error))") }
        print(ClaudeMap.findClaude() == nil ? "Claude Code still isn't found. Install it with: \(claudeInstall)" : "ready: Claude Code. Run claude once and sign in.")
      } else { print("Install it with: \(claudeInstall)") }
    } else if !claude.signedIn { print("missing for map: Claude Code isn't signed in. Run claude once and sign in.") } else { print("ready: Claude Code") }

    print("\nNow:")
    print(report(await needs(locale: locale, to: to)))
  }

  private static func open(_ page: (name: String, url: String)) {
    if let u = URL(string: page.url), NSWorkspace.shared.open(u) { print("Opened System Settings at \(page.name).") } else { print("Open System Settings and go to \(page.name).") }
  }
}
