import CGTK
import CGTKBridge
import Foundation

/// Counter for generating unique CSS class names.
private var cssClassCounter: Int = 0
private let cssCounterLock = NSLock()

/// An inline style is a rule, not widget state. Reusing the rule is important:
/// adding a provider to a display invalidates styles for the whole widget tree.
/// A provider per rendered modifier made rebuilding a feed quadratic and could
/// stall the main thread for seconds as the list grew.
private final class SharedCSSRule: @unchecked Sendable {
    struct DisplayUse {
        let display: gpointer
        var count: Int
    }

    let className: String
    let provider: UnsafeMutablePointer<GtkCssProvider>
    var displays: [UInt: DisplayUse] = [:]

    init(className: String, css: String) {
        self.className = className
        provider = gtk_css_provider_new()!
        gtk_css_provider_load_from_string(provider, css)
    }
}

nonisolated(unsafe) private var sharedCSSRules: [String: SharedCSSRule] = [:]
private let cssCleanupDataKey = "gtk-swift-shared-css-uses"

private final class SharedCSSUses: @unchecked Sendable {
    var entries: [(key: String, displayID: UInt)] = []

    func releaseAll() {
        for entry in entries { releaseSharedCSSRule(key: entry.key, displayID: entry.displayID) }
        entries.removeAll()
    }
}

private func releaseSharedCSSRule(key: String, displayID: UInt) {
    cssCounterLock.lock()
    defer { cssCounterLock.unlock() }
    guard let rule = sharedCSSRules[key], var use = rule.displays[displayID] else { return }
    use.count -= 1
    if use.count > 0 {
        rule.displays[displayID] = use
        return
    }
    gtk_swift_remove_css_provider_gp(use.display, gpointer(rule.provider))
    rule.displays.removeValue(forKey: displayID)
    if rule.displays.isEmpty {
        sharedCSSRules.removeValue(forKey: key)
        g_object_unref(gpointer(rule.provider))
    }
}

func gtkSharedCSSRuleCount() -> Int {
    cssCounterLock.lock()
    defer { cssCounterLock.unlock() }
    return sharedCSSRules.count
}

/// Apply inline CSS to a widget using a unique class name.
/// The provider is attached to the widget via a shared cleanup list so it is
/// automatically removed from the display when the widget is destroyed.
///
/// `disabledProperties`, when provided, are applied on top of the base rules
/// via a `:disabled` pseudo-class — the widget's sensitivity state governs
/// which set wins. Callers that skip it get GTK's default disabled styling,
/// which usually means the base rules continue to apply even when the
/// widget is insensitive (so a filled .borderedProminent button would keep
/// its full-strength color when disabled, giving no visual signal).
func applyCSSToWidget(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    properties: String,
    disabledProperties: String? = nil
) {
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    let cssNode: String
    switch typeName {
    case "GtkBox":    cssNode = "box"
    case "GtkLabel":  cssNode = "label"
    case "GtkButton": cssNode = "button"
    case "GtkImage":  cssNode = "image"
    default:          cssNode = typeName.lowercased().replacingOccurrences(of: "gtk", with: "")
    }
    let display = gtk_widget_get_display(widget)!
    let key = "\(cssNode)\u{1f}\(properties)\u{1f}\(disabledProperties ?? "")"

    cssCounterLock.lock()
    let rule: SharedCSSRule
    if let existing = sharedCSSRules[key] {
        rule = existing
    } else {
        cssClassCounter += 1
        let className = "gtk-swift-css-\(cssClassCounter)"
        var css = """
            .\(className) { \(properties) }
            \(cssNode).\(className) { \(properties) }
            button.\(className) { \(properties) }
            label.\(className) { \(properties) }
            """
        if let disabledProperties {
            css += """

                .\(className):disabled { \(disabledProperties) }
                \(cssNode).\(className):disabled { \(disabledProperties) }
                button.\(className):disabled { \(disabledProperties) }
                label.\(className):disabled { \(disabledProperties) }
                """
        }
        rule = SharedCSSRule(className: className, css: css)
        sharedCSSRules[key] = rule
    }
    let displayID = UInt(bitPattern: display)
    if var use = rule.displays[displayID] {
        use.count += 1
        rule.displays[displayID] = use
    } else {
        gtk_swift_add_css_provider_to_display(
            display,
            rule.provider,
            UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
        )
        rule.displays[displayID] = SharedCSSRule.DisplayUse(display: gpointer(display), count: 1)
    }
    cssCounterLock.unlock()

    gtk_widget_add_css_class(widget, rule.className)

    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    let uses: SharedCSSUses
    if let existing = g_object_get_data(object, cssCleanupDataKey) {
        uses = Unmanaged<SharedCSSUses>.fromOpaque(existing).takeUnretainedValue()
    } else {
        uses = SharedCSSUses()
        g_object_set_data_full(object, cssCleanupDataKey, Unmanaged.passRetained(uses).toOpaque()) { data in
            let uses = Unmanaged<SharedCSSUses>.fromOpaque(data!).takeRetainedValue()
            uses.releaseAll()
        }
    }
    uses.entries.append((key, displayID))
}
