import SwiftUI

struct RouteHistoryView: View {
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var routePendingDeletion: RouteRecord?
    @State private var showDeleteConfirmation = false
    @State private var routeBeingEdited: RouteRecord?

    private var groupedRoutes: [RouteDayGroup] {
        RouteDateFormatting.groupedByDay(locationManager.savedRoutes)
    }

    var body: some View {
        NavigationStack {
            Group {
                if locationManager.savedRoutes.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Routes", systemImage: "map")
                    } description: {
                        Text("Completed and in-progress routes will appear here.")
                    }
                } else {
                    List {
                        ForEach(groupedRoutes) { dayGroup in
                            DisclosureGroup(dayGroup.header) {
                                ForEach(dayGroup.routes) { route in
                                    Button {
                                        locationManager.selectRoute(id: route.id)
                                        dismiss()
                                    } label: {
                                        RouteHistoryRow(
                                            route: route,
                                            isActive: route.id == locationManager.activeRouteId
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("Delete", role: .destructive) {
                                            routePendingDeletion = route
                                            showDeleteConfirmation = true
                                        }

                                        Button("Edit") {
                                            routeBeingEdited = currentRoute(matching: route)
                                        }
                                        .tint(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Past Routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $routeBeingEdited) { route in
                EditRouteSheet(
                    route: route,
                    locationManager: locationManager
                )
            }
            .alert("Delete Route?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let route = routePendingDeletion {
                        locationManager.deleteRoute(id: route.id)
                    }
                    routePendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    routePendingDeletion = nil
                }
            } message: {
                if let route = routePendingDeletion {
                    Text("This will permanently delete \"\(route.trimmedName ?? route.displayTitle)\" and its path and flyer markers.")
                }
            }
        }
    }

    private func currentRoute(matching route: RouteRecord) -> RouteRecord {
        locationManager.routes.first { $0.id == route.id } ?? route
    }
}

private struct EditRouteSheet: View {
    let route: RouteRecord
    @ObservedObject var locationManager: LocationManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var routeMethodsStore: RouteMethodsStore
    @EnvironmentObject private var neighborhoodTypesStore: NeighborhoodTypesStore

    @State private var name: String
    @State private var selectedMethod = RouteMethodsStorage.noneOption
    @State private var otherMethodText = ""
    @State private var selectedNeighborhoodType = NeighborhoodTypesStorage.noneOption
    @State private var otherNeighborhoodTypeText = ""
    @State private var selectedHighlighterColor = HighlighterColors.noneOption
    @State private var otherHighlighterColorText = ""

    init(route: RouteRecord, locationManager: LocationManager) {
        self.route = route
        self.locationManager = locationManager
        _name = State(initialValue: route.trimmedName ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedMethod: String? {
        RouteMethodsStorage.resolvedMethod(
            selectedMethod: selectedMethod,
            otherMethodText: otherMethodText
        )
    }

    private var resolvedNeighborhoodType: String? {
        NeighborhoodTypesStorage.resolvedType(
            selectedType: selectedNeighborhoodType,
            otherTypeText: otherNeighborhoodTypeText
        )
    }

    private var resolvedHighlighterColor: String? {
        HighlighterColors.resolvedColor(
            selectedColor: selectedHighlighterColor,
            otherColorText: otherHighlighterColorText
        )
    }

    private var isDuplicateName: Bool {
        !trimmedName.isEmpty &&
        !locationManager.isRouteNameAvailable(trimmedName, excludingRouteId: route.id)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !isDuplicateName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Route Name") {
                    TextField("Route name", text: $name)
                        .textInputAutocapitalization(.words)

                    if isDuplicateName {
                        Text("A route with this name already exists.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                RouteMethodPickerSection(
                    selectedMethod: $selectedMethod,
                    otherMethodText: $otherMethodText
                )

                NeighborhoodTypePickerSection(
                    selectedType: $selectedNeighborhoodType,
                    otherTypeText: $otherNeighborhoodTypeText
                )

                HighlighterColorPickerSection(
                    selectedColor: $selectedHighlighterColor,
                    otherColorText: $otherHighlighterColorText
                )

                Section("Route Data") {
                    if let color = HighlighterColors.systemDisplayColor(for: route.trimmedHighlighterColor) {
                        LabeledContent("Highlighter color") {
                            HighlighterColorSwatch(color: color, size: 16)
                        }
                    } else if let customColor = HighlighterColors.customColorLabel(for: route.trimmedHighlighterColor) {
                        LabeledContent("Highlighter color", value: customColor)
                    }

                    LabeledContent("Time") {
                        Text(RouteDateFormatting.routeTimeRange(
                            startedAt: route.startedAt,
                            endedAt: route.endedAt
                        ))
                        .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Flyers", value: "\(route.flyerCount)")
                    LabeledContent("Distance", value: formattedDistance)
                }
            }
            .navigationTitle("Edit Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = locationManager.updateRoute(
                            id: route.id,
                            name: trimmedName,
                            method: resolvedMethod,
                            neighborhoodType: resolvedNeighborhoodType,
                            highlighterColor: resolvedHighlighterColor
                        )
                        if saved {
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                initializeMethodSelection()
                initializeNeighborhoodTypeSelection()
                initializeHighlighterColorSelection()
            }
        }
        .presentationDetents([.large])
    }

    private func initializeMethodSelection() {
        guard let method = route.trimmedMethod else {
            selectedMethod = RouteMethodsStorage.noneOption
            otherMethodText = ""
            return
        }

        if let match = routeMethodsStore.methods.first(where: {
            $0.compare(method, options: .caseInsensitive) == .orderedSame
        }) {
            selectedMethod = match
            otherMethodText = ""
        } else {
            selectedMethod = RouteMethodsStorage.otherOption
            otherMethodText = method
        }
    }

    private func initializeNeighborhoodTypeSelection() {
        guard let neighborhoodType = route.trimmedNeighborhoodType else {
            selectedNeighborhoodType = NeighborhoodTypesStorage.noneOption
            otherNeighborhoodTypeText = ""
            return
        }

        if let match = neighborhoodTypesStore.types.first(where: {
            $0.compare(neighborhoodType, options: .caseInsensitive) == .orderedSame
        }) {
            selectedNeighborhoodType = match
            otherNeighborhoodTypeText = ""
        } else {
            selectedNeighborhoodType = NeighborhoodTypesStorage.otherOption
            otherNeighborhoodTypeText = neighborhoodType
        }
    }

    private func initializeHighlighterColorSelection() {
        let state = HighlighterColors.initialPickerState(for: route.trimmedHighlighterColor)
        selectedHighlighterColor = state.selected
        otherHighlighterColorText = state.otherText
    }

    private var formattedDistance: String {
        Measurement(value: route.distanceWalked, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

private struct RouteHistoryRow: View {
    let route: RouteRecord
    let isActive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let color = HighlighterColors.systemDisplayColor(for: route.trimmedHighlighterColor) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
                    .frame(width: 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(route.trimmedName ?? route.displayTitle)
                            .font(.headline)

                        if route.trimmedName != nil {
                            if let method = route.trimmedMethod {
                                Text(method)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let neighborhoodType = route.trimmedNeighborhoodType {
                                Text(neighborhoodType)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if let customColor = HighlighterColors.customColorLabel(for: route.trimmedHighlighterColor) {
                                Text(customColor)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Text(RouteDateFormatting.routeTimeOnlyRange(
                                startedAt: route.startedAt,
                                endedAt: route.endedAt
                            ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                    }

                    if isActive {
                        Text("Current")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 16) {
                    Label("\(route.flyerCount) flyers", systemImage: "newspaper")
                    Label(formattedDistance, systemImage: "figure.walk")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDistance: String {
        Measurement(value: route.distanceWalked, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}

#Preview {
    RouteHistoryView(locationManager: LocationManager())
        .environmentObject(RouteMethodsStore())
        .environmentObject(NeighborhoodTypesStore())
}
