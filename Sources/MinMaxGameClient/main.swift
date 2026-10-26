import Foundation
import MinMaxCore

@main
struct MinMaxGameClient {
    static func main() {
        if CommandLine.arguments.dropFirst().contains("--help") {
            print("MinMaxGameClient \(MinMaxCore.version)")
            print("Placeholder game client; network probing is not implemented yet.")
            return
        }

        print("MinMaxGameClient \(MinMaxCore.version) is ready.")
    }
}
