import SwiftUI

struct TasksCard: View {
    @Binding var tasks: [FocusTask]
    @State private var newTask = ""
    @FocusState private var isAddingTask: Bool

    private var remaining: Int { tasks.filter { !$0.isComplete }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("A few things for today")
                    .font(.system(size: 23, design: .serif))
                Spacer(minLength: 4)
                Text("\(remaining) left")
                    .font(.system(size: 11))
                    .foregroundStyle(KeepTheme.mutedInk)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach($tasks) { $task in
                        HStack(spacing: 14) {
                            Toggle("", isOn: $task.isComplete)
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .accessibilityLabel("Complete \(task.title)")
                            Text(task.title)
                                .font(.system(size: 13))
                                .strikethrough(task.isComplete)
                                .foregroundStyle(task.isComplete ? KeepTheme.mutedInk : KeepTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                                .help(task.title)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 2)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) { rule }
                    }
                    if tasks.count < 4 {
                        ForEach(0..<(4 - tasks.count), id: \.self) { _ in
                            Color.clear.frame(height: 44).overlay(alignment: .bottom) { rule }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 13))
                    .foregroundStyle(KeepTheme.accentStrong)
                TextField("Add a little intention…", text: $newTask)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .focused($isAddingTask)
                    .onSubmit(addTask)
                    .accessibilityLabel("New task")
                Button(action: addTask) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(.system(size: 12))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderless)
                .disabled(newTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add task")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(KeepTheme.paper, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isAddingTask ? KeepTheme.focusRing : KeepTheme.border, lineWidth: isAddingTask ? 2 : 1)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(height: 288)
        .background(KeepTheme.surface, in: RoundedRectangle(cornerRadius: KeepTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: KeepTheme.cardRadius)
                .strokeBorder(KeepTheme.border, lineWidth: 1)
        }
        .foregroundStyle(KeepTheme.ink)
    }

    private var rule: some View {
        Rectangle().fill(KeepTheme.border).frame(height: 1)
    }

    private func addTask() {
        let title = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        tasks.append(FocusTask(title: title))
        newTask = ""
    }
}

#Preview {
    TasksCard(tasks: .constant(FocusTask.examples))
        .padding().frame(width: 450).background(KeepTheme.paper)
}
