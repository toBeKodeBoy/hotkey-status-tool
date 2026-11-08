import AppKit

func checkEventTap(store: StatsStore) {
    var callback: CGEventTapCallBack?
    var context: UnsafeMutableRawPointer?
    let port = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, nil, nil)!
    defer { CFMachPortInvalidate(port) }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)!
    var valid = true
    var failCreate = false
    var failSource = false
    var enableCalls = 0
    var services = EventTapMonitor.Services()
    services.create = { _, _, options, _, handler, refcon in
        precondition(options == .listenOnly)
        callback = handler
        context = refcon
        return failCreate ? nil : port
    }
    services.isValid = { _ in valid }
    services.enable = { _, _ in enableCalls += 1 }
    services.makeSource = { _, _, _ in failSource ? nil : source }
    services.addSource = { _, _, _ in }
    services.removeSource = { _, _, _ in }
    services.invalidate = { _ in }
    let monitor = EventTapMonitor(store: store, services: services)
    precondition(monitor.start())
    precondition(monitor.start(), "already valid")
    valid = false
    precondition(monitor.start(), "invalid tap recreated")
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 17, keyDown: true)!
    event.flags = .maskCommand
    _ = callback?(OpaquePointer(bitPattern: 1)!, .keyDown, event, context)
    _ = callback?(OpaquePointer(bitPattern: 1)!, .keyUp, event, context)
    _ = callback?(OpaquePointer(bitPattern: 1)!, .tapDisabledByTimeout, event, context)
    _ = callback?(OpaquePointer(bitPattern: 1)!, .tapDisabledByUserInput, event, context)
    precondition(enableCalls > 0)
    monitor.stop()
    _ = callback?(OpaquePointer(bitPattern: 1)!, .keyDown, event, context)
    monitor.stop()
    failCreate = true
    precondition(!monitor.start(), "creation failure")
    failCreate = false
    failSource = true
    precondition(!monitor.start(), "source failure")
}
