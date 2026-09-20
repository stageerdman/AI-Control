import SwiftUI
import AIControlCore

/// The New Project form (PROJECT.md §9.2), presented as a sheet from the
/// dashboard. Collects name / location / visibility / INIT description, validates
/// with the core `NewProjectValidator`, and on submit hands a target folder URL
/// back to the dashboard, which creates the empty dir + opens the AI session.
/// The app authors nothing here — the AI builds the project (principle 2).
struct NewProjectSheet: View {
    let rootURL: URL
    let organizers: [AIControlNode]
    let globalConfig: GlobalConfig
    let onSetUpConfig: () -> Void
    /// (targetDir, name, visibility, description). The dashboard does the create.
    let onCreate: (URL, String, String, String) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var locationURL: URL
    @State private var visibility = "private"
    @State private var descriptionText = ""

    init(
        rootURL: URL,
        organizers: [AIControlNode],
        globalConfig: GlobalConfig,
        onSetUpConfig: @escaping () -> Void,
        onCreate: @escaping (URL, String, String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.rootURL = rootURL
        self.organizers = organizers
        self.globalConfig = globalConfig
        self.onSetUpConfig = onSetUpConfig
        self.onCreate = onCreate
        self.onCancel = onCancel
        _locationURL = State(initialValue: rootURL)
    }

    private var folderName: String { NewProjectValidator.folderName(for: name) }
    private var targetDir: URL { locationURL.appendingPathComponent(folderName) }

    /// Names already present at the chosen location (fresh disk read, so a folder
    /// created outside the app is still caught).
    private var siblingNames: Set<String> {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: locationURL.path)) ?? []
        return Set(entries)
    }

    private var problems: [NewProjectValidator.Problem] {
        NewProjectValidator.validate(name: name, description: descriptionText, existingSiblingNames: siblingNames)
    }
    private var isValid: Bool { problems.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Project").font(.title2.weight(.semibold))
                Text("The AI sets it up under AI Control and makes the first commit.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(20)
            Divider()

            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("my-project"))
                        .font(.body.monospaced())
                    if !folderName.isEmpty, let msg = nameProblemMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary)
                    }

                    Picker("Location", selection: $locationURL) {
                        Text("\(rootURL.lastPathComponent) (root)").tag(rootURL)
                        ForEach(organizers, id: \.url) { org in
                            Text(org.name).tag(org.url)
                        }
                    }

                    Picker("Visibility", selection: $visibility) {
                        Text("Private").tag("private")
                        Text("Public").tag("public")
                    }
                    .pickerStyle(.segmented)
                    Text(visibility == "private" ? "Creates a Private GitHub repo." : "Creates a Public GitHub repo.")
                        .font(.caption).foregroundStyle(.tertiary)
                }

                Section {
                    Text("What do you want to build?").font(.callout.weight(.medium))
                    Text("Describe the project in detail — this becomes the INIT update and guides the whole setup.")
                        .font(.caption).foregroundStyle(.tertiary)
                    TextEditor(text: $descriptionText)
                        .font(.body)
                        .frame(minHeight: 120)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.25)))
                }
            }
            .formStyle(.grouped)

            if configWarning != nil {
                Divider()
                HStack(spacing: 10) {
                    Text(configWarning!).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Set up…", action: onSetUpConfig).controlSize(.small)
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }

            Divider()
            HStack {
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Project") { onCreate(targetDir, folderName, visibility, descriptionText) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(minWidth: 460, idealWidth: 520)
        .onChange(of: locationURL) { _, _ in } // triggers sibling re-read via recomputed problems
    }

    private var nameProblemMessage: String? {
        if problems.contains(.invalidName) { return "Use a folder-safe name (no slashes, not starting with a dot)." }
        if problems.contains(.nameTaken) { return "A folder named \"\(folderName)\" already exists here." }
        return nil
    }

    private var configWarning: String? {
        if !globalConfig.exists {
            return "Global config isn't set up. Projects normally inherit coding principles, workflow rules and secrets from ~/.ai-control/."
        }
        if globalConfig.modules.isEmpty {
            return "No global modules authored yet — the AI will create a minimal CLAUDE.md it can improve later."
        }
        return nil
    }
}
