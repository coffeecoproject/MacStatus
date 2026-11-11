import Darwin
import Foundation
import Testing
@testable import MacSystemMetrics

struct AgentTaskFinderTests {
    /// In its own process group unless given one, as Claude Code starts each command.
    private func process(_ pid: pid_t, parent: pid_t, _ name: String, group: pid_t? = nil) -> ProcessEntry {
        ProcessEntry(
            pid: pid, parent: parent, name: name, startedAt: Date(timeIntervalSince1970: Double(pid)), group: group ?? pid
        )
    }

    @Test func shellsAnAgentStartedAreTasksButItsServersAreNot() {
        let processes = [
            process(10, parent: 1, "claude"),
            process(11, parent: 10, "zsh"),
            process(12, parent: 11, "node"),
            // An MCP server, started directly.
            process(13, parent: 10, "node"),
            process(20, parent: 1, "codex"),
            process(21, parent: 20, "sandbox-exec"),
            process(22, parent: 20, "codex-code-mode-host"),
            // The user's own terminal is no agent's.
            process(30, parent: 1, "Terminal"),
            process(31, parent: 30, "zsh")
        ]
        let roots = AgentTaskFinder.roots(in: processes, responsible: { _ in nil }, isService: { _ in false })
        #expect(roots == [
            .init(pid: 11, agent: "Claude Code", detached: false),
            .init(pid: 21, agent: "Codex", detached: false)
        ])
    }

    @Test func processesLeftRunningCountTowardTheAgentResponsibleForThem() {
        let processes = [
            process(10, parent: 1, "claude"),
            // Its shell exited; launchd adopted it.
            process(40, parent: 1, "node"),
            process(41, parent: 40, "node"),
            // Adopted too, but started by an app, not an agent.
            process(50, parent: 1, "Safari"),
            // An agent is responsible for itself.
            process(60, parent: 1, "codex"),
            // Started by launchd for a browser the command runs, so the agent is responsible for it too.
            process(70, parent: 1, "SetStoreUpdateService")
        ]
        let owners: [pid_t: pid_t] = [40: 10, 41: 10, 50: 50, 60: 60, 70: 10]
        let roots = AgentTaskFinder.roots(in: processes, responsible: { owners[$0] }, isService: { $0 == 70 })
        #expect(roots == [.init(pid: 40, agent: "Claude Code", detached: true)])
    }

    @Test func aTaskIncludesEveryProcessUnderIt() {
        let processes = [
            process(11, parent: 10, "zsh"),
            process(12, parent: 11, "node"),
            process(13, parent: 12, "postgres"),
            process(14, parent: 10, "zsh")
        ]
        #expect(Set(AgentTaskFinder.tree(of: [11], in: processes)) == [11, 12, 13])
    }

    @Test func whatIsLeftOfOneCommandLineIsOneTask() {
        let processes = [
            process(10, parent: 1, "claude"),
            // Both sides of `devtools build | tail -3`, adopted when their shell (90) exited.
            process(91, parent: 1, "Electron", group: 90),
            process(92, parent: 1, "tail", group: 90),
            // Another command's leftover.
            process(95, parent: 1, "napboxd", group: 94),
            // A live shell, and a process that left it but stayed in its group.
            process(100, parent: 10, "zsh"),
            process(102, parent: 1, "node", group: 100)
        ]
        let roots = AgentTaskFinder.roots(in: processes, responsible: { $0 == 10 ? nil : 10 }, isService: { _ in false })
        #expect(AgentTaskFinder.groups(of: roots, in: processes) == [
            .init(leader: 91, roots: [91, 92], agent: "Claude Code", detached: true),
            .init(leader: 95, roots: [95], agent: "Claude Code", detached: true),
            .init(leader: 100, roots: [100, 102], agent: "Claude Code", detached: false)
        ])
    }

    /// The Codex app's server shares its group with the app, so what is left in that group is unrelated.
    @Test func anAgentsOwnGroupJoinsNothing() {
        let processes = [
            process(10, parent: 5, "codex", group: 5),
            process(11, parent: 10, "zsh", group: 5),
            process(12, parent: 10, "zsh", group: 5),
            process(13, parent: 1, "node", group: 5)
        ]
        let roots = AgentTaskFinder.roots(in: processes, responsible: { $0 == 13 ? 10 : nil }, isService: { _ in false })
        #expect(AgentTaskFinder.groups(of: roots, in: processes).map(\.roots) == [[11], [12], [13]])
    }

    /// As Claude Code runs a command: a quote in it is written '"'"'.
    @Test func claudeCodesShellSetupIsUnwrapped() {
        let script = """
        source /Users/me/.claude/shell-snapshots/snapshot-zsh-1.sh 2>/dev/null || true && { \\builtin unalias -- 'which'; } \
        >/dev/null 2>&1 || true && eval 'npm run dev -- --name '"'"'my app'"'"' \\
        && echo "done"' < /dev/null && pwd -P >| /tmp/claude-a54e-cwd
        """
        #expect(AgentTaskFinder.command(arguments: ["/bin/zsh", "-c", script]) == .script("""
        npm run dev -- --name 'my app' \\
        && echo "done"
        """))
    }

    @Test func commandsComeFromTheShellsScriptOrTheArguments() {
        #expect(AgentTaskFinder.command(arguments: ["/bin/zsh", "-lc", "pnpm test"]) == .script("pnpm test"))
        #expect(AgentTaskFinder.command(arguments: [
            "/usr/bin/sandbox-exec", "-p", "(version 1)", "-D", "WRITABLE_ROOT_0=/tmp", "--", "/bin/bash", "-lc", "cargo build"
        ]) == .script("cargo build"))
        // Without -c the shell runs a script file, which is what its arguments say.
        #expect(AgentTaskFinder.command(arguments: ["/bin/sh", "build.sh"]) == .arguments(["/bin/sh", "build.sh"]))
    }

    @Test func programsRunDirectlyAreNamedByTheirFile() {
        let daemon = AgentTaskFinder.Command.arguments(["/Users/me/napbox/.build/Release/napboxd", "--port", "8080"])
        #expect(daemon.headline == "napboxd --port 8080")
        #expect(daemon.text == "/Users/me/napbox/.build/Release/napboxd --port 8080")
        #expect(AgentTaskFinder.Command.arguments(["Electron", "-e", "run()\nexit()"]).headline == "Electron -e run()")
    }

    @Test(arguments: [
        ("cd /Users/me/Pawcode/services/api && pnpm test", "pnpm test"),
        ("export PATH=~/.nvm/bin:$PATH && S=/tmp/x; OUT=$S/out\nnpm run start > $OUT/log 2>&1", "npm run start > $OUT/log 2>&1"),
        ("NODE_ENV=test /Users/me/.nvm/bin/node scripts/run.mjs", "node scripts/run.mjs"),
        ("# wait for the build\nuntil grep -q done log; do sleep 5; done", "until grep -q done log"),
        ("cd 'my dir; here' && make", "make"),
        ("echo 'a && b' | tail -3", "echo 'a && b' | tail -3"),
        ("swift build \\\n  --configuration release", "swift build --configuration release"),
        ("cd /tmp", "cd /tmp")
    ])
    func headlinesSkipSetup(script: String, headline: String) {
        #expect(AgentTaskFinder.Command.script(script).headline == headline)
    }

    @Test func shellWordsJoinQuotedPartsAndEscapes() {
        #expect(AgentTaskFinder.shellWord("'a b'\"c\\\"d\"\\ e rest") == "a bc\"d e")
        #expect(AgentTaskFinder.shellWord("\"\\n\"") == "\\n")
    }

    @Test func projectsAreRepositoriesWithWorktreesCountingAsTheirMain() {
        let entries: [String: AgentTaskFinder.GitEntry] = [
            "/Users/me/Developer/Pawcode/.git": .directory,
            "/Users/me/Developer/Pawcode/.claude/worktrees/fix/.git": .file("gitdir: /Users/me/Developer/Pawcode/.git/worktrees/fix\n"),
            "/Users/me/Developer/app/vendor/lib/.git": .file("gitdir: ../../.git/modules/lib\n"),
            "/Users/me/.git": .directory
        ]
        func project(_ directory: String) -> String? {
            AgentTaskFinder.project(of: directory, home: "/Users/me", gitEntry: { entries[$0] })
        }
        #expect(project("/Users/me/Developer/Pawcode/services/api") == "Pawcode")
        #expect(project("/Users/me/Developer/Pawcode/.claude/worktrees/fix/services/api") == "Pawcode")
        #expect(project("/Users/me/Developer/app/vendor/lib/src") == "lib")
        // Outside any repository but the home directory's.
        #expect(project("/Users/me/Developer/scratch/out") == "out")
        #expect(project("/tmp") == "tmp")
        #expect(project("/") == nil)
    }

    @Test func procArgsAreSplitIntoArguments() {
        var buffer = withUnsafeBytes(of: Int32(3)) { Array($0) }
        buffer += Array("/bin/zsh".utf8) + [0, 0, 0]
        buffer += Array("/bin/zsh\u{0}-c\u{0}echo hi\u{0}PATH=/usr/bin\u{0}".utf8)
        #expect(AgentTaskFinder.arguments(fromProcArgs: buffer) == ["/bin/zsh", "-c", "echo hi"])
        #expect(AgentTaskFinder.arguments(fromProcArgs: Array(buffer.prefix(12))) == nil)
    }

    /// Reads this test process's own arguments, to notice the kernel's layout changing.
    @Test func readsTheArgumentsOfARunningProcess() throws {
        let arguments = try #require(AgentTaskReader.arguments(of: getpid()))
        #expect(arguments == CommandLine.arguments)
    }
}
