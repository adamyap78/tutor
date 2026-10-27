import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct MTGApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel()

    var body: some Scene {
        WindowGroup("MTG Viewer") {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 640)
                .onAppear { model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
                Button("Copy") { model.copyOrName() }.keyboardShortcut("c")
                Button("Copy Card Details") { model.copyDetails() }.keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }.keyboardShortcut("v")
                Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }.keyboardShortcut("a")
            }
            CommandMenu("Cards") {
                Button("Search") { model.focusSearch(selectAll: true) }.keyboardShortcut("k")
                Button("Find") { model.focusSearch(selectAll: true) }.keyboardShortcut("f")
                Divider()
                Button("Toggle Grid / List") { model.toggleLayout() }.keyboardShortcut("g")
                Button("Toggle Card Text") { model.toggleText() }.keyboardShortcut("i")
                Button("Flip Card") { model.flip() }.keyboardShortcut("t")
                Button("Next Printing") { model.stepPrinting(1) }.keyboardShortcut("]")
                Button("Previous Printing") { model.stepPrinting(-1) }.keyboardShortcut("[")
                Button("Open on Scryfall") { model.openScryfall() }.keyboardShortcut("o")
                Divider()
                Toggle("Cache All Card Images", isOn: Binding(get: { model.warmEnabled }, set: { model.setWarm($0) }))
                Picker("On-Demand Image Cache", selection: Binding(get: { model.cacheLimitMB }, set: { model.setCacheLimit($0) })) {
                    ForEach([300, 1024, 2048, 5120, 10240], id: \.self) { mb in
                        Text(mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB").tag(mb)
                    }
                }
                Divider()
                Button("Refresh Card Database") { model.refreshData(force: true, silent: false) }.keyboardShortcut("r")
            }
        }
    }
}
