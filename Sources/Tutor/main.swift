import SwiftUI

// Dev commands run async work off the main thread and exit. Don't use top-level `await` here:
// it changes how the app's main-actor work is scheduled and the UI stops receiving search results.
if CLI.isCommand(CommandLine.arguments) {
    Task {
        await CLI.run(CommandLine.arguments)
        exit(0)
    }
    dispatchMain()
}
TutorApp.main()
