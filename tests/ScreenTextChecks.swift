import AppKit
import CoreImage

@main
struct ScreenTextChecks {
    @MainActor
    static func main() throws {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        var overrides = arguments
        overrides["enableScreenText"] = false
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        assert(!ScreenTextManager.isEnabled)
        ScreenTextManager.shared.capture() // Disabled capture must return before requesting permission.
        overrides["enableScreenText"] = true
        defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        assert(ScreenTextManager.isEnabled)

        let size = CGSize(width: 1440, height: 900)
        let region = CGRect(x: 100, y: 50, width: 300, height: 120)
        assert(ScreenTextRecognition.pixelRect(region, viewSize: size, imageSize: size) == region)
        assert(ScreenTextRecognition.pixelRect(region, viewSize: size, imageSize: CGSize(width: 2880, height: 1800)) == CGRect(x: 200, y: 100, width: 600, height: 240))
        // Local screen coordinates work identically for displays left/above the main display.
        for origin in [CGPoint(x: -1440, y: 0), CGPoint(x: 0, y: 900)] {
            let global = region.offsetBy(dx: origin.x, dy: origin.y)
            let local = global.offsetBy(dx: -origin.x, dy: -origin.y)
            assert(ScreenTextRecognition.pixelRect(local, viewSize: size, imageSize: size) == region)
        }
        assert(ScreenTextRecognition.pixelRect(CGRect(x: -10, y: -20, width: 30, height: 40), viewSize: size, imageSize: size) == CGRect(x: 0, y: 0, width: 20, height: 20))
        assert(ScreenTextRecognition.pixelRect(region, viewSize: .zero, imageSize: size) == .zero)
        assert(ScreenTextRecognition.mayCopy(generation: 1, currentGeneration: 1, changeCount: 4, currentChangeCount: 4))
        assert(!ScreenTextRecognition.mayCopy(generation: 1, currentGeneration: 2, changeCount: 4, currentChangeCount: 4))
        assert(!ScreenTextRecognition.mayCopy(generation: 1, currentGeneration: 1, changeCount: 4, currentChangeCount: 5))

        let context = CGContext(data: nil, width: 1200, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 240).fill()
        let blank = context.makeImage()!
        ("屏幕文字测试 Hello Eave 2026" as NSString).draw(at: CGPoint(x: 40, y: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let blankText = try ScreenTextRecognition.text(in: blank)
        assert(blankText.isEmpty)
        let recognized = try ScreenTextRecognition.text(in: context.makeImage()!)
        assert(recognized.contains("Hello Eave 2026"), recognized)
        assert(recognized.contains("屏幕文字测试"), recognized)
        assert(ScreenTextRecognition.openableURL("https://example.com/path?q=1") != nil)
        for invalid in ["javascript:alert(1)", "file:///tmp/test", "https://", "hello", "https://example.com\nhttps://other.com", "https://user:password@example.com"] {
            assert(ScreenTextRecognition.openableURL(invalid) == nil)
        }
        assert(tryOutcome(blank) == .text(""))
        assert(tryOutcome(context.makeImage()!) == .text(recognized))
        assert(ScreenTextRecognition.joinedLines(["这是", "测试"], removeLineBreaks: true) == "这是测试")
        assert(ScreenTextRecognition.joinedLines(["Hello ", " world"], removeLineBreaks: true) == "Hello world")
        assert(ScreenTextRecognition.joinedLines(["版本", "version"], removeLineBreaks: true) == "版本 version")
        assert(ScreenTextRecognition.joinedLines(["这是", "测试"], removeLineBreaks: false) == "这是\n测试")
        assert(ScreenTextRecognition.joinedLines(["", "  "], removeLineBreaks: true).isEmpty)
        let payload = "https://example.com/eave?q=1"
        let qr = qrImage(payload)
        let mixed = CGContext(data: nil, width: 1200, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        mixed.setFillColor(CGColor(gray: 1, alpha: 1))
        mixed.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        mixed.interpolationQuality = .none
        mixed.draw(context.makeImage()!, in: CGRect(x: 0, y: 0, width: 1200, height: 240))
        mixed.draw(qr, in: CGRect(x: 40, y: 320, width: 240, height: 240))
        assert(tryOutcome(mixed.makeImage()!) == .qr(payload, URL(string: payload)), "QR must win over visible text")
        let withoutQR = try ScreenTextRecognition.outcome(in: mixed.makeImage()!, detectQRCodes: false, removeLineBreaks: true)
        guard case .text(let plainOCR) = withoutQR else { fatalError("Disabled QR detection must use OCR") }
        assert(plainOCR.contains("Hello Eave 2026"), plainOCR)
        assert(!plainOCR.contains("\n"))
        let plain = "你好 Eave"
        assert(tryOutcome(qrImage(plain)) == .qr(plain, nil))
        mixed.draw(qrImage(plain), in: CGRect(x: 360, y: 320, width: 240, height: 240))
        assert(tryOutcome(mixed.makeImage()!) == .qr(payload + "\n" + plain, nil))
        print("QR priority, plain payload, multiple codes, URL checks and OCR fallback passed.")
        print("Screen text checks passed: coordinates, stale clipboard, blank image, Chinese and English OCR.")
    }

    static func tryOutcome(_ image: CGImage) -> ScreenTextRecognition.Outcome {
        do { return try ScreenTextRecognition.outcome(in: image) }
        catch { fatalError("Recognition failed: \(error)") }
    }

    static func qrImage(_ payload: String) -> CGImage {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let white = CIImage(color: .white).cropped(to: image.extent.insetBy(dx: -32, dy: -32))
        return CIContext().createCGImage(image.composited(over: white), from: white.extent)!
    }
}
