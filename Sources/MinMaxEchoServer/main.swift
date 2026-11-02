import Darwin
import Foundation
import MinMaxUDP

do {
    try WorkloadCLI.runEcho(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("MinMaxEchoServer: \(error)\n".utf8))
    exit(1)
}
