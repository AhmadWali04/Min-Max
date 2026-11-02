import Darwin
import Foundation
import MinMaxUDP

do {
    try WorkloadCLI.runProbe(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("MinMaxGameClient: \(error)\n".utf8))
    exit(1)
}
