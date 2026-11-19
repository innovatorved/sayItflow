import AppKit
import SwiftUI

/// Searchable, timestamped log of all local voice dictations.
struct TranscriptHistoryView: View {
    @ObservedObject private var history = TranscriptHistoryStore.shared
    @ObservedObject private var settings = AppSettings.shared

    @State private var searchQuery = ""
    @State private var copiedID: UUID?
    @State private var expandedRawIDs: Set<UUID> = []
    @State private var showClearConfirmation = false
    @State private var exportedFeedback = false

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .medium
        return df
    }()

    private static let dayHeaderFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        return df
    }()

    private var filteredEntries: [TranscriptEntry] {
        history.filtered(query: searchQuery)
    }

    private var groupedByDay: [(title: String, entries: [TranscriptEntry])] {
        let calendar = Calendar.current
        var groups: [(key: Date, title: String, entries: [TranscriptEntry])] = []

        for entry in filteredEntries {
            let dayStart = calendar.startOfDay(for: entry.timestamp)
            if let idx = groups.firstIndex(where: { $0.key == dayStart }) {
                groups[idx].entries.append(entry)
            } else {
                let title: String
                if calendar.isDateInToday(dayStart) {
                    title = "Today"
                } else if calendar.isDateInYesterday(dayStart) {
                    title = "Yesterday"
                } else {
                    title = Self.dayHeaderFormatter.string(from: dayStart)
                }
                groups.append((key: dayStart, title: title, entries: [entry]))
            }
        }
        return groups.map { (title: $0.title, entries: $0.entries) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            toolbarCard

            if history.entries.isEmpty {
                emptyStateCard
            } else if filteredEntries.isEmpty {
                noMatchesCard
            } else {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(groupedByDay, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.title.uppercased())
                                    .font(DesignTokens.fontMono(size: 10, weight: .semibold))
                                    .tracking(DesignTokens.trackingLoose)
                                    .foregroundStyle(DesignTokens.textMuted)
                                Spacer()
                                Text("\(group.entries.count) \(group.entries.count == 1 ? "note" : "notes")")
                                    .font(DesignTokens.fontMono(size: 10))
                                    .foregroundStyle(DesignTokens.textMuted)
                            }
                            .padding(.horizontal, 2)

                            ForEach(group.entries) { entry in
                                entryCard(entry)
                            }
                        }
                    }
                }
            }
        }
        .alert("Clear all saved transcripts?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                history.deleteAll()
            }
        } message: {
            Text("This permanently deletes all \(history.entries.count) saved transcripts from this Mac.")
        }
    }

    // MARK: - Toolbar

    private var toolbarCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textMuted)
                    TextField("Search transcripts or apps…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(DesignTokens.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusMd)
                        .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                )

                if !history.entries.isEmpty {
                    Button(exportedFeedback ? "Copied MD" : "Copy All") {
                        copyText(history.exportMarkdown())
                        exportedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            exportedFeedback = false
                        }
                    }
                    .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))

                    Button("Clear") {
                        showClearConfirmation = true
                    }
                    .buttonStyle(MonochromeGhostButtonStyle())
                }
            }

            HStack(spacing: 16) {
                statPill(label: "SAVED", value: "\(history.entries.count)")
                statPill(label: "WORDS", value: "\(history.totalWords)")
                Spacer()
                Text("Stored 100% locally on this Mac")
                    .font(DesignTokens.fontMono(size: 10))
                    .foregroundStyle(DesignTokens.textMuted)
            }
        }
        .monochromeCard(radius: DesignTokens.radiusMd, padding: 12)
    }

    private func statPill(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(DesignTokens.fontMono(size: 9, weight: .medium))
                .tracking(DesignTokens.trackingLoose)
                .foregroundStyle(DesignTokens.textMuted)
            Text(value)
                .font(DesignTokens.fontMono(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }

    // MARK: - Entry Card

    private func entryCard(_ entry: TranscriptEntry) -> some View {
        let isCopied = copiedID == entry.id
        let isRawExpanded = expandedRawIDs.contains(entry.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(DesignTokens.fontMono(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)

                if let appName = entry.targetAppName, !appName.isEmpty {
                    chip(appName)
                }

                chip("\(entry.wordCount)w")

                if entry.durationSeconds > 0 {
                    chip(String(format: "%.1fs", entry.durationSeconds))
                }

                if !entry.injectionSucceeded {
                    Text("Clipboard only")
                        .font(DesignTokens.fontMono(size: 9, weight: .medium))
                        .foregroundStyle(DesignTokens.warningFg)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignTokens.warningBg, in: RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                if entry.rawText != nil {
                    Button(isRawExpanded ? "Hide Raw" : "Raw") {
                        if isRawExpanded {
                            expandedRawIDs.remove(entry.id)
                        } else {
                            expandedRawIDs.insert(entry.id)
                        }
                    }
                    .font(DesignTokens.fontMono(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.textMuted)
                    .buttonStyle(.plain)
                }

                Button {
                    copyText(entry.text)
                    copiedID = entry.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        if copiedID == entry.id { copiedID = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? DesignTokens.successFg : DesignTokens.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusSm)
                            .stroke(DesignTokens.borderSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    history.delete(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textMuted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Delete transcript")
            }

            Text(entry.text)
                .font(.system(size: 13))
                .foregroundStyle(DesignTokens.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if isRawExpanded, let raw = entry.rawText {
                VStack(alignment: .leading, spacing: 3) {
                    Text("RAW VOZ OUTPUT")
                        .font(DesignTokens.fontMono(size: 9, weight: .semibold))
                        .tracking(DesignTokens.trackingLoose)
                        .foregroundStyle(DesignTokens.textMuted)
                    Text(raw)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: DesignTokens.radiusSm))
            }
        }
        .monochromeCard(radius: DesignTokens.radiusMd, padding: 12)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(DesignTokens.fontMono(size: 10))
            .foregroundStyle(DesignTokens.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignTokens.surfaceSubtle, in: RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DesignTokens.borderSubtle, lineWidth: 1)
            )
    }

    // MARK: - Empty States

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 26))
                .foregroundStyle(DesignTokens.textMuted)
            Text("No transcriptions yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Hold \(settings.hotkeyMode.label) anywhere, speak, and release. Every dictation is automatically saved here with its exact timestamp.")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .monochromeCard(radius: DesignTokens.radiusMd, padding: 16)
    }

    private var noMatchesCard: some View {
        VStack(spacing: 8) {
            Text("No transcripts match \"\(searchQuery)\"")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
            Button("Clear Search") {
                searchQuery = ""
            }
            .buttonStyle(MonochromeOutlineButtonStyle(isCompact: true))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .monochromeCard(radius: DesignTokens.radiusMd, padding: 16)
    }

    private func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
