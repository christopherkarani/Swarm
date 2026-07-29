/// Compilation-time schema validation errors.
public enum HiveCompilationError: Error, Sendable {
    /// Multiple channel specs declare the same `HiveChannelID`.
    case duplicateChannelID(HiveChannelID)
    /// v1 restriction: `.taskLocal` channels must be `.checkpointed`.
    case invalidTaskLocalUntracked(channelID: HiveChannelID)
    case startEmpty
    case duplicateStartNode(HiveNodeID)
    case duplicateNodeID(HiveNodeID)
    case invalidNodeIDContainsReservedJoinCharacters(nodeID: HiveNodeID)
    case unknownStartNode(HiveNodeID)
    case unknownEdgeEndpoint(from: HiveNodeID, to: HiveNodeID, unknown: HiveNodeID)
    case duplicateRouter(from: HiveNodeID)
    case unknownRouterFrom(HiveNodeID)
    case invalidJoinEdgeParentsEmpty(target: HiveNodeID)
    case invalidJoinEdgeParentsContainsDuplicate(parent: HiveNodeID, target: HiveNodeID)
    case invalidJoinEdgeParentsContainsTarget(target: HiveNodeID)
    case unknownJoinParent(parent: HiveNodeID, target: HiveNodeID)
    case unknownJoinTarget(target: HiveNodeID)
    case duplicateJoinEdge(joinID: String)
    case staticGraphCycleDetected(nodes: [HiveNodeID])
    case outputProjectionUnknownChannel(HiveChannelID)
    case outputProjectionIncludesTaskLocal(HiveChannelID)
    case invalidNodeRunWhenChannelsEmpty(nodeID: HiveNodeID)
    case invalidNodeRunWhenUnknownChannel(nodeID: HiveNodeID, channelID: HiveChannelID)
    case invalidNodeRunWhenIncludesTaskLocalChannel(nodeID: HiveNodeID, channelID: HiveChannelID)
}
