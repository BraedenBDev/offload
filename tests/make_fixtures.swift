// Regenerates the synthetic test files. Run from the repo root: swift tests/make_fixtures.swift
import AppKit
import CoreImage
func png(_ i: NSImage, _ p: String) { let r = NSBitmapImageRep(data: i.tiffRepresentation!)!; try! r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: p)) }
let t = NSImage(size: NSSize(width: 640, height: 200)); t.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 640, height: 200).fill()
("OFFLOAD TEST 2027" as NSString).draw(at: NSPoint(x: 30, y: 80), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]); t.unlockFocus(); png(t, "skills/offload/fixtures/text.png")
let f = CIFilter(name: "CIQRCodeGenerator")!; f.setValue("https://example.com/offload".data(using: .utf8), forKey: "inputMessage")
let rep = NSCIImageRep(ciImage: f.outputImage!.transformed(by: .init(scaleX: 10, y: 10))); let q = NSImage(size: rep.size); q.addRepresentation(rep); png(q, "skills/offload/fixtures/qr.png")
