import SwiftUI

// MARK: - 已发送的文档（气泡里）

struct MessageDocumentChip: View {
    let document: MessageDocument

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: document.iconName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.accent.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(document.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(document.sizeText) · \(document.purpose.title)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(width: 224, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("文档 \(document.filename)，\(document.sizeText)")
    }
}

// MARK: - 待发文档（输入条上方）

struct PendingDocumentChip: View {
    let item: PendingDocument
    var onRemove: () -> Void
    var onRetry: () -> Void

    private var failed: Bool { item.errorText != nil }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if failed { onRetry() }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: failed ? "exclamationmark.triangle.fill" : iconName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(failed ? Color.orange : Theme.accent)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill((failed ? Color.orange : Theme.accent).opacity(0.1))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.filename)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        statusLine
                    }

                    Spacer(minLength: 0)
                }
                .padding(9)
                .frame(width: 224, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(failed ? Color.orange.opacity(0.45) : Color.primary.opacity(0.06),
                                      lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }

    private var iconName: String {
        switch item.filename.lowercased().split(separator: ".").last {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "xls", "xlsx", "csv": return "tablecells"
        case "epub", "mobi": return "book"
        default: return "doc.plaintext"
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch item.phase {
        case .uploading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("上传解析中…")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)

        case .ready:
            Text("已就绪 · \(item.sizeText)")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

        case .failed:
            Text("上传失败 · 点一下重试")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.orange)
                .lineLimit(1)
        }
    }
}
