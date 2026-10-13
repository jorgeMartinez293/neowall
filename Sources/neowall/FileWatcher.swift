import Foundation

/// Calls `onChange` on the main queue when any of `paths` is written, renamed
/// or deleted. Watch the parent directory too: editors that save atomically
/// replace the file, which a watch on the old file alone never reports.
final class FileWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []

    init(paths: [String], onChange: @escaping () -> Void) {
        for path in paths {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .rename, .delete], queue: .main
            )
            source.setEventHandler(handler: onChange)
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
    }

    deinit {
        sources.forEach { $0.cancel() }
    }
}
