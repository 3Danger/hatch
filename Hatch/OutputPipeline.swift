import Foundation

/// Конвейер по сохранённому выводу: шаги (`grep`, `sort`, `jq`…) получают на вход уже
/// сохранённый вывод команды, а сама команда не перезапускается — безопасно и мгновенно
/// даже для `rm`, `curl -X POST`, деплоя. Шаги идут в шелле пользователя (алиасы из rc).
enum OutputPipeline {
    struct Result: Equatable {
        var output: String
        var status: Int32
    }

    /// Дольше шаги не работают: зависший шаг не держит блок.
    static let timeout: TimeInterval = 15

    static func run(stages: [String], input: String, directory: String,
                    shell: String, environment: [String: String]) async -> Result {
        guard !stages.isEmpty else { return Result(output: input, status: 0) }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(stages: stages, input: input, directory: directory,
                                                           shell: shell, environment: environment))
            }
        }
    }

    private static func runBlocking(stages: [String], input: String, directory: String,
                                    shell: String, environment: [String: String]) -> Result {
        // шаг вроде `head -1` закрывает вход раньше, чем мы дописали вывод: без этого — SIGPIPE и падение
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", ProcessRunner.script(shell: shell)]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        var env = environment
        env["PWD"] = directory
        env[ProcessRunner.commandVariable] = stages.joined(separator: " | ")
        env["DISABLE_AUTO_UPDATE"] = "true"
        env["PAGER"] = "cat"
        process.environment = env

        let inputPipe = Pipe()
        let output = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = output
        process.standardError = output // ошибки шагов видны в выводе

        do {
            try process.run()
        } catch {
            return Result(output: "Ошибка запуска: \(error)", status: -1)
        }

        let text = input
        DispatchQueue.global(qos: .userInitiated).async {
            let handle = inputPipe.fileHandleForWriting
            if !text.isEmpty {
                // последняя строка с переводом строки — иначе sort/wc видят её не так
                try? handle.write(contentsOf: Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
            }
            try? handle.close()
        }
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            if process.isRunning { kill(pid, SIGKILL) }
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let result = String(decoding: data, as: UTF8.self)
        return Result(output: result.trimmingCharacters(in: .newlines), status: process.terminationStatus)
    }
}
