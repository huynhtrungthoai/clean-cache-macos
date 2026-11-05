// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskWise",
    // Target names stay DiskCleaner / DiskCleanerCore: build.sh's output paths and the
    // L10n / knowledge-base dev-tree fallback paths are built from them; renaming only adds needless build risk.
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "DiskCleanerCore",
            path: "Sources/DiskCleanerCore"
        ),
        .executableTarget(
            name: "DiskCleaner",
            dependencies: ["DiskCleanerCore"],
            path: "Sources/DiskCleaner",
            // Deliberately no `resources`: SPM's generated Bundle.module calls fatalError when the
            // .bundle is missing, and bakes the developer's absolute build path into the release binary.
            // safety_db.json is copied into Contents/Resources by build.sh and loaded via Bundle.main at runtime.
            exclude: ["Resources"]
        ),
        // Self-test program: runs without XCTest (plain command-line toolchain); a failed assertion exits non-zero.
        // Usage: swift run SelfTest
        .executableTarget(
            name: "SelfTest",
            dependencies: ["DiskCleanerCore"],
            path: "Sources/SelfTest"
        ),
        // Command line for the agent channel (diskwise): CLI subcommands + stdio MCP server in one binary.
        // build.sh renames the product to diskwise when copying it into the .app; in dev it is DiskWiseCLI.
        .executableTarget(
            name: "DiskWiseCLI",
            dependencies: ["DiskCleanerCore"],
            path: "Sources/DiskWiseCLI"
        )
    ]
)
