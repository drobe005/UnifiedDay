#if os(macOS)
import SwiftUI

/// Today on the Mac: the day's timeline, with the selected item's details in a
/// panel on the right instead of a sheet.
struct MacTodayView: View {
    @Environment(EventKitService.self) private var eventKit
    @State private var items: [TimelineItem] = []
    @State private var hasLoaded = false
    @State private var selectedID: String?
    @State private var showingAttention = false
    @State private var showingOnboarding = false

    private var selectedItem: TimelineItem? {
        items.first { $0.id == selectedID }
    }

    private var attentionCount: Int {
        items.filter { $0.kind == .reminder }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                MacScreenHeader(
                    caption: Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                    title: "Today"
                ) {
                    if eventKit.accessGranted {
                        MacIconButton(help: "Needs attention, \(attentionCount) \(attentionCount == 1 ? "item" : "items")") {
                            showingAttention = true
                        } label: {
                            AttentionBell(count: attentionCount)
                        }
                    }
                    MacIconButton(help: "Refresh (Cmd R)") {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    MacNewButton()
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let item = selectedItem {
                ItemDetailView(item: item, onChange: { Task { await load() } }, onClose: { selectedID = nil })
                    .id(item.id)
                    .frame(width: MacLayout.detailPanelWidth)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(UD.borderSecondary).frame(width: 1)
                    }
                    .padding(.top, MacLayout.titleBarHeight)
                    .background(UD.bgCard)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedID)
        .task {
            if eventKit.accessGranted {
                await load()
            } else if !eventKit.accessNeedsSettings {
                showingOnboarding = true
            }
        }
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView()
                .environment(eventKit)
        }
        .sheet(isPresented: $showingAttention) {
            NeedsAttentionView()
                .environment(eventKit)
        }
        .onChange(of: eventKit.accessGranted) { _, granted in
            if granted {
                showingOnboarding = false
                Task { await load() }
            }
        }
        .onChange(of: eventKit.changeCount) {
            guard eventKit.accessGranted else { return }
            Task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !eventKit.accessGranted {
            AccessPromptView { showingOnboarding = true }
        } else if !hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            UDEmptyState(
                icon: "calendar.badge.checkmark",
                title: "Nothing on the books",
                message: "No events or reminders today. Press Cmd N to add one."
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    TodaySummaryBadges(items: items)
                        .padding(.bottom, 8)
                    ForEach(TodayView.sections(of: items), id: \.title) { section in
                        UDListHeader(title: section.title, count: section.items.count)
                        ForEach(section.items) { item in
                            TimelineRow(item: item) {
                                Task { await load() }
                            }
                        }
                        Spacer().frame(height: 8)
                    }
                }
                .padding(.horizontal, MacLayout.contentPadding)
                .padding(.bottom, MacLayout.contentPadding)
            }
            .environment(\.timelineSelection, $selectedID)
            .environment(\.timelineShowsMoveButtons, true)
        }
    }

    private func load() async {
        items = await eventKit.fetchTimeline(for: .now)
        hasLoaded = true
        await eventKit.refreshBadge()
    }
}
#endif
