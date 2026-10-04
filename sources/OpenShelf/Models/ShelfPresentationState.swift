import Foundation

@MainActor
final class ShelfPresentationState: ObservableObject {
    @Published var isPinned = false
}
