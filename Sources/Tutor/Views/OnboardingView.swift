import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Setting up your card library").font(.system(size: 22, weight: .semibold))
            Text("A one-time download of every Magic card from Scryfall. After this, everything works offline.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)

            if let err = model.importError {
                VStack(spacing: 12) {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13)).foregroundStyle(.orange)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Try Again") { model.refreshData(force: true, silent: false) }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                }
                .padding(.top, 8)
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: model.progress?.fraction ?? 0).frame(width: 320)
                    Text(model.progress?.detail ?? "Preparing…")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
