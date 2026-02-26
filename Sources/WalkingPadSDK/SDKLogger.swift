import os

enum SDKLogger {
    static func make(category: String) -> Logger {
        #if DEBUG
        Logger(subsystem: "com.makemefit.walkingpadsdk", category: category)
        #else
        Logger(.disabled)
        #endif
    }
}
