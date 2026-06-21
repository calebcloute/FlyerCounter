import SwiftUI
import UIKit

enum HighlighterColors {
    static let noneOption = "None"
    static let otherOption = "Other"

    struct Option: Identifiable {
        let name: String
        let uiColor: UIColor

        var id: String { name }
        var color: Color { Color(uiColor: uiColor) }
    }

    static let systemOptions: [Option] = [
        Option(name: "Red", uiColor: .systemRed),
        Option(name: "Orange", uiColor: .systemOrange),
        Option(name: "Yellow", uiColor: .systemYellow),
        Option(name: "Green", uiColor: .systemGreen),
        Option(name: "Mint", uiColor: .systemMint),
        Option(name: "Teal", uiColor: .systemTeal),
        Option(name: "Cyan", uiColor: .systemCyan),
        Option(name: "Blue", uiColor: .systemBlue),
        Option(name: "Indigo", uiColor: .systemIndigo),
        Option(name: "Purple", uiColor: .systemPurple),
        Option(name: "Pink", uiColor: .systemPink),
        Option(name: "Brown", uiColor: .systemBrown),
        Option(name: "Gray", uiColor: .systemGray),
        Option(name: "Black", uiColor: .black),
    ]

    static func resolvedColor(selectedColor: String, otherColorText: String) -> String? {
        if selectedColor == noneOption { return nil }
        if selectedColor == otherOption {
            let trimmed = otherColorText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return selectedColor
    }

    static func initialPickerState(for storedValue: String?) -> (selected: String, otherText: String) {
        guard let storedValue = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !storedValue.isEmpty else {
            return (noneOption, "")
        }

        if let match = systemOptions.first(where: {
            $0.name.compare(storedValue, options: .caseInsensitive) == .orderedSame
        }) {
            return (match.name, "")
        }

        return (otherOption, storedValue)
    }

    static func systemDisplayColor(for storedValue: String?) -> Color? {
        guard let storedValue = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !storedValue.isEmpty,
              let match = systemOptions.first(where: {
                  $0.name.compare(storedValue, options: .caseInsensitive) == .orderedSame
              }) else {
            return nil
        }

        return match.color
    }

    static func customColorLabel(for storedValue: String?) -> String? {
        guard let storedValue = storedValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !storedValue.isEmpty else {
            return nil
        }

        let isSystemColor = systemOptions.contains {
            $0.name.compare(storedValue, options: .caseInsensitive) == .orderedSame
        }
        return isSystemColor ? nil : storedValue
    }
}

struct HighlighterColorSwatch: View {
    let color: Color
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(.primary.opacity(0.2), lineWidth: 1)
            }
    }
}

struct HighlighterColorPickerSection: View {
    @Binding var selectedColor: String
    @Binding var otherColorText: String

    var body: some View {
        Section {
            Picker("Highlighter color used", selection: $selectedColor) {
                Text(HighlighterColors.noneOption).tag(HighlighterColors.noneOption)
                ForEach(HighlighterColors.systemOptions) { option in
                    HStack {
                        HighlighterColorSwatch(color: option.color)
                        Text(option.name)
                    }
                    .tag(option.name)
                }
                Text(HighlighterColors.otherOption).tag(HighlighterColors.otherOption)
            }

            if selectedColor == HighlighterColors.otherOption {
                TextField("Describe the color", text: $otherColorText)
                    .textInputAutocapitalization(.words)
            }
        } footer: {
            Text("Optional. Choose a system color, or use Other for one-off color names.")
                .foregroundStyle(.secondary)
        }
    }
}
