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
    /// New parameters (cheap; may be called several times per frame).
    func update(_ params: EffectParameters)
    /// Once per display refresh: do the actual drawing if anything changed.
    /// Drawing from anywhere else starves `CAMetalLayer`'s three drawables,
    /// blocks the main thread and presents frames out of order.
    func render()
    /// `FoldPhase.idle`: release whatever `prepare` acquired.
    func stop()
}
