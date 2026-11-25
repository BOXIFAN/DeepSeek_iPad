import SwiftUI

/// 每个格子一份的委托：知道自己对应的图片。
struct ImageCellDropDelegate: DropDelegate {
    let target: MessageImage
    @Binding var items: [MessageImage]
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingID,
              draggingID != target.id,
              let from = items.firstIndex(where: { $0.id == draggingID }),
              let to = items.firstIndex(where: { $0.id == target.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            items.move(fromOffsets: IndexSet(integer: from),
                       toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}
