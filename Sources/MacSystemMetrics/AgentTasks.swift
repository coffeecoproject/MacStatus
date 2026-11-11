import Darwin
import Foundation

/// A command a coding agent (Claude Code, Codex) is running for one of its sessions, with what it started.
public struct AgentTask: Sendable, Equatable, Identifiable {
    public let pid: pid_t
    public let startedAt: Date
    /// The agent's name, as people know it.
    public let agent: String
    /// The command as the agent wrote it; may span lines.
    public let command: String
    /// One line saying what runs: the first command past setup such as `cd` and `export`, programs by name.
    public let headline: String
    /// The repository the command runs in, or its directory's name outside one; nil when unreadable.
    public let project: String?
    /// The shell that ran it has exited, so the session no longer follows it, though it still runs.
    /// What was left of one command, such as both sides of a pipe, makes one task.
    public let detached: Bool
    /// Physical footprint of the command and every process under it.
    public let footprint: UInt64

    /// A pid alone may be reused once the process exits.
    public var id: String { "\(pid)@\(startedAt.timeIntervalSince1970)" }
}

/// One of the current user's processes, as far as finding tasks needs.
struct ProcessEntry: Sendable, Equatable {
    let pid: pid_t
    let parent: pid_t
    /// The executable's name, as the kernel keeps it (at most 16 characters).
    let name: String
    let startedAt: Date
    /// Process group: the processes of one command line share it, and keep it when their shell exits.
    let group: pid_t
}

enum AgentTaskFinder {
    /// Executable names of the agents' session processes.
    static let agents = ["claude": "Claude Code", "codex": "Codex"]
    /// What agents run commands with; anything else they start directly (MCP servers, helpers) is not a task.
    static let shells: Set<String> = ["zsh", "bash", "sh", "sandbox-exec"]

    struct Root: Equatable {
        let pid: pid_t
        let agent: String
        let detached: Bool
    }

