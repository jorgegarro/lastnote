// swift-tools-version:6.0
import PackageDescription

let vendorHeaderPaths = [
    "scintilla/include", "scintilla/src", "scintilla/cocoa",
    "lexilla/include", "lexilla/lexlib", "include",
]

let package = Package(
    name: "LastNote",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "LastNote", targets: ["LastNote"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.20.0"),
    ],
    targets: [
        // Scintilla (editor engine, same as Notepad++) + Lexilla (syntax lexers), compiled from
        // vendored source. See Vendor/PATCHES.md for local modifications.
        .target(
            name: "SciKit",
            path: "Vendor",
            exclude: ["scintilla/src/SciTE.properties"],
            sources: [
                "scintilla/src",
                "scintilla/cocoa/InfoBar.mm",
                "scintilla/cocoa/PlatCocoa.mm",
                "scintilla/cocoa/ScintillaCocoa.mm",
                "scintilla/cocoa/ScintillaView.mm",
                "lexilla/src/Lexilla.cxx",
                "lexilla/lexlib",
                "lexilla/lexers",
                "bridge",
            ],
            publicHeadersPath: "include",
            cSettings: vendorHeaderPaths.map { .headerSearchPath($0) },
            cxxSettings: vendorHeaderPaths.map { .headerSearchPath($0) } + [
                .unsafeFlags(["-Wno-everything"]),
            ],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("CoreText"),
            ]
        ),
        .executableTarget(
            name: "LastNote",
            dependencies: [
                "SciKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/LastNote",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LastNoteTests",
            dependencies: [
                "LastNote", "SciKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Tests/LastNoteTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
