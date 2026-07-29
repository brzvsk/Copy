import SwiftUI
import CopyCore

struct ShelfRootView: View {
    @Bindable var viewModel: ShelfViewModel

    var body: some View {
        VStack(spacing: 0) {
            ShelfHeader(viewModel: viewModel)
            Divider()
            ShelfItemsRow(viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ShelfBackground())
    }
}

private struct ShelfHeader: View {
    @Bindable var viewModel: ShelfViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search history", text: $viewModel.query)
                .textFieldStyle(.plain)
                .frame(maxWidth: 240)
                .focused($searchFocused)
            ForEach(ShelfScope.allCases, id: \.self) { scope in
                ScopeChip(title: scope.title, isOn: viewModel.scope == scope) {
                    viewModel.scope = scope
                }
            }
            Spacer()
            Text("Copy")
                .font(Tokens.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Tokens.shelfPadding)
        .padding(.vertical, 10)
        .onAppear { searchFocused = true }
    }
}

private struct ScopeChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tokens.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.18) : .clear))
                .overlay(Capsule().stroke(isOn ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ShelfItemsRow: View {
    @Bindable var viewModel: ShelfViewModel

    var body: some View {
        if viewModel.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(viewModel.query.isEmpty ? "Copy something to get started" : "No matches for \"\(viewModel.query)\"")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Tokens.cardGap) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.uuid) { index, item in
                            ItemCardView(
                                item: item,
                                isSelected: index == viewModel.selectedIndex,
                                store: viewModel.store,
                                onPaste: { viewModel.requestPaste(item, plain: false) },
                                onPastePlain: { viewModel.requestPaste(item, plain: true) },
                                onToggleFavorite: { viewModel.toggleFavorite(item) },
                                onDelete: { viewModel.delete(item) },
                                dragProvider: { viewModel.dragProvider(for: item) }
                            )
                            .id(item.uuid)
                            .onTapGesture {
                                viewModel.selectedIndex = index
                                viewModel.requestPaste(item, plain: false)
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.shelfPadding)
                    .padding(.vertical, 16)
                }
                .onChange(of: viewModel.selectedIndex) { _, newIndex in
                    if viewModel.items.indices.contains(newIndex) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(viewModel.items[newIndex].uuid, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

private struct ShelfBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
