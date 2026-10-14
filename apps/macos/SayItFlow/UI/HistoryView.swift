import SwiftUI
import AppKit

public struct HistoryView: View {
    @ObservedObject private var store = DictationHistoryStore.shared
    @State private var searchText = ""
    @State private var copiedRecordId: UUID?
    @State private var showClearConfirmation = false

    public init() {}

    private var filteredRecords: [DictationRecord] {
        store.search(query: searchText)
    }

    private var totalWords: Int {
        store.records.reduce(0) { $0 + $1.wordCount }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Search and Controls Bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignTokens.inkMuted)

                    TextField("Search dictations…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.inkPrimary)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.inkMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                        .stroke(DesignTokens.border, lineWidth: 1)
                )

                Spacer()

                if !store.records.isEmpty {
                    HStack(spacing: 6) {
                        Text("\(store.records.count) dictations · \(totalWords) words")
                            .font(DesignTokens.fontMono(size: 11, weight: .medium))
                            .foregroundStyle(DesignTokens.inkMuted)

                        Button("Clear All") {
                            showClearConfirmation = true
                        }
                        .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))
                    }
                }
            }

            // Records List or Empty State
            if filteredRecords.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredRecords) { record in
                        recordRow(record)
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear all dictation history?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                store.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all stored dictations from this Mac.")
        }
    }

    // MARK: - Record Row

    private func recordRow(_ record: DictationRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                // Time & App Badge
                HStack(spacing: 6) {
                    Text(timeString(from: record.timestamp))
                        .font(DesignTokens.fontMono(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.inkMuted)

                    if !record.appName.isEmpty {
                        Text(record.appName)
                            .font(DesignTokens.fontMono(size: 10, weight: .medium))
                            .foregroundStyle(DesignTokens.inkSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                                    .stroke(DesignTokens.border, lineWidth: 1)
                            )
                    }

                    Text("\(record.wordCount)w · \(record.charCount)c")
                        .font(DesignTokens.fontMono(size: 10))
                        .foregroundStyle(DesignTokens.inkMuted)
                }

                Spacer()

                // Actions: Copy & Delete
                HStack(spacing: 6) {
                    Button {
                        copyToClipboard(record)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedRecordId == record.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                            Text(copiedRecordId == record.id ? "Copied" : "Copy")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(copiedRecordId == record.id ? DesignTokens.ready : DesignTokens.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                                .stroke(copiedRecordId == record.id ? DesignTokens.ready.opacity(0.4) : DesignTokens.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(DesignTokens.easeOut) {
                            store.delete(id: record.id)
                        }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.inkMuted)
                            .padding(5)
                            .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                                    .stroke(DesignTokens.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Delete record")
                }
            }

            // Transcript Body
            Text(record.text)
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(3)
                .foregroundStyle(DesignTokens.inkPrimary)
                .textSelection(.enabled)
        }
        .monochromeCard(radius: DesignTokens.radiusMd, padding: 14)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "waveform.and.mic" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(DesignTokens.inkMuted)

            Text(searchText.isEmpty ? "No Dictations Recorded" : "No Matching Dictations")
                .font(DesignTokens.fontDisplay(size: 15, weight: .semibold))
                .tracking(DesignTokens.trackingTight)
                .foregroundStyle(DesignTokens.inkPrimary)

            Text(
                searchText.isEmpty
                    ? "Hold your push-to-talk hotkey to speak anywhere. Your past transcripts will appear here."
                    : "Try searching for a different keyword or app name."
            )
            .font(.system(size: 12))
            .foregroundStyle(DesignTokens.inkSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .monochromeCard(radius: DesignTokens.radiusLg, padding: 24)
    }

    // MARK: - Helpers

    private func copyToClipboard(_ record: DictationRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.text, forType: .string)
        copiedRecordId = record.id

        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedRecordId == record.id {
                copiedRecordId = nil
            }
        }
    }

    private func timeString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        let exactTime = timeFormatter.string(from: date)

        return "\(relative) (\(exactTime))"
    }
}
