import Foundation
import FoundationModels
import NaturalLanguage
import Speech
import Translation

let version = "0.1.0"
let usage = """
offload \(version): bulk work on your Mac with Apple's on-device models. No tokens, no cloud.

Read
  ocr         text from images                     offload ocr [--out f] [--jobs 4] [paths]
  look        QR codes, labels, quality, faces     offload look [--ops barcode,classify] [--out f] [paths]
  similar     near-duplicate images                offload similar [--max-distance 0.25] [paths]
  doc         PDF or image to text, tables, lists  offload doc file.pdf
  transcribe  speech to text                       offload transcribe [--locale en-US] [--out f] [paths]
  sound       speech, music and other sounds       offload sound files

Transform (JSONL rows)
  translate   into English, or --to                offload translate --in f --out f
  extract     links, dates, phones, names          offload extract --in f --out f
  embed       meaning vectors                      offload embed --in f --out f
  generate    on-device model, plain text          offload generate --in f --out f --instructions @file
  tag         short topic tags                     offload tag --in f --out f

Learn
  train-text  train a classifier from labels       offload train-text --in f --out model.mlmodelc
  predict     run a trained classifier             offload predict --model m --in f --out f

Setup
  doctor      show which local models are ready    offload doctor
  version     print the version                    offload version

Paths can also come from stdin. Rows use --id (default id) and --text (default text).
Commands given --out skip finished work, so you can rerun them after any interruption.
"""
func doctor() async {
  print("offload \(version)")
  let v = ProcessInfo.processInfo.operatingSystemVersion; print("macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
  print("text model: \(SystemLanguageModel.default.availability)")
  print("speech installed: \((await SpeechTranscriber.installedLocales).map { $0.identifier(.bcp47) }.sorted().joined(separator: " "))")
  let av = LanguageAvailability()
  for l in ["es", "zh-Hans", "fr", "pt", "ja", "de", "it", "ko", "ar", "hi"] { print("translate \(l) to en: \(await av.status(from: Locale.Language(identifier: l), to: Locale.Language(identifier: "en")))") }
  print("meaning search assets: \(NLContextualEmbedding(language: .english)?.hasAvailableAssets ?? false)")
}
@main struct Offload { static func main() async throws {
  let a = Array(CommandLine.arguments.dropFirst()); let r = Array(a.dropFirst())
  switch a.first {
  case "ocr": try OCR.run(r)
  case "look": await See.look(r)
  case "similar": await See.similar(r)
  case "doc": await See.doc(r)
  case "transcribe": await Hear.transcribe(r)
  case "sound": Hear.sound(r)
  case "translate": await Local.translate(r)
  case "extract": await TextTools.extract(r)
  case "embed": await Local.embed(r)
  case "embed-query": Local.embedQuery(r.joined(separator: " "))
  case "generate": await Local.generate(r)
  case "tag": await Local.tag(r)
  case "train-text": try TextTools.train(r)
  case "predict": await TextTools.predict(r)
  case "doctor": await doctor()
  case "version", "--version": print(version)
  case nil, "help", "--help", "-h": print(usage)
  default: fputs("unknown command \(a[0])\n\n\(usage)\n", stderr); exit(2)
  }
} }
