import SwiftUI
import ClipVaultCore

struct PanelView: View {
    @ObservedObject var model: PanelViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索剪贴板历史…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if model.filtered.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(model.query.isEmpty ? "还没有剪贴板记录" : "没有匹配的记录")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                                ClipRowView(
                                    item: item,
                                    thumbnail: model.thumbnail(for: item),
                                    selected: index == model.selectedIndex,
                                    index: index
                                )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.confirm(at: index)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: model.selectedIndex) { _, newIndex in
                        if model.filtered.indices.contains(newIndex) {
                            proxy.scrollTo(model.filtered[newIndex].id, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("↩ 复制　⌘1–9 快速复制　⌘⌫ 删除　esc 关闭")
                Spacer()
                Text("\(model.filtered.count) 条")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 640, height: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.focusTick) { _, _ in
            searchFocused = true
        }
    }
}

struct ClipRowView: View {
    let item: ClipItem
    let thumbnail: NSImage?
    let selected: Bool
    let index: Int

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewText)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if item.isSensitive {
                        Text("敏感")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.25), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if let app = item.sourceAppName {
                        Text(app)
                    }
                    Text(Self.timeFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
                    Text(ByteFormat.string(item.byteSize))
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            selected ? Color.accentColor.opacity(0.22) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if item.isSensitive {
            Image(systemName: "key.fill")
                .font(.system(size: 16))
                .foregroundStyle(.orange)
        } else if item.isImage {
            Image(systemName: "photo")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
    }
}
