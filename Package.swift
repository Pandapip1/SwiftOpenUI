// swift-tools-version: 6.2

import PackageDescription

let requestedBackend = Context.environment["SWIFTOPENUI_BACKEND"]?.lowercased()
#if os(Linux)
let gtkBackendEnabled = requestedBackend == nil || requestedBackend == "gtk"
let gtkWebKitEnabled = gtkBackendEnabled
#else
let gtkBackendEnabled = requestedBackend == "gtk"
let gtkWebKitEnabled = false
#endif
let gtkSwiftSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
] + (gtkBackendEnabled ? [.define("BACKEND_GTK")] : [])

var targets: [Target] = [
    .target(
        name: "CredentialStorage",
        dependencies: {
            #if os(Linux)
            return ["Security"]
            #else
            return []
            #endif
        }(),
        path: "Sources/CredentialStorage"
    ),
    // Portable declarative UI model consumed by non-SwiftUI renderers.
    .target(
        name: "SwiftOpenUICore",
        path: "Sources/SwiftOpenUI",
        swiftSettings: gtkSwiftSettings
    ),

    // Stable application-facing module. Applications import SwiftOpenUI on
    // every platform; this facade chooses the available backend surface.
    .target(
        name: "SwiftOpenUI",
        dependencies: gtkBackendEnabled ? ["SwiftOpenUICore"] : ["SwiftOpenUICore", "BackendSwiftUI"],
        path: "Sources/SwiftOpenUIFacade",
        swiftSettings: gtkSwiftSettings
    ),

    // Core tests
    .testTarget(
        name: "SwiftOpenUITests",
        dependencies: ["SwiftOpenUICore"],
        path: "Tests/SwiftOpenUITests"
    ),
    .testTarget(
        name: "CredentialStorageTests",
        dependencies: ["CredentialStorage"],
        path: "Tests/CredentialStorageTests"
    ),

    // Layout parity — shared snapshot model (platform-independent)
    .target(
        name: "LayoutParityShared",
        dependencies: [],
        path: "Tests/LayoutParityTests/Shared"
    ),
    // Layout parity — comparison logic unit tests (platform-independent)
    .testTarget(
        name: "LayoutParityComparisonTests",
        dependencies: ["LayoutParityShared"],
        path: "Tests/LayoutParityTests/ComparisonTests"
    ),

    // Bundled icon font resources for non-macOS backends. Ungated so
    // Windows / Web / Android backends can declare it as a dependency
    // alongside GTK4. macOS targets continue to use native SF Symbols
    // via real SwiftUI and never consume this target.
    .target(
        name: "SwiftOpenUISymbols",
        path: "Sources/SwiftOpenUISymbols",
        resources: [
            .copy("Resources/MaterialSymbolsRounded-Regular.ttf"),
            .copy("Resources/LICENSES"),
            .copy("Resources/README.md"),
        ]
    ),
]

if !gtkBackendEnabled {
    // Native Apple renderer. Do not construct this target for a GTK build on
    // macOS: the package's portable `WebKit` module intentionally has the same
    // API name as Apple's framework and would shadow it in that build graph.
    targets.append(.target(
        name: "BackendSwiftUI",
        dependencies: ["SwiftOpenUICore"],
        path: "Sources/Backend/SwiftUI",
        swiftSettings: gtkSwiftSettings,
        linkerSettings: [.linkedFramework("WebKit")]
    ))
}

// Compatibility modules use the same module and declaration names as Apple's
// frameworks. Apple builds import the system frameworks; Linux builds receive
// equivalent implementations from SwiftOpenUI.
#if os(Linux)
targets += [
    .target(
        name: "AuthenticationServices",
        dependencies: ["SwiftOpenUICore"],
        path: "Sources/AuthenticationServices"
    ),
    .systemLibrary(
        name: "CSecret",
        path: "Sources/CSecret",
        pkgConfig: "libsecret-1",
        providers: [.apt(["libsecret-1-dev"])]
    ),
    .target(
        name: "Security",
        dependencies: ["CSecret"],
        path: "Sources/Security"
    ),
]
#else
targets += [
    .target(name: "AuthenticationServicesCompatStub", path: "Sources/AuthenticationServicesCompatStub"),
    .target(name: "SecurityCompatStub", path: "Sources/SecurityCompatStub"),
]
#endif

