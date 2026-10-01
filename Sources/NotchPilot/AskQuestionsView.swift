import SwiftUI

/// Full AskUserQuestion UI for the notch.
///
/// Walks
/// through every question in the batch (1–4), supports multi-select and a
/// free-text "own answer", and submits all answers at once through
/// `HookBridge.submitAnswers` (a native allow + `answers`).
struct AskQuestionsView: View {
    let permission: PendingPermission
    let accent: Color
    let accentBorder: Color
    let onSubmit: ([String: String]) -> Void
    let onCancel: () -> Void

    @State private var index = 0
    @State private var selected: [Int: Set<Int>] = [:]
    @State private var otherText: [Int: String] = [:]
    @State private var editingOther = false
    @FocusState private var otherFocused: Bool

    private var questions: [AskQuestion] { permission.askQuestions }
    private var current: AskQuestion { questions[min(index, questions.count - 1)] }
    private var isLast: Bool { index >= questions.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if questions.count > 1 || !current.header.isEmpty {
                HStack(spacing: 6) {
                    if questions.count > 1 {
                        Text("Question \(index + 1) of \(questions.count)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(accent)
                    }
                    if !current.header.isEmpty {
                        Text(current.header)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    if current.multiSelect {
                        Text("select all that apply")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }

            Text(current.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(current.options) { option in
                        optionButton(option)
                    }
                    otherRow
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .onDisappear { NotchWindow.setKeyboardFocus(false) }

        Spacer(minLength: 0)

        HStack(spacing: 8) {
            if index > 0 {
                footerButton("Back", primary: false) { go(to: index - 1) }
            }
            footerButton("Cancel", primary: false) {
                NotchWindow.setKeyboardFocus(false)
                onCancel()
            }
            .keyboardShortcut(.cancelAction)
            if current.multiSelect || editingOther || hasAnswer(current.id) {
                footerButton(isLast ? "Submit" : "Next", primary: true) { advance() }
                    .disabled(!hasAnswer(current.id))
                    .opacity(hasAnswer(current.id) ? 1 : 0.4)
            }
        }
    }

    // MARK: - Rows

    private func optionButton(_ option: AskOption) -> some View {
        let isOn = selected[current.id]?.contains(option.id) ?? false
        return Button {
            toggle(option)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                if current.multiSelect {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isOn ? accent : .white.opacity(0.5))
                        .padding(.top, 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let desc = option.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(isOn ? 0.38 : 0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(isOn ? accent : accentBorder, lineWidth: isOn ? 1 : 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var otherRow: some View {
        if editingOther {
            TextField("Your answer…", text: Binding(
                get: { otherText[current.id] ?? "" },
                set: { otherText[current.id] = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .rounded))
            .foregroundColor(.white)
            .focused($otherFocused)
            .onSubmit { if hasAnswer(current.id) { advance() } }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(accent, lineWidth: 1)
                    )
            )
        } else {
            Button {
                editingOther = true
                NotchWindow.setKeyboardFocus(true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { otherFocused = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Other…")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func footerButton(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(primary ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(primary ? accent : Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(Color.white.opacity(primary ? 0 : 0.2), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private func toggle(_ option: AskOption) {
        let qid = current.id
        if current.multiSelect {
            var set = selected[qid] ?? []
            if set.contains(option.id) { set.remove(option.id) } else { set.insert(option.id) }
            selected[qid] = set
        } else {
            // Single choice: pick and move on, like the terminal dialog.
            selected[qid] = [option.id]
            otherText[qid] = nil
            advance()
        }
    }

    private func hasAnswer(_ qid: Int) -> Bool {
        let picked = !(selected[qid] ?? []).isEmpty
        let typed = !(otherText[qid] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return picked || typed
    }

    private func answer(for q: AskQuestion) -> String {
        let typed = (otherText[q.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let labels = q.options
            .filter { (selected[q.id] ?? []).contains($0.id) }
            .map(\.label)
        if q.multiSelect {
            return (labels + (typed.isEmpty ? [] : [typed])).joined(separator: ", ")
        }
        return typed.isEmpty ? (labels.first ?? "") : typed
    }

    private func go(to i: Int) {
        index = i
        editingOther = !(otherText[questions[i].id] ?? "").isEmpty
        if !editingOther { NotchWindow.setKeyboardFocus(false) }
    }

    private func advance() {
        guard hasAnswer(current.id) else { return }
        if isLast {
            NotchWindow.setKeyboardFocus(false)
            var answers: [String: String] = [:]
            for q in questions { answers[q.text] = answer(for: q) }
            onSubmit(answers)
        } else {
            go(to: index + 1)
        }
    }
}
