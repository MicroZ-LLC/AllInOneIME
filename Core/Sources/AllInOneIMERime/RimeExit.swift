import AllInOneIMECore
import Foundation

/// librime ended before the process exits. `exit()` (`NSApp.terminate`, the self-test's, a helper's) runs librime's
/// static destructors, which take its `Service` apart while its deployment thread may still be compiling: that thread
/// then crashed (SIGSEGV in `WorkspaceUpdate::Run`). So an exit waits for the deployment (and a sync of the learned
/// words, run on a queue of ours) and then finalizes librime, before those destructors run. `_exit` (the SIGTERM path)
/// runs neither.
extension RimeService {
    /// Registered once, after librime's `Service` exists (`start`), so it runs before that singleton is destroyed:
    /// handlers run in the reverse order of their registration.
    static let endsAtExit: Void = { _ = atexit { RimeService.endAtExit() } }()

    /// The mark of librime's deployment thread (`markDeploymentThread`): an exit from it can't wait for itself.
    private static let deploymentThreadKey = "AllInOneIME.rimeDeploymentThread"

    /// Called on librime's deployment thread, as each deployment starts (its "deploy" "start" notification).
    static func markDeploymentThread() {
        Thread.current.threadDictionary[deploymentThreadKey] = true
    }

    /// Takes none of `RimeService`'s locks but the sync flag's (held only to read or write it), so an exit called while
    /// one is held can't wait on itself; the deployment thread's own notifications take the deployment lock only while
    /// setting the status.
    private static func endAtExit() {
        let service = shared
        guard service.isStarted else { return }
        guard Thread.current.threadDictionary[deploymentThreadKey] == nil else {
            return log.error("exit called on librime's deployment thread: librime not ended first")
        }
        let began = Date()
        while service.isSyncing { Thread.sleep(forTimeInterval: 0.01) }  // swiftlint:disable:this blocking_call (exiting, any thread)
        trail.step("exit: join deployment, finalize")
        service.api.pointee.join_maintenance_thread()
        service.api.pointee.finalize()
        log.notice(String(format: "librime ended at exit after waiting %.2f s for its deployment", Date().timeIntervalSince(began)))
        trail.step("ended at exit")
    }
}
