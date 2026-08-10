import SwiftUI
import UMusicInspector
import UniformTypeIdentifiers

@main
struct UMusicDataInspectorApp: App {
    var body: some Scene { WindowGroup { InspectorView() } }
}

private struct InspectorView: View {
    @State private var package: InspectedResearchPackage?
    @State private var selecting = false
    @State private var selectingStore = false
    @State private var copiedStore: URL?
    @State private var errorMessage: String?
    var body: some View {
        NavigationStack {
            Form {
                Button("Open Research Package") { selecting = true }
                Button("Copy Store for Read-Only Inspection") { selectingStore = true }
                if let package {
                    LabeledContent("Kind", value: package.manifest.exportKind.rawValue.capitalized)
                    LabeledContent("Schema", value: "\(package.manifest.schemaVersion)")
                    LabeledContent("Files", value: "\(package.manifest.files.count)")
                    ForEach(package.manifest.recordCounts.keys.sorted(), id: \.self) { key in LabeledContent(key, value: "\(package.manifest.recordCounts[key] ?? 0)") }
                    Text("Inspector reads the selected export package only. It never opens or mutates the live learning store.").font(.caption).foregroundStyle(.secondary)
                }
                if let copiedStore { LabeledContent("Read-only store copy", value: copiedStore.lastPathComponent) }
            }
            .navigationTitle("uMusic Data Inspector")
            .fileImporter(isPresented: $selecting, allowedContentTypes: [.folder]) { result in
                do { package = try ReadOnlyResearchInspector.inspect(packageAt: result.get()) }
                catch { errorMessage = "The selected package is malformed or unsupported." }
            }
            .fileImporter(isPresented: $selectingStore, allowedContentTypes: [.data]) { result in
                do { copiedStore = try ReadOnlyResearchInspector.protectedReadOnlyCopy(of: result.get()) }
                catch { errorMessage = "The store could not be copied safely." }
            }
            .alert("Unable to Open", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("OK") {} } message: { Text(errorMessage ?? "") }
        }
    }
}
