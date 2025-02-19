// swift-tools-version:5.3

import PackageDescription

let package = Package(
	name: "Clibgit2",
	platforms: [.iOS(.v13)],
	products: [
		.library(
			name: "Clibgit2",
			targets: [ "Clibgit2" ]
		),
	],
	dependencies: [],
	targets: [
		.binaryTarget(
			name: "Clibgit2",
			url: "https://github.com/qmx/LibGit2-On-iOS/releases/download/build-0b804a49116e2db1f01187a6c86ce1f3a37669bf/Clibgit2.xcframework.zip",
			checksum: "5703277b6ce1b7aa1f86f44335582511dd93d4c740454e7e1ff14ed07081cef8"
		),
	]
)
