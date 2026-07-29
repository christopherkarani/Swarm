/// Shared error description formatting for redaction and debug payloads.
internal enum HiveErrorDescription {
    static func describe(_ error: Error, debugPayloads: Bool) -> String {
        if debugPayloads {
            return String(reflecting: error)
        }
        return String(describing: type(of: error))
    }
}
