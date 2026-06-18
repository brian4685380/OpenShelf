import AppKit
import SwiftUI

struct FileIcon: View {
    let url: URL

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
                .frame(width: 34, height: 34)

            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 23, height: 23)
        }
    }
}
