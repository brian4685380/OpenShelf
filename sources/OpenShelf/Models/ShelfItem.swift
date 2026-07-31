import Foundation

struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let isManagedByShelf: Bool

    init(url: URL, isManagedByShelf: Bool = false) {
        self.url = url
        self.isManagedByShelf = isManagedByShelf
    }
}
