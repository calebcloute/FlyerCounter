import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var routeMethodsStore: RouteMethodsStore
    @EnvironmentObject private var neighborhoodTypesStore: NeighborhoodTypesStore
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
            .navigationTitle("Preferences")
        }
    }
}

#Preview {
    PreferencesView()
        .environmentObject(RouteMethodsStore())
        .environmentObject(NeighborhoodTypesStore())
}
