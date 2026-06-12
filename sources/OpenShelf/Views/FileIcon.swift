import AppKit
import SwiftUI

struct FileIcon: View {
    let url: URL

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: 24, height: 24)
    }
}
