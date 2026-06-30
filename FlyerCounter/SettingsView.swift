import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var routeMethodsStore: RouteMethodsStore
    @EnvironmentObject private var neighborhoodTypesStore: NeighborhoodTypesStore
    @EnvironmentObject private var autoFlyerSettingsStore: AutoFlyerSettingsStore
    @EnvironmentObject private var settingsLockStore: SettingsLockStore
    @EnvironmentObject private var boundaryAlertSettingsStore: BoundaryAlertSettingsStore
    @State private var newMethodName = ""
    @State private var newNeighborhoodTypeName = ""

    private var trimmedNewMethodName: String {
        newMethodName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewNeighborhoodTypeName: String {
        newNeighborhoodTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                SettingsLockSection(
                    settingsLockStore: settingsLockStore,
                    autoFlyerSettingsStore: autoFlyerSettingsStore
                )
                BoundaryAlertSettingsSection(store: boundaryAlertSettingsStore)
                AutomaticFlyerCountingSection(
                    store: autoFlyerSettingsStore,
                    settingsLockStore: settingsLockStore
                )

                Section {
                    if routeMethodsStore.methods.isEmpty {
                        Text("No route methods yet. Add one below to use when ending a route.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(routeMethodsStore.methods, id: \.self) { method in
                            Text(method)
                        }
                        .onDelete(perform: routeMethodsStore.deleteMethods)
                    }
                } header: {
                    Text("Route Methods")
                } footer: {
                    Text("These appear in the dropdown when you end a route. Use “Other” at route end for one-off methods.")
                }

                Section("Add Route Method") {
                    HStack {
                        TextField("e.g. Zigzag method", text: $newMethodName)
                            .textInputAutocapitalization(.words)

                        Button("Add") {
                            if routeMethodsStore.addMethod(trimmedNewMethodName) {
                                newMethodName = ""
                            }
                        }
                        .disabled(trimmedNewMethodName.isEmpty)
                    }
                }

                Section {
                    if neighborhoodTypesStore.types.isEmpty {
                        Text("No neighborhood types yet. Add one below to use when ending a route.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(neighborhoodTypesStore.types, id: \.self) { type in
                            Text(type)
                        }
                        .onDelete(perform: neighborhoodTypesStore.deleteTypes)
                    }
                } header: {
                    Text("Neighborhood Types")
                } footer: {
                    Text("These appear in the dropdown when you end a route. Use “Other” at route end for one-off types.")
                }

                Section("Add Neighborhood Type") {
                    HStack {
                        TextField("e.g. Suburban", text: $newNeighborhoodTypeName)
                            .textInputAutocapitalization(.words)

                        Button("Add") {
                            if neighborhoodTypesStore.addType(trimmedNewNeighborhoodTypeName) {
                                newNeighborhoodTypeName = ""
                            }
                        }
                        .disabled(trimmedNewNeighborhoodTypeName.isEmpty)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(RouteMethodsStore())
        .environmentObject(NeighborhoodTypesStore())
        .environmentObject(AutoFlyerSettingsStore())
        .environmentObject(SettingsLockStore())
        .environmentObject(BoundaryAlertSettingsStore())
}
