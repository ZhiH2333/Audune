#if os(macOS)
import SwiftUI

/// Preview, conflict policy, and confirm UI for a validated preset exchange file.
struct VisualPresetImportSheet: View {
    var library: VisualPresetLibrary
    var entries: [VisualPresetExchange.Entry]
    var onConfirm: (VisualPresetImportPlan) -> Void
    var onCancel: () -> Void

    @State private var policy: VisualPresetImportConflictPolicy = .importAsCopies
    @State private var plan: VisualPresetImportPlan?
    @State private var planError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Presets")
                .font(.headline)
            Text("Review the presets in this file before adding them to your library.")
                .foregroundStyle(.secondary)

            Picker("If a name is already used", selection: $policy) {
                Text("Import as copies").tag(VisualPresetImportConflictPolicy.importAsCopies)
                Text("Skip conflicts").tag(VisualPresetImportConflictPolicy.skipConflicts)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: policy) { _, _ in
                rebuildPlan()
            }

            if let planError {
                Text(planError)
                    .foregroundStyle(.red)
            } else if let plan {
                Text(summary(for: plan))
                    .foregroundStyle(.secondary)
                List {
                    ForEach(Array(plan.items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.entry.name)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(item.entry.mode.title)
                                    .foregroundStyle(.secondary)
                            }
                            Text(statusText(for: item))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(minHeight: 180, maxHeight: 280)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Import") {
                    guard let plan, plan.importCount > 0 else { return }
                    onConfirm(plan)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil || (plan?.importCount ?? 0) == 0 || planError != nil)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { rebuildPlan() }
    }

    private func rebuildPlan() {
        switch VisualPresetImportPlanner.plan(entries: entries, library: library, policy: policy) {
        case .success(let next):
            plan = next
            planError = nil
        case .failure(let error):
            plan = nil
            planError = error.message
        }
    }

    private func summary(for plan: VisualPresetImportPlan) -> String {
        if plan.skippedCount > 0 {
            return String(localized: "Ready to import \(plan.importCount) presets. \(plan.skippedCount) will be skipped.")
        }
        return String(localized: "Ready to import \(plan.importCount) presets.")
    }

    private func statusText(for item: VisualPresetImportItem) -> String {
        switch item.status {
        case .ready:
            return String(localized: "New custom preset")
        case .renamed(let from):
            let to = item.finalName ?? from
            return String(localized: "Name conflict — will import as \"\(to)\"")
        case .skippedConflict:
            return String(localized: "Name conflict — skipped")
        }
    }
}
#endif
