import Combine
import Foundation
import SwiftUI

@MainActor
final class AreaBoundariesStore: ObservableObject {
    @Published private(set) var boundaries: [AreaBoundary] = []

    init() {
        boundaries = AreaBoundaryStorage.load()
    }

    func boundary(id: UUID) -> AreaBoundary? {
        boundaries.first { $0.id == id }
    }

    @discardableResult
    func addBoundary(name: String, points: [StoredCoordinate]) -> AreaBoundary? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, points.count >= 3 else { return nil }

        let boundary = AreaBoundary(
            id: UUID(),
            name: trimmedName,
            points: points,
            createdAt: Date()
        )
        boundaries.insert(boundary, at: 0)
        AreaBoundaryStorage.save(boundaries)
        return boundary
    }

    func deleteBoundaries(at offsets: IndexSet) {
        boundaries.remove(atOffsets: offsets)
        AreaBoundaryStorage.save(boundaries)
    }

    func deleteBoundary(id: UUID) {
        boundaries.removeAll { $0.id == id }
        AreaBoundaryStorage.save(boundaries)
    }
}
