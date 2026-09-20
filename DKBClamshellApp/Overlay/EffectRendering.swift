import AppKit
import DKBClamshellCore

/// What `LidMonitor` talks to; Lite and Full are interchangeable behind it
/// (plan D5). All calls are on the main actor.
@MainActor
protocol EffectRendering: AnyObject {
    /// Fills the overlay window.
    var view: NSView { get }
    /// `FoldPhase.prewarm`: get ready to draw (Full starts its capture here).
    func prepare()
    /// Once per frame while the overlay is visible.
    func update(_ params: EffectParameters)
    /// `FoldPhase.idle`: release whatever `prepare` acquired.
    func stop()
}