// Example runner dependencies:
// - SwiftOpenUI for the core framework
// - Backend libraries on their native platforms
var exampleDeps: [Target.Dependency] = ["SwiftOpenUI"]
if !gtkBackendEnabled {
    targets.append(.target(
        name: "MacExampleSupport",
        dependencies: ["SwiftOpenUI"],
        path: "Sources/MacExampleSupport",
        swiftSettings: gtkSwiftSettings
    ))
    exampleDeps.append("MacExampleSupport")
}

// WebKit abstraction — platform-independent; the GTK backend wires up the concrete
// implementation on Linux, and Apple platforms use the system WebKit framework instead.
// Declared unconditionally so SwiftPM can resolve it on all hosts (including macOS,
// where Hummingbird references it via a .when(platforms: nonApple) condition in its
// test target — the resolver validates product existence regardless of the condition).
targets += [
    .target(
        name: "WebKit",
        dependencies: ["SwiftOpenUICore"],
        path: "Sources/WebKit",
        swiftSettings: gtkSwiftSettings
    ),
]

// GTK4 backend. Linux selects it by default; macOS can opt in for backend development.
if gtkBackendEnabled {
var gtkBackendDependencies: [Target.Dependency] = [
    "SwiftOpenUICore", "CGTK", "CAdwaita", "CGTKBridge", "CGTKWidgets", "CGStreamer", "CFontconfig", "SwiftOpenUISymbols",
]
var gtkBackendExclude: [String] = []
if gtkWebKitEnabled { gtkBackendDependencies += ["WebKit", "CWebKitGTK"] }
else { gtkBackendExclude.append("GTKWebView.swift") }
var gtkTestExclude: [String] = []
if !gtkWebKitEnabled { gtkTestExclude.append("GTK4WebViewTests.swift") }
var gtkTestDependencies: [Target.Dependency] = [
    "SwiftOpenUICore", "BackendGTK4", "CGTK", "CAdwaita", "CGTKBridge", "SwiftOpenUISymbols",
]
if gtkWebKitEnabled { gtkTestDependencies.append("WebKit") }
targets += [
    .systemLibrary(
        name: "CWebKitGTK",
        path: "Sources/Backend/GTK4/CWebKitGTK",
        pkgConfig: "webkitgtk-6.0",
        providers: [.apt(["libwebkitgtk-6.0-dev"])]
    ),
    .systemLibrary(
        name: "CGTK",
        path: "Sources/Backend/GTK4/CGTK",
        pkgConfig: "gtk4",
        providers: [.apt(["libgtk-4-dev"])]
    ),
    .systemLibrary(
        name: "CAdwaita",
        path: "Sources/Backend/GTK4/CAdwaita",
        pkgConfig: "libadwaita-1",
        providers: [.apt(["libadwaita-1-dev"])]
    ),
    .systemLibrary(
        name: "CGStreamer",
        path: "Sources/Backend/GTK4/CGStreamer",
        pkgConfig: "gstreamer-app-1.0",
        providers: [.apt(["libgstreamer1.0-dev", "libgstreamer-plugins-base1.0-dev"])]
    ),
    .systemLibrary(
        name: "CFontconfig",
        path: "Sources/Backend/GTK4/CFontconfig",
        pkgConfig: "fontconfig",
        providers: [.apt(["libfontconfig1-dev"])]
    ),
    .target(
        name: "CGTKBridge",
        dependencies: ["CGTK"],
        path: "Sources/Backend/GTK4/CGTKBridge"
    ),
    .target(
        name: "CGTKWidgets",
        dependencies: ["CGTK"],
        path: "Sources/Backend/GTK4/CGTKWidgets",
        publicHeadersPath: "include"
    ),
    .target(
        name: "BackendGTK4",
        dependencies: gtkBackendDependencies,
        path: "Sources/Backend/GTK4/Rendering",
        exclude: gtkBackendExclude,
        swiftSettings: gtkSwiftSettings,
        linkerSettings: [
            // FontConfig is used by the process-local font registration
            // path that loads SwiftOpenUISymbols' bundled Material Symbols
            // font. GTK/Pango pull libfontconfig in transitively for
            // runtime calls but pkg-config's --libs gtk4 doesn't name
            // it explicitly at link time; declare it here to keep the
            // FcConfig* symbols resolvable.
            .linkedLibrary("gstreamer-1.0"),
            .linkedLibrary("gstapp-1.0"),
        ]
    ),
    .target(
        name: "BrowserTabs",
        dependencies: ["SwiftOpenUI", "BackendGTK4", "CGTK", "CAdwaita"],
        path: "Sources/BrowserTabs",
        swiftSettings: gtkSwiftSettings
    ),
    .testTarget(
        name: "GTK4RenderTests",
        // SwiftOpenUISymbols is a DIRECT dependency: the symbol-mapping
        // tests import it (declared, not leaked transitively — see the
        // librano NIOFoundationCompat cold-build lesson).
        dependencies: gtkTestDependencies,
        path: "Tests/BackendTests/GTK4Tests",
        exclude: gtkTestExclude
    ),
    // Layout parity — GTK comparison against macOS reference
    .testTarget(
        name: "GTKLayoutParityTests",
        dependencies: ["SwiftOpenUI", "SwiftOpenUICore", "BackendGTK4", "CGTK", "CGTKBridge", "LayoutParityShared"],
        path: "Tests/LayoutParityTests/GTKComparison"
    ),
]
exampleDeps.append("BackendGTK4")
}

