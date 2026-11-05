import Foundation
import FoundationModels
import NaturalLanguage
import Speech
import Translation

let version = "0.1.0"

struct Command: Sendable {
  let name, group, summary, usage: String
  let run: @Sendable ([String]) async throws -> Void
}

let commands: [Command] = [
  Command(name: "ocr", group: "Read", summary: "text from images", usage: "[--out f] [--jobs 4] [--unique] [paths]") { await OCR.run($0) },
  Command(name: "look", group: "Read", summary: "QR codes, labels, quality, faces", usage: "[--ops barcode,classify] [--out f] [--jobs 4] [paths]") { await See.look($0) },
  Command(name: "similar", group: "Read", summary: "near-duplicate images", usage: "[--max-distance 0.25] [paths]") { await See.similar($0) },
  Command(name: "doc", group: "Read", summary: "PDF or image to text, tables, lists", usage: "file.pdf") { await See.doc($0) },
  Command(name: "transcribe", group: "Read", summary: "speech to text", usage: "[--locale en-US] [--out f] [paths]") { await Hear.transcribe($0) },
  Command(name: "sound", group: "Read", summary: "speech, music and other sounds", usage: "[--out f] [paths]") { await Hear.sound($0) },
  Command(name: "translate", group: "Transform (JSONL rows)", summary: "into English, or --to", usage: "--in f --out f [--to en]") { await Local.translate($0) },
  Command(name: "extract", group: "Transform (JSONL rows)", summary: "links, dates, phones, names", usage: "--in f --out f") { await TextTools.extract($0) },
  Command(name: "embed", group: "Transform (JSONL rows)", summary: "meaning vectors", usage: "--in f --out f") { await Local.embed($0) },
  Command(name: "embed-query", group: "Transform (JSONL rows)", summary: "one meaning vector for a search", usage: "\"words\"") { await Local.embedQuery($0) },
  Command(name: "generate", group: "Transform (JSONL rows)", summary: "on-device model, plain text", usage: "--in f --out f --instructions @file") { await Local.generate($0) },
  Command(name: "tag", group: "Transform (JSONL rows)", summary: "short topic tags", usage: "--in f --out f") { await Local.tag($0) },
  Command(name: "train-text", group: "Learn", summary: "train a classifier from labels", usage: "--in f --out model.mlmodelc") { try await TextTools.train($0) },
  Command(name: "predict", group: "Learn", summary: "run a trained classifier", usage: "--model m --in f --out f") { await TextTools.predict($0) },
  Command(name: "map", group: "Send to Claude", summary: "run a Claude model over rows", usage: "--in f --out f --system @file --schema f") { await ClaudeMap.main($0) },
  Command(name: "doctor", group: "Setup", summary: "show what's ready and what's missing", usage: "[--to en] [--locale en-US]") { await Setup.doctor($0) },
  Command(name: "setup", group: "Setup", summary: "get what's missing, asking as it goes", usage: "[--yes] [--languages \"es fr\"] [--open intelligence|translation]") { await Setup.run($0) },
  Command(name: "version", group: "Setup", summary: "print the version", usage: "") { _ in print(version) },
]

var usage: String {
  var lines = ["offload \(version): bulk work on your Mac with Apple's on-device models. No tokens, no cloud."]
  var group = ""
  for c in commands {
    if c.group != group { group = c.group; lines += ["", group] }
    let name = c.name.padding(toLength: 12, withPad: " ", startingAt: 0)
    let summary = c.summary.padding(toLength: 48, withPad: " ", startingAt: 0)
    lines.append("  \(name)\(summary)offload \(c.name) \(c.usage)")
  }
  lines += ["", "New here? Run offload setup in a terminal. It checks what each command needs and helps you get it.", "Paths can also come from stdin. Rows use --id (default id) and --text (default text).", "Commands given --out skip finished work, so you can rerun them after any interruption."]
  return lines.joined(separator: "\n")
}

@main struct Offload {
  static func main() async throws {
    let a = Array(CommandLine.arguments.dropFirst())
    switch a.first {
    case nil, "help", "--help", "-h": print(usage)
    case "--version": print(version)
    case let name?:
      guard let c = commands.first(where: { $0.name == name }) else { fputs("unknown command \(name)\n\n\(usage)\n", stderr); exit(2) }
      do { try await c.run(Array(a.dropFirst())) } catch { fputs("\(name): \(errText(error))\n", stderr); exit(1) }
    }
  }
}