    /// Shells an agent started, and processes left running after theirs exited: those are adopted by launchd,
    /// but the system still holds the agent responsible for them. So it does for the XPC services launchd
    /// starts on behalf of a command's processes (a browser's, say), which were never the command's own.
    static func roots(
        in processes: [ProcessEntry], responsible: (pid_t) -> pid_t?, isService: (pid_t) -> Bool
    ) -> [Root] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        func agent(_ pid: pid_t?) -> String? {
            pid.flatMap { byPID[$0] }.flatMap { agents[$0.name] }
        }
        return processes.compactMap { process in
            if shells.contains(process.name), let name = agent(process.parent) {
                return Root(pid: process.pid, agent: name, detached: false)
            }
            guard process.parent == 1, agents[process.name] == nil,
                  let owner = responsible(process.pid), owner != process.pid, let name = agent(owner),
                  !isService(process.pid) else { return nil }
            return Root(pid: process.pid, agent: name, detached: true)
        }
    }

    /// The roots of one task: a shell, or what is left of one, with the processes of its command line it lost.
    struct Group: Equatable {
        /// Identifies the task: its shell, or else the first process left of it.
        let leader: pid_t
        /// In pid order, which for a command line is roughly left to right.
        let roots: [pid_t]
        let agent: String
        let detached: Bool
    }

    /// Roots sharing a process group are one command line: a pipe whose shell exited leaves each side adopted
    /// on its own, and a shell's group can hold a process that left it. Claude Code gives each command its own
    /// group; a group an agent is in holds unrelated processes and joins nothing.
    static func groups(of roots: [Root], in processes: [ProcessEntry]) -> [Group] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let agentGroups = Set(processes.filter { agents[$0.name] != nil }.map(\.group))
        var order: [pid_t] = []
        var members: [pid_t: [Root]] = [:]
        for root in roots {
            guard let process = byPID[root.pid] else { continue }
            // A shell only stands for the group it leads.
            let joins = !agentGroups.contains(process.group) && (root.detached || process.group == process.pid)
            // Keyed apart from any group by a pid that cannot be one (groups are positive).
            let key = joins ? process.group : -root.pid
            if members[key] == nil { order.append(key) }
            members[key, default: []].append(root)
        }
        return order.compactMap { key in
            guard let roots = members[key]?.sorted(by: { $0.pid < $1.pid }), let first = roots.first else { return nil }
            let leader = roots.first { !$0.detached } ?? first
            return Group(leader: leader.pid, roots: roots.map(\.pid), agent: leader.agent, detached: leader.detached)
        }
    }

    /// The roots and every process under them.
    static func tree(of roots: [pid_t], in processes: [ProcessEntry]) -> [pid_t] {
        let children = Dictionary(grouping: processes, by: \.parent)
        var members: [pid_t] = []
        var pending = roots
        // The listing is not atomic, so a reused pid could close a loop; each process is taken once.
        var seen: Set<pid_t> = []
        while let pid = pending.popLast() {
            guard seen.insert(pid).inserted else { continue }
            members.append(pid)
            pending += children[pid, default: []].map(\.pid)
        }
        return members
    }

    /// The command a task runs, from its arguments: what a shell was given with `-c`, unwrapped from the
    /// sandbox Codex may run it in and from Claude Code's shell setup; otherwise the arguments themselves.
    static func command(arguments: [String]) -> Command {
        guard let program = arguments.first.map({ ($0 as NSString).lastPathComponent }) else { return .arguments([]) }
        if program == "sandbox-exec", let separator = arguments.firstIndex(of: "--") {
            return command(arguments: Array(arguments[(separator + 1)...]))
        }
        if shells.contains(program),
           let flag = arguments.dropFirst().firstIndex(where: isCommandFlag), flag + 1 < arguments.count {
            let script = arguments[flag + 1]
            return .script(claudeCommand(in: script) ?? script)
        }
        return .arguments(arguments)
    }

    enum Command: Equatable {
        /// What a shell runs.
        case script(String)
        /// A program run directly, or what is left of a command line.
        case arguments([String])

        var text: String {
            switch self {
            case .script(let script): script
            case .arguments(let arguments): arguments.joined(separator: " ")
            }
        }

        var headline: String {
            switch self {
            case .script(let script):
                return AgentTaskFinder.headline(ofScript: script)
            case .arguments(let arguments):
                guard let program = arguments.first else { return "" }
                let line = ([(program as NSString).lastPathComponent] + arguments.dropFirst()).joined(separator: " ")
                return String(line.prefix { !$0.isNewline })
            }
        }
    }

    /// The first command of a script that does more than set up: `cd`, `export`, assignments and comments are
    /// passed over, and a program given by path is named by its file. The whole script when it only sets up.
    static func headline(ofScript script: String) -> String {
        let commands = simpleCommands(in: script)
        for var words in commands {
            words = Array(words.drop(while: isAssignment))
            guard let first = words.first, !first.hasPrefix("#") else { continue }
            let program = shellWord(first[...])
            if program == "cd" || program == "export" { continue }
            if program.contains("/"), !program.hasSuffix("/") {
                words[0] = (program as NSString).lastPathComponent
            }
            return words.joined(separator: " ")
        }
        return commands.first.map { $0.joined(separator: " ") } ?? ""
    }

    /// `NAME=value`, as written before a command or alone.
    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), let first = word.first, first == "_" || first.isLetter else { return false }
        return word[..<equals].allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    /// The simple commands of a script as their words, quotes kept: split at unquoted newlines, `;`, `&&` and
    /// `||`, as the shell runs them one after another. A pipe stays within its command.
    static func simpleCommands(in script: String) -> [[String]] {
        var commands: [[String]] = []
        var words: [String] = []
        var word = ""
        var quote: Character?
        let characters = Array(script)
        var index = 0
        func endWord() {
            if !word.isEmpty { words.append(word) }
            word = ""
        }
        func endCommand() {
            endWord()
            if !words.isEmpty { commands.append(words) }
            words = []
        }
        while index < characters.count {
            let character = characters[index]
            let following = index + 1 < characters.count ? characters[index + 1] : nil
            index += 1
            if let open = quote {
                word.append(character)
                if character == "\\", open == "\"", let following {
                    word.append(following)
                    index += 1
                } else if character == open {
                    quote = nil
                }
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
                word.append(character)
            case "\\":
                // An escaped line break continues the line.
                if following == "\n" {
                    endWord()
                } else if let following {
                    word.append(character)
                    word.append(following)
                }
                index += 1
            case " ", "\t":
                endWord()
            case "\n", ";":
                endCommand()
            case "&" where following == "&", "|" where following == "|":
                index += 1
                endCommand()
            default:
                word.append(character)
            }
        }
        endCommand()
        return commands
    }

    /// `-c`, or flags combined with it such as `-lc`.
    private static func isCommandFlag(_ argument: String) -> Bool {
        argument.count > 1 && argument.hasPrefix("-") && !argument.hasPrefix("--")
            && argument.dropFirst().allSatisfy(\.isLetter) && argument.contains("c")
    }

    /// Claude Code sources a snapshot of the user's shell and then `eval`s the command as one quoted word.
    static func claudeCommand(in script: String) -> String? {
        guard script.hasPrefix("source "), script.contains("/shell-snapshots/"),
              let eval = script.range(of: " eval ") else { return nil }
        return shellWord(script[eval.upperBound...])
    }

    /// The first word of `text` as the shell reads it: quoted parts and escapes joined, up to unquoted space.
    static func shellWord(_ text: Substring) -> String {
        var word = ""
        var index = text.startIndex
        func next() -> Character? {
            guard index < text.endIndex else { return nil }
            defer { index = text.index(after: index) }
            return text[index]
        }
        while let character = next() {
            switch character {
            case "'":
                while let quoted = next(), quoted != "'" { word.append(quoted) }
            case "\"":
                while let quoted = next(), quoted != "\"" {
                    // Inside double quotes a backslash escapes only these.
                    if quoted == "\\", index < text.endIndex, "\"\\$`".contains(text[index]) {
                        word.append(next()!)
                    } else {
                        word.append(quoted)
                    }
                }
            case "\\":
                if let escaped = next() { word.append(escaped) }
            case " ", "\t", "\n":
                return word
            default:
                word.append(character)
            }
        }
        return word
    }

    /// The repository `directory` is in, a linked worktree counting as its main repository, or else the
    /// directory's own name. The home directory is no project, even when it is a repository itself, and the
    /// root directory, where daemons go, names none.
    static func project(of directory: String, home: String, gitEntry: (String) -> GitEntry?) -> String? {
        guard directory != "/" else { return nil }
        var current = directory
        while current != "/", current != home, current.hasPrefix("/") {
            switch gitEntry(current + "/.git") {
            case .directory:
                return (current as NSString).lastPathComponent
            case .file(let contents):
                // A linked worktree's `.git` file points into its main repository's `.git/worktrees`.
                if let gitDir = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir: ") })?.dropFirst(8),
                   let worktrees = gitDir.range(of: "/.git/worktrees/") {
                    return (String(gitDir[..<worktrees.lowerBound]) as NSString).lastPathComponent
                }
                return (current as NSString).lastPathComponent
            case nil:
                current = (current as NSString).deletingLastPathComponent
            }
        }
        return (directory as NSString).lastPathComponent
    }

    enum GitEntry: Equatable {
        case directory
        case file(String)
    }

    /// Splits `KERN_PROCARGS2` output: the argument count, the executable path, then the arguments,
    /// each ending in a NUL (the path padded with more), followed by the environment, which is left out.
    static func arguments(fromProcArgs buffer: [UInt8]) -> [String]? {
        let countSize = MemoryLayout<Int32>.size
        guard buffer.count > countSize else { return nil }
        let count = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = countSize
        // The executable path, then its padding.
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < count, index < buffer.count {
            let end = buffer[index...].firstIndex(of: 0) ?? buffer.count
            arguments.append(String(decoding: buffer[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments.count == count ? arguments : nil
    }
}

/// Reads the current user's agent tasks; other users' processes are not looked at.
public final class AgentTaskReader {
    /// Projects by working directory; finding one reads the file system.
    private var projects: [String: String?] = [:]

    public init() {}

    /// Oldest first, so what was left running the longest leads.
    public func read() throws(MetricError) -> [AgentTask] {
        let processes = try Self.processes()
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return Self.groups(in: processes).compactMap { group -> AgentTask? in
            guard let leader = byPID[group.leader] else { return nil }
            // A shell's command already covers what left its group; what is left of one is each side in turn.
            let commands = group.detached
                ? group.roots.map { pid in Self.arguments(of: pid).map(AgentTaskFinder.command(arguments:)) ?? .arguments([byPID[pid]?.name ?? ""]) }
                : [Self.arguments(of: group.leader).map(AgentTaskFinder.command(arguments:)) ?? .arguments([leader.name])]
            return AgentTask(
                pid: group.leader,
                startedAt: leader.startedAt,
                agent: group.agent,
                command: commands.map(\.text).joined(separator: " | "),
                headline: commands.map(\.headline).joined(separator: " | "),
                project: Self.workingDirectory(of: group.leader).flatMap(project(of:)),
                detached: group.detached,
                footprint: AgentTaskFinder.tree(of: group.roots, in: processes)
                    .compactMap(ProcessList.footprint(pid:)).reduce(0, +)
            )
        }
        .sorted { $0.startedAt != $1.startedAt ? $0.startedAt < $1.startedAt : $0.pid < $1.pid }
    }

    /// Asks the task and every process under it to end (SIGTERM), as they are now: what started under it since
    /// it was read is included, and a pid since reused by another process is not.
    public static func terminate(_ task: AgentTask) {
        guard let processes = try? processes(),
              processes.contains(where: { $0.pid == task.pid && $0.startedAt == task.startedAt }),
              let group = groups(in: processes).first(where: { $0.leader == task.pid }) else { return }
        // Children first, so a shell does not react to one exiting by starting something else.
        for pid in AgentTaskFinder.tree(of: group.roots, in: processes).reversed() {
            kill(pid, SIGTERM)
        }
    }

    private static func groups(in processes: [ProcessEntry]) -> [AgentTaskFinder.Group] {
        let roots = AgentTaskFinder.roots(in: processes, responsible: responsible(for:), isService: isService(_:))
        return AgentTaskFinder.groups(of: roots, in: processes)
    }

    /// Run from an XPC service bundle.
    private static func isService(_ pid: pid_t) -> Bool {
        var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 && String(decoding: buffer.prefix(Int(length)), as: UTF8.self).contains(".xpc/")
    }

    private func project(of directory: String) -> String? {
        if let cached = projects[directory] { return cached }
        let project = AgentTaskFinder.project(
            of: directory, home: NSHomeDirectory(), gitEntry: Self.gitEntry(at:)
        )
        projects[directory] = project
        return project
    }

    private static func gitEntry(at path: String) -> AgentTaskFinder.GitEntry? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return .directory }
        return .file((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
    }

    private static func processes() throws(MetricError) -> [ProcessEntry] {
        let user = getuid()
        return try ProcessList.pids().compactMap { pid in
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size, info.pbi_uid == user else { return nil }
            let name = withUnsafeBytes(of: info.pbi_comm) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return ProcessEntry(
                pid: pid,
                parent: pid_t(info.pbi_ppid),
                name: name,
                startedAt: Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000),
                group: pid_t(info.pbi_pgid)
            )
        }
    }

    private static func responsible(for pid: pid_t) -> pid_t? {
        (Responsibility.responsiblePID?(pid)).flatMap { $0 > 0 ? $0 : nil }
    }

    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return AgentTaskFinder.arguments(fromProcArgs: Array(buffer.prefix(size)))
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }
}
