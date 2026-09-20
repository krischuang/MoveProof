import SwiftUI

/// A domain error turned into something a tenant can read and act on.
///
/// Every error that reaches the screen goes through here, which is what guarantees
/// MoveProof never shows "Save failed": anything that is not already a
/// `TenantFacingError` is wrapped in `UnexpectedFailure`, whose wording still tells
/// the tenant what was happening and what to try.
struct TenantMessage: Identifiable, Equatable {

    let id = UUID()
    let title: String
    let whatHappened: String
    let whatToDoNext: String

    /// - Parameter whileDoing: what the tenant was doing, in their words, used only
    ///   when the error is not a domain rule. For example "signing off this room".
    init(_ error: Error, whileDoing: String) {
        if let tenantFacing = error as? TenantFacingError {
            title = tenantFacing.title
            whatHappened = tenantFacing.whatHappened
            whatToDoNext = tenantFacing.whatToDoNext
        } else {
            // Technical detail goes to the log, never to the tenant.
            AppLog.inspection.error("Unexpected failure while \(whileDoing): \(error)")
            let wrapped = UnexpectedFailure(underlying: error, whileDoing: whileDoing)
            title = wrapped.title
            whatHappened = wrapped.whatHappened
            whatToDoNext = wrapped.whatToDoNext
        }
    }

    init(title: String, whatHappened: String, whatToDoNext: String) {
        self.title = title
        self.whatHappened = whatHappened
        self.whatToDoNext = whatToDoNext
    }

    static func == (lhs: TenantMessage, rhs: TenantMessage) -> Bool {
        lhs.id == rhs.id
    }
}

extension View {

    /// Presents a domain message as an alert, with the recovery step in the body
    /// rather than hidden behind a help link.
    func tenantMessageAlert(_ message: Binding<TenantMessage?>) -> some View {
        alert(
            message.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: { presented in
            Text("\(presented.whatHappened)\n\n\(presented.whatToDoNext)")
        }
    }
}

/// Inline version of the same wording, used where an alert would interrupt a form
/// the tenant is still filling in.
struct TenantMessageBanner: View {

    let message: TenantMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message.title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message.whatHappened)
                .font(.subheadline)
            Text(message.whatToDoNext)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.title). \(message.whatHappened) \(message.whatToDoNext)")
    }
}
