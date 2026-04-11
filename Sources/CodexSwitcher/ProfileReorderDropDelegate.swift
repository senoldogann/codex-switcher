import SwiftUI
import UniformTypeIdentifiers

struct ProfileReorderDropDelegate: DropDelegate {
    let destinationIndex: Int
    let reorder: (UUID, Int) -> Void
    let setTargetIndex: (Int?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        setTargetIndex(destinationIndex)
    }

    func dropExited(info: DropInfo) {
        setTargetIndex(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.text]).first else {
            setTargetIndex(nil)
            return false
        }

        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { value, _ in
            let identifier: String?
            if let data = value as? Data {
                identifier = String(data: data, encoding: .utf8)
            } else {
                identifier = value as? String
            }

            guard let rawIdentifier = identifier?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  let draggedProfileId = UUID(uuidString: rawIdentifier) else {
                DispatchQueue.main.async {
                    setTargetIndex(nil)
                }
                return
            }

            DispatchQueue.main.async {
                reorder(draggedProfileId, destinationIndex)
                setTargetIndex(nil)
            }
        }

        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
