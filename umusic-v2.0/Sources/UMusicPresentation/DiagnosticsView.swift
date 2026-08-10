import SwiftUI
import UMusicCore

struct DiagnosticsView: View {
    let provider: any DiagnosticsProviding
    @State private var snapshot = DiagnosticsSnapshot(frameworkVersion: "Loading", schemaVersion: 0)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Versions") {
                    LabeledContent("Framework", value: snapshot.frameworkVersion)
                    LabeledContent("Build", value: snapshot.buildIdentifier)
                    LabeledContent("Data schema", value: String(snapshot.schemaVersion))
                    LabeledContent("Ranker", value: snapshot.modelVersion)
                    LabeledContent("Features", value: snapshot.featureSchemaVersion)
                }
                Section("Status") {
                    if snapshot.issues.isEmpty { Label("No known local issues", systemImage: "checkmark.circle") }
                    ForEach(snapshot.issues) { issue in
                        VStack(alignment: .leading) {
                            Text(issue.code).font(.body.monospaced())
                            ForEach(issue.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                LabeledContent(key, value: value).font(.caption)
                            }
                        }
                    }
                }
                Text("Diagnostics contain stable codes and redacted build/schema state only. They exclude credentials, URLs, paths, coordinates, Health data, and listening timelines.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Diagnostics")
            .toolbar { Button("Done") { dismiss() } }
            .task { snapshot = await provider.snapshot() }
        }
    }
}
