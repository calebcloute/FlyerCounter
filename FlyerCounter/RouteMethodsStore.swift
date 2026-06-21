import Combine
import Foundation
import SwiftUI

enum RouteMethodsStorage {
    private static let storageKey = "routeMethods"

    static let noneOption = "None"
    static let otherOption = "Other"

    static func resolvedMethod(selectedMethod: String, otherMethodText: String) -> String? {
        if selectedMethod == noneOption { return nil }
        if selectedMethod == otherOption {
            let trimmed = otherMethodText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return selectedMethod
    }

    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let methods = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return methods
    }

    static func save(_ methods: [String]) {
        guard let data = try? JSONEncoder().encode(methods) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

@MainActor
final class RouteMethodsStore: ObservableObject {
    @Published private(set) var methods: [String] = []

    init() {
        methods = RouteMethodsStorage.load()
    }

    var pickerOptions: [String] {
        methods + [RouteMethodsStorage.otherOption]
    }

    @discardableResult
    func addMethod(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.compare(RouteMethodsStorage.noneOption, options: .caseInsensitive) != .orderedSame,
              trimmed.compare(RouteMethodsStorage.otherOption, options: .caseInsensitive) != .orderedSame,
              !methods.contains(where: { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }) else {
            return false
        }

        methods.append(trimmed)
        RouteMethodsStorage.save(methods)
        return true
    }

    func deleteMethods(at offsets: IndexSet) {
        methods.remove(atOffsets: offsets)
        RouteMethodsStorage.save(methods)
    }
}

struct RouteMethodPickerSection: View {
    @Binding var selectedMethod: String
    @Binding var otherMethodText: String
    @EnvironmentObject private var routeMethodsStore: RouteMethodsStore

    var body: some View {
        Section {
            Picker("Route method", selection: $selectedMethod) {
                Text(RouteMethodsStorage.noneOption).tag(RouteMethodsStorage.noneOption)
                ForEach(routeMethodsStore.methods, id: \.self) { method in
                    Text(method).tag(method)
                }
                Text(RouteMethodsStorage.otherOption).tag(RouteMethodsStorage.otherOption)
            }

            if selectedMethod == RouteMethodsStorage.otherOption {
                TextField("Describe the method", text: $otherMethodText)
                    .textInputAutocapitalization(.words)
            }
        } footer: {
            Text("Optional. Add reusable methods in Preferences, or choose Other.")
                .foregroundStyle(.secondary)
        }
    }
}
