import Combine
import Foundation
import SwiftUI

enum NeighborhoodTypesStorage {
    private static let storageKey = "neighborhoodTypes"

    static let noneOption = "None"
    static let otherOption = "Other"

    static func resolvedType(selectedType: String, otherTypeText: String) -> String? {
        if selectedType == noneOption { return nil }
        if selectedType == otherOption {
            let trimmed = otherTypeText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return selectedType
    }

    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let types = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return types
    }

    static func save(_ types: [String]) {
        guard let data = try? JSONEncoder().encode(types) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

@MainActor
final class NeighborhoodTypesStore: ObservableObject {
    @Published private(set) var types: [String] = []

    init() {
        types = NeighborhoodTypesStorage.load()
    }

    @discardableResult
    func addType(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.compare(NeighborhoodTypesStorage.noneOption, options: .caseInsensitive) != .orderedSame,
              trimmed.compare(NeighborhoodTypesStorage.otherOption, options: .caseInsensitive) != .orderedSame,
              !types.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) else {
            return false
        }

        types.append(trimmed)
        NeighborhoodTypesStorage.save(types)
        return true
    }

    func deleteTypes(at offsets: IndexSet) {
        types.remove(atOffsets: offsets)
        NeighborhoodTypesStorage.save(types)
    }
}

struct NeighborhoodTypePickerSection: View {
    @Binding var selectedType: String
    @Binding var otherTypeText: String
    @EnvironmentObject private var neighborhoodTypesStore: NeighborhoodTypesStore

    var body: some View {
        Section {
            Picker("Neighborhood type", selection: $selectedType) {
                Text(NeighborhoodTypesStorage.noneOption).tag(NeighborhoodTypesStorage.noneOption)
                ForEach(neighborhoodTypesStore.types, id: \.self) { type in
                    Text(type).tag(type)
                }
                Text(NeighborhoodTypesStorage.otherOption).tag(NeighborhoodTypesStorage.otherOption)
            }

            if selectedType == NeighborhoodTypesStorage.otherOption {
                TextField("Describe the neighborhood type", text: $otherTypeText)
                    .textInputAutocapitalization(.words)
            }
        } footer: {
            Text("Optional. Add reusable types in Settings, or choose Other.")
                .foregroundStyle(.secondary)
        }
    }
}
