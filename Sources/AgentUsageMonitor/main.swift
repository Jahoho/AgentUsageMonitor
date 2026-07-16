import AppKit

private var retainedDelegate: AppDelegate?

let application = NSApplication.shared
let delegate = AppDelegate()
retainedDelegate = delegate

application.delegate = delegate
application.setActivationPolicy(.accessory)
ApplicationMenu.install(on: application)
application.run()
