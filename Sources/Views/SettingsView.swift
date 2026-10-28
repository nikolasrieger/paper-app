import SwiftUI

struct SettingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Reminders.self) private var reminders
    @Environment(\.dismiss) private var dismiss

    @State private var pickingFolder = false

    @ViewBuilder private var folderSection: some View {
        let folder = store.folder
        Section {
            if let name = folder.folderName {
                LabeledContent("Folder", value: name)
                LabeledContent("Synced papers", value: "\(folder.syncedCount)")
                if let last = folder.lastSync { LabeledContent("Last sync", value: last.formatted(date: .omitted, time: .shortened)) }
                Button { Task { await store.syncFolder(force: true) } } label: {
                    if folder.isSyncing { HStack { ProgressView(); Text("Syncing…") } } else { Text("Sync now") }
                }
                Button("Choose a different folder…") { pickingFolder = true }
                Button("Disconnect and remove synced papers", role: .destructive) { store.disconnectFolder() }
            } else {
                Button("Choose papers folder…") { pickingFolder = true }
            }
            if let message = folder.message { Text(message).font(.footnote).foregroundStyle(Theme.warning) }
        } header: { Text("Summaries from your Mac") } footer: {
            Text("Pick the folder that your Mac script writes to (in iCloud Drive, OneDrive or any folder the Files app can open). New papers appear here automatically.")
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                folder.setFolder(url)
                Task { await store.syncFolder(force: true) }
            }
        }
    }

    var body: some View {
        @Bindable var reminders = reminders
        NavigationStack {
            Form {
                Section {
                    Toggle("Daily reminder", isOn: $reminders.enabled)
                    if reminders.enabled {
                        DatePicker("Time", selection: $reminders.time, displayedComponents: .hourAndMinute)
                    }
                } header: { Text("Paper of the day") } footer: {
                    if reminders.denied { Text("Notifications are turned off for PaperDaily in iOS Settings.") }
                    else { Text("A notification with the day's paper, at the time you choose.") }
                }
                folderSection
                Section {
                    NavigationLink("Glossary") { GlossaryView() }
                }
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .onChange(of: reminders.enabled) { _, _ in Task { await reminders.reschedule(using: store) } }
            .onChange(of: reminders.time) { _, _ in Task { await reminders.reschedule(using: store) } }
        }
    }
}