// Win32 backend (Windows)
#if os(Windows)
targets += [
    .target(
        name: "CWin32",
        path: "Sources/Backend/Win32/CWin32",
        publicHeadersPath: "include",
        linkerSettings: [
            .linkedLibrary("comctl32"),
            .linkedLibrary("user32"),
            .linkedLibrary("gdi32"),
            .linkedLibrary("d2d1"),
            .linkedLibrary("dwrite"),
            .linkedLibrary("windowscodecs"),
            .linkedLibrary("ole32"),
        ]
    ),
    .target(
        name: "CWin32Bridge",
        dependencies: ["CWin32"],
        path: "Sources/Backend/Win32/CWin32Bridge"
    ),
    .target(
        name: "BackendWin32",
        dependencies: ["SwiftOpenUICore", "CWin32", "CWin32Bridge", "SwiftOpenUISymbols"],
        path: "Sources/Backend/Win32/Rendering"
    ),
    .testTarget(
        name: "Win32RenderTests",
        dependencies: ["SwiftOpenUICore", "BackendWin32"],
        path: "Tests/BackendTests/Win32Tests"
    ),
    // Layout parity — Win32 comparison against macOS reference
    .testTarget(
        name: "Win32LayoutParityTests",
        dependencies: ["SwiftOpenUICore", "BackendWin32", "CWin32", "CWin32Bridge", "LayoutParityShared"],
        path: "Tests/LayoutParityTests/Win32Comparison"
    ),
]
exampleDeps.append("BackendWin32")
#endif

// Android backend — temporarily in root for cross-compilation testing
#if os(macOS)
if !gtkBackendEnabled {
targets += [
    .target(
        name: "CAdwaita",
        dependencies: [],
        path: "Sources/Backend/GTK4/CAdwaitaStubs"
    ),
    .target(
        name: "BrowserTabs",
        dependencies: ["SwiftOpenUI"],
        path: "Sources/BrowserTabs"
    ),
    // Stub so SwiftPM can resolve BackendGTK4 on macOS at resolution time.
    // The real target (with GTK system-library deps) only compiles on Linux.
    // HummingbirdKitTests conditionally depends on BackendGTK4 with
    // .when(platforms: [.linux]), so this stub is never linked on macOS.
    .target(
        name: "BackendGTK4",
        dependencies: [],
        path: "Sources/Backend/GTK4/Stubs"
    ),
]
}
targets += [
    .target(
        name: "BackendAndroid",
        dependencies: ["SwiftOpenUICore"],
        path: "Sources/Backend/Android/Rendering",
        swiftSettings: gtkSwiftSettings
    ),
    .testTarget(
        name: "AndroidRenderTests",
        dependencies: ["SwiftOpenUICore", "BackendAndroid"],
        path: "Tests/BackendTests/AndroidTests"
    ),
]
if !gtkBackendEnabled {
targets += [
    .testTarget(
        name: "SwiftUIBackendTests",
        dependencies: ["SwiftOpenUI"],
        path: "Tests/BackendTests/SwiftUITests"
    ),
    // Layout parity — macOS reference capture (uses real SwiftUI)
    .testTarget(
        name: "MacOSLayoutReferenceTests",
        dependencies: ["SwiftOpenUI", "LayoutParityShared"],
        path: "Tests/LayoutParityTests/MacOSReference"
    ),
]
}
#endif

