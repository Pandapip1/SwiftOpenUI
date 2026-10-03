import Foundation

/// A value kept in `UserDefaults` that re-renders its view when written, like SwiftUI's `@AppStorage`.
/// Reads always go to the defaults database, so values written elsewhere (another view, `defaults write`) are seen.
@propertyWrapper
public struct AppStorage<Value>: AnyStateStorageProvider {
    private let key: String
    private let store: UserDefaults
    private let defaultValue: Value
    private let read: (UserDefaults, String) -> Value?
    private let write: (UserDefaults, String, Value) -> Void
    private let state: StateStorage<Value>

    public var anyStorage: AnyStateStorage { state }

    public var wrappedValue: Value {
        get { read(store, key) ?? defaultValue }
        nonmutating set {
            write(store, key, newValue)
            state.setValue(newValue)
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { self.wrappedValue }, set: { self.wrappedValue = $0 })
    }

    fileprivate init(_ defaultValue: Value, _ key: String, _ store: UserDefaults?,
                     read: @escaping (UserDefaults, String) -> Value?,
                     write: @escaping (UserDefaults, String, Value) -> Void) {
        let defaults = store ?? .standard
        self.key = key
        self.store = defaults
        self.defaultValue = defaultValue
        self.read = read
        self.write = write
        self.state = StateStorage(read(defaults, key) ?? defaultValue)
    }
}

extension AppStorage where Value == Bool {
    public init(wrappedValue: Bool, _ key: String, store: UserDefaults? = nil) {
        self.init(wrappedValue, key, store, read: { $0.object(forKey: $1) as? Bool }, write: { $0.set($2, forKey: $1) })
    }
}
extension AppStorage where Value == Int {
    public init(wrappedValue: Int, _ key: String, store: UserDefaults? = nil) {
        self.init(wrappedValue, key, store, read: { $0.object(forKey: $1) as? Int }, write: { $0.set($2, forKey: $1) })
    }
}
extension AppStorage where Value == Double {
    public init(wrappedValue: Double, _ key: String, store: UserDefaults? = nil) {
        self.init(wrappedValue, key, store, read: { $0.object(forKey: $1) as? Double }, write: { $0.set($2, forKey: $1) })
    }
}
extension AppStorage where Value == String {
    public init(wrappedValue: String, _ key: String, store: UserDefaults? = nil) {
        self.init(wrappedValue, key, store, read: { $0.string(forKey: $1) }, write: { $0.set($2, forKey: $1) })
    }
}
extension AppStorage where Value == URL {
    public init(wrappedValue: URL, _ key: String, store: UserDefaults? = nil) {
        self.init(wrappedValue, key, store, read: { $0.string(forKey: $1).flatMap(URL.init(string:)) }, write: { $0.set($2.absoluteString, forKey: $1) })
    }
}
extension AppStorage where Value == Data {
    public init(wrappedValue: Data, _ key: String, store: UserDefaults? = nil) {
        self.init(wrappedValue, key, store, read: { $0.data(forKey: $1) }, write: { $0.set($2, forKey: $1) })
    }
}
extension AppStorage where Value: RawRepresentable, Value.RawValue == String {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        self.init(wrappedValue, key, store, read: { $0.string(forKey: $1).flatMap(Value.init(rawValue:)) }, write: { $0.set($2.rawValue, forKey: $1) })
    }
}
extension AppStorage where Value: RawRepresentable, Value.RawValue == Int {
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) {
        self.init(wrappedValue, key, store, read: { ($0.object(forKey: $1) as? Int).flatMap(Value.init(rawValue:)) }, write: { $0.set($2.rawValue, forKey: $1) })
    }
}
