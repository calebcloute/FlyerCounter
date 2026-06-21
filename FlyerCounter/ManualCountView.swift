import SwiftUI

struct ManualCountView: View {
    @AppStorage("flyerCount") private var flyerCount = 0
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Flyer Count")
                .font(.title)
                .fontWeight(.semibold)

            Text("\(flyerCount)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            VStack(spacing: 12) {
                Button {
                    flyerCount += 1
                    haptic(.medium)
                } label: {
                    Text("+1 Flyer")
                        .font(.title)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                }
                .buttonStyle(.borderedProminent)

                Button("-1 Flyer") {
                    if flyerCount > 0 {
                        flyerCount -= 1
                        haptic(.light)
                    }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(flyerCount == 0)
            }

            Button("Reset", role: .destructive) {
                showResetConfirmation = true
            }
            .buttonStyle(.bordered)
            .disabled(flyerCount == 0)
        }
        .padding()
        .animation(.default, value: flyerCount)
        .alert("Reset Flyer Count", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                flyerCount = 0
                haptic(.rigid)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to reset the flyer count?")
        }
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

#Preview {
    ManualCountView()
}
