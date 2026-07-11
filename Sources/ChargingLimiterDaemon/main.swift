import ChargingLimiterCore
import ChargingLimiterHardware
import Darwin
import Foundation
import OSLog

let logger = Logger(subsystem: ChargingLimiterIdentifiers.daemonBundle, category: "main")

guard getuid() == 0 else {
    logger.fault("ChargingLimiterDaemon must run as root")
    exit(EXIT_FAILURE)
}

#if !arch(arm64)
logger.fault("ChargingLimiterDaemon supports Apple Silicon only")
exit(EXIT_FAILURE)
#endif

do {
    let transport = try AppleSMCTransport()
    let hardware = try SMCHardwareController(transport: transport)
    let controller = try DaemonController(hardware: hardware)
    let service = DaemonXPCService(controller: controller)
    let delegate = DaemonListener(service: service)
    let listener = NSXPCListener(machServiceName: ChargingLimiterIdentifiers.daemonMachService)
    listener.delegate = delegate

    signal(SIGTERM, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termSource.setEventHandler {
        controller.shutdown()
        exit(EXIT_SUCCESS)
    }
    termSource.resume()
    let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interruptSource.setEventHandler {
        controller.shutdown()
        exit(EXIT_SUCCESS)
    }
    interruptSource.resume()

    controller.start()
    listener.resume()
    logger.notice("Charging limiter daemon started")
    RunLoop.main.run()
} catch {
    logger.fault("Daemon startup failed: \(error.localizedDescription, privacy: .public)")
    exit(EXIT_FAILURE)
}
