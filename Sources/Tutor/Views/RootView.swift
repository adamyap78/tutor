import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            switch model.dataState {
            case .ready: MainView().ignoresSafeArea(.container, edges: .top)
            case .needsData: OnboardingView()
            case .loading: EmptyView()
            }
        }
        .background(WindowConfigurator())
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.isMovableByWindowBackground = true
            v.window?.titlebarAppearsTransparent = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                v.window?.standardWindowButton(b)?.isHidden = true
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if model.mode == .detail {
                    DetailView()
                } else {
                    HStack(spacing: 0) {
                        Group {
                            if model.count == 0 { EmptyResults() }
                            else { ResultGrid() }
                        }
                        .frame(minWidth: 320, maxWidth: .infinity)
                        PreviewPane()
                            .frame(width: PreviewPane.width)
                    }
                }
                // Floats over the results column only; kept alive (hidden) while inspecting so the field still receives the keyboard.
                SearchBar()
                    .padding(.trailing, model.mode == .detail ? 0 : PreviewPane.width + 1)
                    .frame(height: model.mode == .detail ? 0 : nil)
                    .clipped()
                    .opacity(model.mode == .detail ? 0 : 1)
                    .allowsHitTesting(model.mode != .detail)
            }
        }
    }
}
