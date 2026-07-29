import SwiftUI
import CopyCore

struct PreviewPane: View {
    let item: ClipItem
    let store: ItemStore

    var body: some View {
        Group {
            switch item.kind {
            case .image:
                CardThumbnail(item: item, store: store)
                    .padding(12)
            case .color:
                VStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Tokens.color(fromHex: item.plainText ?? ""))
                    Text(item.plainText ?? "")
                        .font(.system(size: 15, design: .monospaced))
                }
                .padding(16)
            default:
                ScrollView {
                    Text(String((item.plainText ?? "").prefix(200_000)))
                        .font(.system(size: 13, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
            }
        }
        .frame(width: 420, height: 320)
    }
}
