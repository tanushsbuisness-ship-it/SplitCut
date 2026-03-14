import SwiftUI
import ARKit
import SceneKit
import simd

// MARK: - Phase

enum MeasurePhase: Equatable {
    case widthFirst    // waiting for first width tap
    case widthSecond   // first width point placed, waiting for second
    case lengthFirst   // width done, waiting for first length tap
    case lengthSecond  // first length point placed, waiting for second
    case done          // both measurements complete
}

// MARK: - Observable state

/// Shared between ARContainerView (UIKit side) and ARMeasureSheet (SwiftUI side).
@Observable
final class ARMeasurementState {
    var phase:        MeasurePhase = .widthFirst
    var widthMeters:  Double?      = nil
    var lengthMeters: Double?      = nil
    var message: String = "Point at the board and tap a corner to begin measuring Width."

    var widthInches:  Double? { widthMeters.map  { $0 * 39.3701 } }
    var lengthInches: Double? { lengthMeters.map { $0 * 39.3701 } }

    func resetWidth() {
        phase        = .widthFirst
        widthMeters  = nil
        message      = "Tap a corner to re-measure Width."
    }

    func resetAll() {
        phase        = .widthFirst
        widthMeters  = nil
        lengthMeters = nil
        message      = "Point at the board and tap a corner to begin measuring Width."
    }
}

// MARK: - Main sheet view

struct ARMeasureSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Called with (widthInches, lengthInches) when user confirms.
    let onMeasured: (Double, Double) -> Void

    @State private var arState = ARMeasurementState()
    private var isARSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    var body: some View {
        if isARSupported {
            arOverlayView
        } else {
            arUnavailableView
        }
    }

    // MARK: AR overlay

    private var arOverlayView: some View {
        ZStack(alignment: .bottom) {
            ARContainerView(state: arState)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                crosshairIcon
                Spacer()
                bottomPanel
            }
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
                .padding()
            Spacer()
            if let w = arState.widthInches, let l = arState.lengthInches {
                Text(String(format: "W: %.2f\"  L: %.2f\"", w, l))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding()
            }
        }
        .background(.ultraThinMaterial)
    }

    private var crosshairIcon: some View {
        Image(systemName: "plus")
            .font(.title2)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 3)
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            Text(arState.message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal)
                .animation(.easeInOut, value: arState.message)

            HStack(spacing: 16) {
                MeasureBadge(
                    label: "Width",
                    value: arState.widthInches.map { String(format: "%.2f\"", $0) },
                    isActive: arState.phase == .widthFirst || arState.phase == .widthSecond,
                    color: .yellow
                )
                MeasureBadge(
                    label: "Length",
                    value: arState.lengthInches.map { String(format: "%.2f\"", $0) },
                    isActive: arState.phase == .lengthFirst || arState.phase == .lengthSecond,
                    color: .cyan
                )
            }

            HStack(spacing: 12) {
                // Allow re-measuring width after it's been set
                if arState.widthMeters != nil &&
                    arState.phase != .widthFirst &&
                    arState.phase != .widthSecond {
                    Button("Redo Width") { arState.resetWidth() }
                        .buttonStyle(.bordered)
                        .tint(.yellow)
                }

                if arState.phase == .done,
                   let w = arState.widthInches,
                   let l = arState.lengthInches {
                    Button {
                        onMeasured(w, l)
                        dismiss()
                    } label: {
                        Label("Use Measurements", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: Fallback

    private var arUnavailableView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arkit")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("AR Not Available")
                .font(.title2.bold())
            Text("This device doesn't support AR World Tracking. Enter dimensions manually.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

// MARK: - Badge subview

private struct MeasureBadge: View {
    let label: String
    let value: String?
    let isActive: Bool
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(color)
            Text(value ?? "—")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? color : Color.white.opacity(0.3),
                                lineWidth: isActive ? 2 : 1)
                )
        )
        .animation(.easeInOut, value: isActive)
    }
}

// MARK: - UIViewRepresentable wrapper

struct ARContainerView: UIViewRepresentable {
    let state: ARMeasurementState

    func makeCoordinator() -> ARCoordinator {
        ARCoordinator(state: state)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView(frame: .zero)
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(config)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(ARCoordinator.handleTap(_:))
        )
        sceneView.addGestureRecognizer(tap)
        context.coordinator.sceneView = sceneView
        return sceneView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Sync scene nodes when state changes from SwiftUI (e.g. "Redo Width")
        context.coordinator.syncIfNeeded()
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: ARCoordinator) {
        uiView.session.pause()
    }
}

// MARK: - AR Coordinator

/// Handles raycasting, node placement, and line drawing.
/// All methods are @MainActor (enforced by SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
final class ARCoordinator: NSObject {

    let state: ARMeasurementState
    weak var sceneView: ARSCNView?

    /// The first tap point of the current measurement segment.
    private var pointA: simd_float3? = nil

