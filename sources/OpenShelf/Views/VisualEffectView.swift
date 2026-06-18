import AppKit
import SwiftUI

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()

        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        return view
    }

    func updateNSView(
        _ view: NSVisualEffectView,
        context: Context
    ) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
