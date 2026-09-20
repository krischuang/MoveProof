import SwiftUI

/// Screen 2 — add the property, or change its details later.
struct TenancySetupView: View {

    @Environment(MoveProofModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TenancySetupViewModel

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: TenancySetupViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let inlineMessage = viewModel.inlineMessage {
                    Section {
                        TenantMessageBanner(message: inlineMessage)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    TextField(
                        "Street address",
                        text: Binding(
                            get: { viewModel.propertyAddress },
                            set: { viewModel.propertyAddress = $0 }
                        ),
                        axis: .vertical
                    )
                    .textInputAutocapitalization(.words)
                    .lineLimit(1...3)
                } header: {
                    Text("Property")
                } footer: {
                    Text("Use the address exactly as it appears on your tenancy agreement, so your evidence is easy to match to the right property later.")
                }

                Section {
                    DatePicker(
                        "Move-in date",
                        selection: Binding(
                            get: { viewModel.moveInDate },
                            set: { viewModel.moveInDate = $0; viewModel.moveInDateChanged() }
                        ),
                        displayedComponents: .date
                    )

                    Toggle(
                        "Use the standard seven-day window",
                        isOn: Binding(
                            get: { viewModel.usesDefaultDueDate },
                            set: { viewModel.usesDefaultDueDate = $0; viewModel.defaultDueDateToggled() }
                        )
                    )

                    DatePicker(
                        "Condition report due",
                        selection: Binding(
                            get: { viewModel.conditionReportDueDate },
                            set: { viewModel.conditionReportDueDate = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .disabled(viewModel.usesDefaultDueDate)
                } header: {
                    Text("Dates")
                } footer: {
                    Text(viewModel.dueDateFootnote)
                }

                if !viewModel.isEditingExistingTenancy {
                    Section {
                        Label(
                            "MoveProof will set up \(InspectionArea.defaultAreaNames.count) rooms with a condition checklist in each one. You can rename or remove rooms once the walkthrough starts.",
                            systemImage: "square.grid.2x2"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(viewModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.saveButtonTitle) {
                        if viewModel.save() {
                            model.dataChanged()
                            dismiss()
                        }
                    }
                    .disabled(viewModel.propertyAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .tenantMessageAlert($viewModel.message)
            .task { viewModel.load() }
        }
    }
}
