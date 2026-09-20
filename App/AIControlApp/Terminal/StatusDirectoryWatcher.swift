import Foundation

/// Watches a directory for changes and fires a callback (on the main queue).
/// Used for the session status directory (PROJECT.md §11: "File watching so the
/// dashboard reacts to changes on disk"). A `DispatchSource` on the directory's
/// file descriptor is enough here: the hook writes each status file via temp +
/// rename, which mutates the directory entry and triggers `.write`.
final class StatusDirectoryWatcher {
    private let directory: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1

    init(directory: URL, onChange: @escaping () -> Void) {
        self.directory = directory
        self.onChange = onChange
        start()
    }

    deinit { stop() }

    private func start() {
        fileDescriptor = open(directory.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.onChange() }
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 { close(self.fileDescriptor) }
            self.fileDescriptor = -1
        }
        self.source = source
        source.resume()
    }

    private func stop() {
        source?.cancel()
        source = nil
    }
}
