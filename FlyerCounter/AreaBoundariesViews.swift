import MapKit
import SwiftUI

struct OutsideBoundaryRing: MapContent {
    let coordinates: [CLLocationCoordinate2D]
    var thicknessMeters: Double = BoundaryOutlineStyle.outsideThicknessMeters
    var color: Color = .purple

    var body: some MapContent {
        let outer = PolygonOutwardOffset.offsetCoordinates(
            coordinates,
            distanceMeters: thicknessMeters
        )
        let count = coordinates.count

        if count >= 3, outer.count == count {
            let isCCW = PolygonOutwardOffset.isCounterClockwise(coordinates)
            ForEach(0..<count, id: \.self) { index in
                let next = (index + 1) % count
                MapPolygon(
                    coordinates: ringSegment(
                        innerStart: coordinates[index],
                        innerEnd: coordinates[next],
                        outerEnd: outer[next],
                        outerStart: outer[index],
                        isCCW: isCCW
                    )
                )
                .foregroundStyle(color)
            }
        }
    }

    private func ringSegment(
        innerStart: CLLocationCoordinate2D,
        innerEnd: CLLocationCoordinate2D,
        outerEnd: CLLocationCoordinate2D,
        outerStart: CLLocationCoordinate2D,
        isCCW: Bool
    ) -> [CLLocationCoordinate2D] {
        if isCCW {
            return [innerStart, innerEnd, outerEnd, outerStart]
        }
        return [innerStart, outerStart, outerEnd, innerEnd]
    }
}

struct AreaBoundariesListSheet: View {
    @EnvironmentObject private var areaBoundariesStore: AreaBoundariesStore
    @Environment(\.dismiss) private var dismiss
    @Binding var overlayBoundaryId: UUID?

    let onFocusBoundary: (AreaBoundary) -> Void

    @State private var showEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if areaBoundariesStore.boundaries.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Maps", systemImage: "square.dashed")
                    } description: {
                        Text("Create a map to draw a flyer area boundary.")
                    } actions: {
                        Button("Create New Map") {
                            showEditor = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        if overlayBoundaryId != nil {
                            Section {
                                Button("Clear Boundary Overlay", role: .destructive) {
                                    overlayBoundaryId = nil
                                    dismiss()
                                }
                            }
                        }

                        Section {
                            ForEach(areaBoundariesStore.boundaries) { boundary in
                                Button {
                                    overlayBoundaryId = boundary.id
                                    onFocusBoundary(boundary)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(boundary.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            Text("\(boundary.points.count) points")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if overlayBoundaryId == boundary.id {
                                            Image(systemName: "eye.fill")
                                                .foregroundStyle(.purple)
                                        }
                                    }
                                }
                            }
                            .onDelete(perform: areaBoundariesStore.deleteBoundaries)
                        }
                    }
                }
            }
            .navigationTitle("Area Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New") {
                        showEditor = true
                    }
                }
            }
            .navigationDestination(isPresented: $showEditor) {
                AreaBoundaryEditorView()
            }
        }
    }
}

private struct DraftBoundaryPoint: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
}

struct AreaBoundaryEditorView: View {
    @EnvironmentObject private var areaBoundariesStore: AreaBoundariesStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mapDisplayStyle") private var mapDisplayStyle = MapDisplayStyle.illustrated.rawValue

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var draftPoints: [DraftBoundaryPoint] = []
    @State private var isClosed = false
    @State private var showNamingSheet = false
    @State private var boundaryName = ""

    private var polylineCoordinates: [CLLocationCoordinate2D] {
        let coordinates = draftPoints.map(\.coordinate)
        guard coordinates.count >= 2 else { return coordinates }
        if isClosed, let first = coordinates.first {
            return coordinates + [first]
        }
        return coordinates
    }

    private var canClose: Bool {
        draftPoints.count >= 3 && !isClosed
    }

    private var canSave: Bool {
        isClosed && draftPoints.count >= 3
    }

    private var selectedMapDisplayStyle: MapDisplayStyle {
        MapDisplayStyle(rawValue: mapDisplayStyle) ?? .illustrated
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if isClosed, draftPoints.count >= 3 {
                    OutsideBoundaryRing(coordinates: draftPoints.map(\.coordinate))
                } else if polylineCoordinates.count >= 2 {
                    MapPolyline(coordinates: polylineCoordinates)
                        .stroke(.purple, lineWidth: 3)
                }

                ForEach(Array(draftPoints.enumerated()), id: \.element.id) { index, point in
                    if index == 0 && canClose {
                        Annotation("", coordinate: point.coordinate, anchor: .center) {
                            Button {
                                isClosed = true
                            } label: {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(.white, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                        }
                    } else {
                        Annotation("", coordinate: point.coordinate, anchor: .center) {
                            Circle()
                                .fill(index == 0 ? .blue : .purple)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
            }
            .mapStyle(selectedMapDisplayStyle.mapStyle)
            .onTapGesture { screenPoint in
                guard !isClosed,
                      let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                draftPoints.append(DraftBoundaryPoint(coordinate: coordinate))
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if isClosed {
                    Text("Shape closed. Tap Save to name this map.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if canClose {
                    Text("Tap the green starting dot to close the shape.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap the map to place boundary points.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Undo") {
                        undoLastPoint()
                    }
                    .buttonStyle(.bordered)
                    .disabled(draftPoints.isEmpty || isClosed)

                    Button("Clear") {
                        clearDraft()
                    }
                    .buttonStyle(.bordered)
                    .disabled(draftPoints.isEmpty)

                    Button("Save") {
                        boundaryName = ""
                        showNamingSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Draw Boundary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNamingSheet) {
            AreaBoundaryNamingSheet(boundaryName: $boundaryName) {
                saveBoundary()
            }
        }
    }

    private func undoLastPoint() {
        guard !draftPoints.isEmpty, !isClosed else { return }
        draftPoints.removeLast()
    }

    private func clearDraft() {
        draftPoints.removeAll()
        isClosed = false
    }

    private func saveBoundary() {
        let storedPoints = draftPoints.map { StoredCoordinate(coordinate: $0.coordinate) }
        if areaBoundariesStore.addBoundary(name: boundaryName, points: storedPoints) != nil {
            dismiss()
        }
    }
}

private struct AreaBoundaryNamingSheet: View {
    @Binding var boundaryName: String
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    private var trimmedName: String {
        boundaryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Map name", text: $boundaryName)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Name Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
