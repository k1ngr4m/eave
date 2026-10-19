import SwiftUI
import AppKit
final class DynamicIslandViewModel: ObservableObject {
 func setScrollGestureSuppression(_ flag: Bool, token: UUID) {}
}
enum NoteItem { static let colors: [Color] = [.yellow, .blue] }
final class ProbeState: ObservableObject {
 @Published var text = "- [x] 中文 😀"
 @Published var title = "笔记测试"
 @Published var image: Data? = nil
 @Published var color = 0
}
struct ProbeView: View {
 @ObservedObject var state: ProbeState
 var body: some View {
  NoteEditorView(title: $state.title, content: $state.text, imageData: $state.image, colorIndex: $state.color,
   onSave: {}, onCancel: {}, isNew: true).environmentObject(DynamicIslandViewModel()).frame(width: 440, height: 360)
 }
}
@main enum Probe {
 static func main() {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let state = ProbeState()
  let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 440, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
  window.title = "Eave Notes — isolated check"
  window.contentView = NSHostingView(rootView: ProbeView(state: state))
  window.makeKeyAndOrderFront(nil)
  app.activate(ignoringOtherApps: true)
  DispatchQueue.main.asyncAfter(deadline: .now()+1) {
   guard let editor = window.firstResponder as? NSTextView else { print("FAIL: editor focus"); exit(1) }
   editor.setSelectedRange(NSRange(location: (state.text as NSString).length, length: 0))
   let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
   app.postEvent(event, atStart: true)
   DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
    guard state.text == "- [x] 中文 😀\n- [ ] " else { print("FAIL: Shift-Return: \(state.text.debugDescription)"); exit(1) }
    editor.undoManager?.undo()
    DispatchQueue.main.asyncAfter(deadline: .now()+0.2) {
     guard editor.string == "- [x] 中文 😀" else { print("FAIL: native text undo"); exit(1) }
     print("Native editor Shift-Return and undo passed")
     app.terminate(nil)
    }
   }
  }
  app.run()
 }
}
