import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let controller = AppController()
application.delegate = controller
application.run()
