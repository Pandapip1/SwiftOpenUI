import Foundation

// SwiftUI adds these IndexSet-based edits to collections, which `onDelete`
// and `onMove` hand to applications. The portable backends provide the same
// API, so application code edits its arrays the same way on every backend.
// They touch nothing but the collection, so they are not tied to any actor.
extension RangeReplaceableCollection where Self: MutableCollection, Index == Int {
    nonisolated public mutating func remove(atOffsets offsets: IndexSet) {
        for i in offsets.sorted(by: >) { remove(at: i) }
    }

    nonisolated public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { self[$0] }
        let before = source.filter { $0 < destination }.count
        remove(atOffsets: source)
        insert(contentsOf: moving, at: destination - before)
    }
}
