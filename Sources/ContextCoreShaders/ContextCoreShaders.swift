import Foundation

/// Accessor namespace for the ContextCore shader resource bundle.
public enum ContextCoreShadersModule {
    /// Resource bundle containing Metal shader sources used by the engine targets.
    public static var bundle: Bundle {
        .module
    }
}
