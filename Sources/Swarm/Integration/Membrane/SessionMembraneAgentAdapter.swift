#if SWARM_INTEGRATIONS && canImport(Membrane)
import Foundation
import MembraneCore

public extension MembraneEnvironment {
    /// Builds an enabled Membrane environment using the canonical Swarm-side
    /// adapter path. The ContextCore session tuning parameters are accepted for
    /// source compatibility; the default adapter derives its behavior from the
    /// `MembraneFeatureConfiguration` alone.
    static func contextCoreSession(
        configuration: MembraneFeatureConfiguration = .default,
        budget: MembraneCore.ContextBudget = MembraneCore.ContextBudget(
            totalTokens: 4096,
            profile: .foundationModels4K
        ),
        recallStore: (any MembraneCore.ContextRecallStore)? = nil,
        pointerStore: (any MembraneCore.PointerStore)? = nil,
        initialSnapshot: MembraneCore.ContextSnapshot? = nil
    ) -> MembraneEnvironment {
        MembraneEnvironment(
            isEnabled: true,
            configuration: configuration,
            adapter: DefaultMembraneAgentAdapter(configuration: configuration)
        )
    }
}
#endif
