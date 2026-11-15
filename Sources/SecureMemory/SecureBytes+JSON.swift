import Foundation

extension SecureBytes {
    /// JSON-encodes `value` straight into protected memory.
    ///
    /// The encoder's output buffer is wiped once copied. Strings inside
    /// `value` and the encoder's own scratch space are outside this type's
    /// control.
    public convenience init<Value: Encodable>(
        jsonEncoding value: Value, encoder: JSONEncoder = JSONEncoder()
    ) throws {
        var encoded = try encoder.encode(value)
        self.init(wiping: &encoded)
    }

    /// Decodes a JSON value from the protected bytes without first copying
    /// them into an owned `Data`.
    ///
    /// The decoded value is ordinary Swift memory: protection ends for any
    /// secret it contains unless that field is itself a `SecureBytes`.
    public func decodeJSON<Value: Decodable>(
        _ type: Value.Type, decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        try withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else {
                return try decoder.decode(type, from: Data())
            }
            // A non-owning view of the protected buffer, valid only here.
            let view = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: bytes.count,
                deallocator: .none
            )
            return try decoder.decode(type, from: view)
        }
    }
}
