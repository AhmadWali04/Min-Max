import Foundation
import MinMaxCore

@main
struct MinMaxEchoServer {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--help") {
            print("MinMaxEchoServer \(MinMaxCore.version)")
            print("Placeholder echo server; UDP behavior is not implemented yet.")
            return
        }

        print("MinMaxEchoServer \(MinMaxCore.version) is ready.")
    }
}