// Web backend (WebAssembly)
// Gated to macOS host — Wasm cross-compilation always happens from macOS.
// On Linux, this avoids pulling JavaScriptKit into native GTK builds.
#if os(macOS)
targets += [
    .target(
        name: "BackendWeb",
        dependencies: [
            "SwiftOpenUICore",
            .product(name: "JavaScriptKit", package: "JavaScriptKit"),
        ],
        path: "Sources/Backend/Web/Rendering",
        swiftSettings: gtkSwiftSettings
    ),
    .testTarget(
        name: "WebDescriptorTests",
        dependencies: ["SwiftOpenUICore", "BackendWeb"],
        path: "Tests/BackendTests/WebTests"
    ),
]
exampleDeps.append("BackendWeb")
#endif

// Wasm linker settings: increase linear memory for debug builds.
// Default Wasm memory is too small for view trees with many modifiers.
var exampleLinkerSettings: [LinkerSetting] = [
    .unsafeFlags([
        "-Xlinker", "--initial-memory=134217728",  // 128 MB (debug binaries need ~38 MB)
        "-Xlinker", "--max-memory=268435456",      // 256 MB growable
    ], .when(platforms: [.wasi]))
]

// Examples — thin runners that wire Examples views to platform entry points.
// On a macOS-hosted GTK validation build, these sources would select their
// native SwiftUI branches from `os(macOS)` and mix two backends in one target.
// Linux GTK and ordinary macOS builds still expose the complete catalog.
#if os(macOS)
let includeExampleTargets = !gtkBackendEnabled
#else
let includeExampleTargets = true
#endif

if includeExampleTargets {
targets += [
    .executableTarget(
        name: "GradientDemo",
        dependencies: exampleDeps,
        path: "Examples/Showcase/GradientDemo",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "HelloWorld",
        dependencies: exampleDeps,
        path: "Examples/Showcase/HelloWorld",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "Stopwatch",
        dependencies: exampleDeps,
        path: "Examples/Showcase/Stopwatch",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "Calculator",
        dependencies: exampleDeps,
        path: "Examples/Showcase/Calculator",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ColorMixer",
        dependencies: exampleDeps,
        path: "Examples/Showcase/ColorMixer",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "SimplePaint",
        dependencies: exampleDeps,
        path: "Examples/Showcase/SimplePaint",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "LayoutStress",
        dependencies: exampleDeps,
        path: "Examples/Showcase/LayoutStress",
        linkerSettings: exampleLinkerSettings
    ),
    // Parity
    .executableTarget(
        name: "ParityViewsBasic",
        dependencies: exampleDeps,
        path: "Examples/Parity/ViewsBasic",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityViewsLayout",
        dependencies: exampleDeps,
        path: "Examples/Parity/ViewsLayout",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityModifiers",
        dependencies: exampleDeps,
        path: "Examples/Parity/Modifiers",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityCosmeticModifiers",
        dependencies: exampleDeps,
        path: "Examples/Parity/CosmeticModifiers",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityAccessibility",
        dependencies: exampleDeps,
        path: "Examples/Parity/Accessibility",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityMenu",
        dependencies: exampleDeps,
        path: "Examples/Parity/Menu",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityStateData",
        dependencies: exampleDeps,
        path: "Examples/Parity/StateData",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityNavigation",
        dependencies: exampleDeps,
        path: "Examples/Parity/Navigation",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityGestures",
        dependencies: exampleDeps,
        path: "Examples/Parity/Gestures",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityEnvironment",
        dependencies: exampleDeps,
        path: "Examples/Parity/Environment",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityAnimation",
        dependencies: exampleDeps,
        path: "Examples/Parity/Animation",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityViewsContainers",
        dependencies: exampleDeps,
        path: "Examples/Parity/ViewsContainers",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityFocus",
        dependencies: exampleDeps,
        path: "Examples/Parity/Focus",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityAppStructure",
        dependencies: exampleDeps,
        path: "Examples/Parity/AppStructure",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityKeyboardShortcut",
        dependencies: exampleDeps,
        path: "Examples/Parity/KeyboardShortcut",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityCommands",
        dependencies: exampleDeps,
        path: "Examples/Parity/Commands",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "ParityDropDestination",
        dependencies: exampleDeps,
        path: "Examples/Parity/DropDestination",
        linkerSettings: exampleLinkerSettings
    ),
    .executableTarget(
        name: "Win32ReviewSmoke",
        dependencies: exampleDeps,
        path: "Examples/Smoke/Win32Review",
        linkerSettings: exampleLinkerSettings
    ),
]

// M-Symbols-1 minimum-viable proof: bundled font loads into FontConfig
// process-locally and Pango renders a glyph by family name. Active on all
// platforms: macOS renders SF Symbol equivalents via the same example
// (SwiftUI-canonical); non-macOS backends render Material glyphs via
// Image(material:) against the SwiftOpenUISymbols font.
targets += [
    .executableTarget(
        name: "ParityMaterialSymbols",
        dependencies: exampleDeps,
        path: "Examples/Parity/MaterialSymbols",
        linkerSettings: exampleLinkerSettings
    ),
]
}

