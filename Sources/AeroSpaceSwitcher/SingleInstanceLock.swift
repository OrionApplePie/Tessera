import Darwin
import Foundation

final class SingleInstanceLock {
    static let defaultLockURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/aerospace-switcher/aerospace-switcher.lock")

    private let lockURL: URL
    private let logger: AppLogger
    private var fileDescriptor: Int32 = -1

    init(lockURL: URL = SingleInstanceLock.defaultLockURL, debugMode: Bool = false) {
        self.lockURL = lockURL
        self.logger = AppLogger(debugMode: debugMode, category: .app)
    }

    deinit {
        release()
    }

    func tryAcquire() throws -> Bool {
        guard fileDescriptor == -1 else {
            return true
        }

        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw SingleInstanceLockError.openFailed(path: lockURL.path, errnoCode: errno)
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let errnoCode = errno
            close(descriptor)

            if errnoCode == EWOULDBLOCK || errnoCode == EAGAIN {
                return false
            }

            throw SingleInstanceLockError.lockFailed(path: lockURL.path, errnoCode: errnoCode)
        }

        fileDescriptor = descriptor
        writeCurrentPID()
        logger.info("Acquired single-instance lock path=\(lockURL.path)")
        return true
    }

    func release() {
        guard fileDescriptor >= 0 else {
            return
        }

        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        fileDescriptor = -1
        logger.info("Released single-instance lock path=\(lockURL.path)")
    }

    private func writeCurrentPID() {
        let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
        ftruncate(fileDescriptor, 0)
        lseek(fileDescriptor, 0, SEEK_SET)
        pid.withCString { pointer in
            _ = write(fileDescriptor, pointer, strlen(pointer))
        }
    }
}

enum SingleInstanceLockError: Error, CustomStringConvertible {
    case openFailed(path: String, errnoCode: Int32)
    case lockFailed(path: String, errnoCode: Int32)

    var description: String {
        switch self {
        case .openFailed(let path, let errnoCode):
            return "Failed to open single-instance lock at \(path): errno \(errnoCode)"
        case .lockFailed(let path, let errnoCode):
            return "Failed to acquire single-instance lock at \(path): errno \(errnoCode)"
        }
    }
}
