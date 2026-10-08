import SwiftUI
import GroveCore

/// Guidance only. Login, passwords and two-factor authentication stay in the user's Terminal.
struct GitHubSetupView: View {
    let store: Store
    private var installed: Bool {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].contains {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "link").font(.system(size: 28)).foregroundStyle(Color.groveInk)
            Text("Connect Your GitHub Account").font(.system(size: 20, weight: .semibold))
            Text("Grove uses your own GitHub CLI sign-in. It comes with no account, repositories or credentials preloaded.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !installed {
                step("1. Install GitHub CLI", command: "brew install gh")
                Link("Need Homebrew?", destination: URL(string: "https://brew.sh")!).font(.system(size: 12))
            }
            step(installed ? "Sign In From Terminal" : "2. Sign In From Terminal", command: "gh auth login --hostname github.com")
            Text("Complete GitHub’s sign-in in Terminal, then return here. Grove never asks you to paste a token.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Connect GitHub") { store.requestRefresh() }
                    .buttonStyle(.borderedProminent).disabled(store.busy || !store.canStartReview)
                Link("Setup Guide", destination: URL(string: "https://cli.github.com/manual/gh_auth_login")!)
            }.controlSize(.regular)
        }.padding(28).frame(maxWidth: 520, alignment: .leading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func step(_ title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            HStack {
                Text(command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                Spacer(minLength: 8)
                Button("Copy") { Clipboard.copy(command) }.controlSize(.small).help("Copy \(command)")
            }.padding(10).background(Color.panel, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