    // Node name constants for lookup and removal
    private enum NodeName {
        static let widthA  = "w_a"
        static let widthB  = "w_b"
        static let widthLine = "w_line"
        static let lengthA = "l_a"
        static let lengthB = "l_b"
        static let lengthLine = "l_line"
    }

    init(state: ARMeasurementState) {
        self.state = state
    }

    // MARK: - State sync (called from updateUIView)

    @MainActor
    func syncIfNeeded() {
        guard let view = sceneView else { return }
        // If width was reset from SwiftUI, remove width nodes and reset tap state
        if state.phase == .widthFirst && pointA != nil {
            [NodeName.widthA, NodeName.widthB, NodeName.widthLine].forEach {
                view.scene.rootNode.childNode(withName: $0, recursively: false)?.removeFromParentNode()
            }
            pointA = nil
        }
    }

    // MARK: - Tap handling

    @MainActor
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = sceneView else { return }
        let location = gesture.location(in: view)

        guard let query = view.raycastQuery(
            from: location,
            allowing: .estimatedPlane,
            alignment: .any
        ) else {
            state.message = "Could not perform raycast. Try a different angle."
            return
        }

        guard let hit = view.session.raycast(query).first else {
            state.message = "No surface detected. Move closer or aim at a flat surface."
            return
        }

        let col = hit.worldTransform.columns.3
        process(worldPos: simd_float3(col.x, col.y, col.z), in: view)
    }

    @MainActor
    private func process(worldPos: simd_float3, in view: ARSCNView) {
        switch state.phase {

        case .widthFirst:
            pointA = worldPos
            addSphere(at: worldPos, color: .systemYellow, name: NodeName.widthA, in: view)
            state.phase   = .widthSecond
            state.message = "Now tap the opposite end of the Width."

        case .widthSecond:
            guard let start = pointA else { return }
            addSphere(at: worldPos, color: .systemYellow, name: NodeName.widthB, in: view)
            drawLine(from: start, to: worldPos, color: .systemYellow, name: NodeName.widthLine, in: view)
            let dist = simd_distance(start, worldPos)
            state.widthMeters = Double(dist)
            state.phase       = .lengthFirst
            state.message     = String(format: "Width: %.2f\". Tap a corner to measure Length.", dist * 39.3701)
            pointA = nil

        case .lengthFirst:
            pointA = worldPos
            addSphere(at: worldPos, color: .systemCyan, name: NodeName.lengthA, in: view)
            state.phase   = .lengthSecond
            state.message = "Tap the opposite end for Length."

        case .lengthSecond:
            guard let start = pointA else { return }
            addSphere(at: worldPos, color: .systemCyan, name: NodeName.lengthB, in: view)
            drawLine(from: start, to: worldPos, color: .systemCyan, name: NodeName.lengthLine, in: view)
            let dist = simd_distance(start, worldPos)
            state.lengthMeters = Double(dist)
            state.phase        = .done
            let w = (state.widthMeters ?? 0) * 39.3701
            let l = Double(dist) * 39.3701
            state.message = String(format: "✓ Width %.2f\"  ×  Length %.2f\"  — tap Use to confirm.", w, l)
            pointA = nil

        case .done:
            break
        }
    }

    // MARK: - SceneKit helpers

    private func addSphere(at position: simd_float3, color: UIColor, name: String, in view: ARSCNView) {
        let sphere = SCNSphere(radius: 0.008)
        sphere.firstMaterial?.diffuse.contents = color
        sphere.firstMaterial?.lightingModel     = .constant

        let node = SCNNode(geometry: sphere)
        node.name = name
        node.simdWorldPosition = position
        view.scene.rootNode.addChildNode(node)
    }

    private func drawLine(from start: simd_float3, to end: simd_float3,
                          color: UIColor, name: String, in view: ARSCNView) {
        let vector = end - start
        let length = simd_length(vector)
        guard length > 0.001 else { return }

        let cylinder = SCNCylinder(radius: 0.003, height: CGFloat(length))
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.lightingModel     = .constant

        let node = SCNNode(geometry: cylinder)
        node.name = name
        node.simdWorldPosition = (start + end) * 0.5

        // Rotate SCNCylinder (default Y-up) to align with the measurement vector
        let yAxis = simd_float3(0, 1, 0)
        let dir   = simd_normalize(vector)
        let cross = simd_cross(yAxis, dir)
        let dot   = simd_dot(yAxis, dir)

        if simd_length(cross) > 0.001 {
            // General case: axis-angle rotation
            let angle = acos(simd_clamp(dot, -1.0 as Float, 1.0 as Float))
            node.simdOrientation = simd_quatf(angle: angle, axis: simd_normalize(cross))
        } else if dot < 0 {
            // Anti-parallel (pointing down): flip 180° around X
            node.simdOrientation = simd_quatf(angle: .pi, axis: simd_float3(1, 0, 0))
        }
        // else: already aligned with Y — no rotation needed

        view.scene.rootNode.addChildNode(node)
    }
}
