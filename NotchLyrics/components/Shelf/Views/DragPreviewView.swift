import SwiftUI
import AppKit

struct DragPreviewView: View {
    let thumbnail: NSImage?
    let displayName: String

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Image(nsImage: thumbnail ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: NLShelf.iconSize, height: NLShelf.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: NLShelf.cardRadius))

            Text(displayName)
                .font(NLShelf.nameFont)
                .foregroundColor(NLShelf.nameOnAccent)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: NLShelf.chipRadius).fill(Color.accentColor))
                .frame(alignment: .top)
        }
        .frame(width: NLShelf.itemWidth)
    }
}
