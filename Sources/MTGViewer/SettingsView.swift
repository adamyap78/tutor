import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            ArtSettings()
                .tabItem { Label("Preview Art", systemImage: "photo") }
            ExclusionSettings()
                .tabItem { Label("Exclusions", systemImage: "eye.slash") }
            SetSettings()
                .tabItem { Label("Sets", systemImage: "square.stack.3d.up") }
        }
        .frame(width: 580, height: 600)
        .onAppear { model.loadSetCatalog() }
    }
}

private struct SettingToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

private struct HiddenSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.hiddenCount > 0 {
            Text("Hiding \(model.hiddenCount.formatted()) cards that only exist in excluded printings.")
        } else {
            Text("Excluded printings are never shown as a card's preview or in its printing list. Cards that exist only in excluded printings are hidden from search.")
        }
    }
}

// MARK: - Preview art

private struct ArtSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("Show the", selection: model.binding(\.art.newestFirst)) {
                    Text("Oldest printing").tag(false)
                    Text("Newest printing").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Don’t go older than", selection: model.binding(\.art.cutoff)) {
                    ForEach(Cutoff.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Which printing represents a card")
            } footer: {
                Text("A card whose only printings are older than the cutoff still shows its oldest one.")
            }

            Section {
                SettingToggle(title: "English", detail: "Over printings in other languages",
                              isOn: model.binding(\.art.preferEnglish))
                SettingToggle(title: "Paper", detail: "Over digital-only printings",
                              isOn: model.binding(\.art.preferPaper))
                SettingToggle(title: "Non-promo", detail: "Over prerelease, buy-a-box and other promos",
                              isOn: model.binding(\.art.preferNonPromo))
                SettingToggle(title: "Standard frame", detail: "Over borderless, full-art, showcase and extended art",
                              isOn: model.binding(\.art.preferStandardFrame))
            } header: {
                Text("When choosing, prefer")
            } footer: {
                Text("Applied in the order above, after the cutoff. Memorabilia and oversized cards are always the last resort.")
            }

            Section {
                Button("Reset Art Preferences") { model.updatePrefs { $0.art = ArtPreferences() } }
                    .disabled(model.prefs.art == ArtPreferences())
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Exclusions

private struct ExclusionSettings: View {
    @Environment(AppModel.self) private var model

    private var types: [(type: String, title: String, detail: String)] {
        guard !model.setCatalog.isEmpty else { return SetKinds.all }
        let present = Set(model.setCatalog.map(\.type))
        return SetKinds.all.filter { present.contains($0.type) }
    }

    var body: some View {
        Form {
            Section("Digital") {
                SettingToggle(title: "Magic Online–only", detail: "Printings that never existed on paper",
                              isOn: model.binding(\.exclude.mtgoOnly))
                SettingToggle(title: "Arena–only", detail: "Including Alchemy rebalances",
                              isOn: model.binding(\.exclude.arenaOnly))
            }

            Section("Kinds of printing") {
                SettingToggle(title: "Promos", detail: "Any printing flagged as a promo, in any set",
                              isOn: model.binding(\.exclude.promos))
                SettingToggle(title: "Oversized", isOn: model.binding(\.exclude.oversized))
                SettingToggle(title: "Non-English", isOn: model.binding(\.exclude.nonEnglish))
            }

            Section {
                ForEach(types, id: \.type) { kind in
                    SettingToggle(title: kind.title, detail: kind.detail,
                                  isOn: model.member(\.exclude.setTypes, kind.type))
                }
            } header: {
                Text("Types of set")
            } footer: {
                HiddenSummary()
            }

            Section {
                Button("Clear All Exclusions") { model.updatePrefs { $0.exclude = ExclusionPreferences() } }
                    .disabled(model.prefs.exclude.isEmpty)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Individual sets

private final class SetFilter: ObservableObject {
    @Published var text = ""
}

private struct SetSettings: View {
    @Environment(AppModel.self) private var model
    @StateObject private var filter = SetFilter()

    private var visible: [SetInfo] {
        let q = filter.text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.setCatalog }
        return model.setCatalog.filter { $0.name.lowercased().contains(q) || $0.code.contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filter sets by name or code", text: $filter.text)
                    .textFieldStyle(.roundedBorder)
                Button("Clear") { model.updatePrefs { $0.exclude.sets = [] } }
                    .disabled(model.prefs.exclude.sets.isEmpty)
            }
            .padding(12)

            if model.setCatalog.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                List(visible) { set in
                    SetRow(set: set)
                }
                .listStyle(.inset)
            }

            HStack {
                Text("\(model.prefs.exclude.sets.count) sets excluded")
                Spacer()
                if model.hiddenCount > 0 { Text("\(model.hiddenCount.formatted()) cards hidden") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
        }
    }
}

private struct SetRow: View {
    @Environment(AppModel.self) private var model
    let set: SetInfo

    var body: some View {
        let byType = model.prefs.exclude.setTypes.contains(set.type)
        HStack(spacing: 10) {
            Toggle("", isOn: byType ? .constant(true) : model.member(\.exclude.sets, set.code))
                .labelsHidden()
                .disabled(byType)
            VStack(alignment: .leading, spacing: 1) {
                Text(set.name).lineLimit(1)
                Text("\(set.code.uppercased()) · \(set.type.replacingOccurrences(of: "_", with: " ")) · \(set.released.prefix(4))"
                     + (byType ? " · excluded by set type" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(set.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
