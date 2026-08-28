@_exported import Swarm

/// Deprecated hollow re-export of Swarm.
///
/// Import `Swarm` directly. Membrane APIs (`MembraneEnvironment`,
/// `MembraneFeatureConfiguration`, `MembraneAgentAdapter`) live on the
/// `Swarm` product. `SwarmMembrane` will be removed in Swarm 0.7.0.
@available(*, deprecated, message: "Import Swarm instead. SwarmMembrane is a hollow re-export and will be removed in 0.7.0.")
public enum SwarmMembraneProduct: Sendable {}