#if os(macOS)
let deps: [Package.Dependency] = [
    .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", from: "0.20.0"),
]
#else
let deps: [Package.Dependency] = []
#endif

// App bundle packaging plugin
targets.append(
    .plugin(
        name: "CreateBundle",
        capability: .command(
            intent: .custom(verb: "create-bundle", description: "Package an executable as a .app bundle"),
            permissions: [.writeToPackageDirectory(reason: "Creates .build/bundles/<Product>.app")]
        ),
        path: "Plugins/CreateBundle"
    )
)

let package = Package(
    name: "SwiftOpenUI",
    platforms: [.macOS(.v14), .iOS(.v17), .tvOS(.v17), .visionOS(.v1)],
    products: {
        var p: [Product] = [
            .library(name: "SwiftOpenUI", targets: ["SwiftOpenUI"]),
            .library(name: "CredentialStorage", targets: ["CredentialStorage"]),
        ]
        if gtkBackendEnabled {
        p.append(.library(name: "WebKit", targets: ["WebKit"]))
        p.append(.library(name: "CGTK", targets: ["CGTK"]))
        p.append(.library(name: "CAdwaita", targets: ["CAdwaita"]))
        p.append(.library(name: "CGTKBridge", targets: ["CGTKBridge"]))
        p.append(.library(name: "BackendGTK4", targets: ["BackendGTK4"]))
        p.append(.library(name: "BrowserTabs", targets: ["BrowserTabs"]))
        // SwiftOpenUISymbols is consumed transitively by BackendGTK4, but
        // also exposed as an importable product so apps can reference
        // `MaterialSymbolsResources` directly (e.g. to surface the bundled
        // license text in an About dialog or to perform custom font lookups).
        p.append(.library(name: "SwiftOpenUISymbols", targets: ["SwiftOpenUISymbols"]))
        }
        #if os(Windows)
        p.append(.library(name: "CWin32", targets: ["CWin32"]))
        p.append(.library(name: "CWin32Bridge", targets: ["CWin32Bridge"]))
        p.append(.library(name: "BackendWin32", targets: ["BackendWin32"]))
        // Same rationale as Linux: expose SwiftOpenUISymbols so apps can
        // reference MaterialSymbolsResources directly.
        p.append(.library(name: "SwiftOpenUISymbols", targets: ["SwiftOpenUISymbols"]))
        #endif
        #if os(macOS)
        if !gtkBackendEnabled {
        p.append(.library(name: "BackendSwiftUI", targets: ["BackendSwiftUI"]))
        p.append(.library(name: "WebKit", targets: ["WebKit"]))
        p.append(.library(name: "CAdwaita", targets: ["CAdwaita"]))
        p.append(.library(name: "BackendGTK4", targets: ["BackendGTK4"]))
        p.append(.library(name: "BrowserTabs", targets: ["BrowserTabs"]))
        }
        p.append(.library(name: "BackendAndroid", type: .dynamic, targets: ["BackendAndroid"]))
        #endif
        #if os(Linux)
        p.append(.library(name: "AuthenticationServices", targets: ["AuthenticationServices"]))
        p.append(.library(name: "Security", targets: ["Security"]))
        #else
        // Product placeholders let downstream manifests declare platform-
        // conditional dependencies; Apple source imports the system modules.
        p.append(.library(name: "AuthenticationServices", targets: ["AuthenticationServicesCompatStub"]))
        p.append(.library(name: "Security", targets: ["SecurityCompatStub"]))
        #endif
        return p
    }(),
    dependencies: deps,
    targets: targets,
    swiftLanguageModes: [.v6]
)
