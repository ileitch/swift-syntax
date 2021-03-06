//===------------ main.swift - Entry point for lit-test-help --------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//


import SwiftSyntax
import Foundation

/// Print the given message to stderr
func printerr(_ message: String, terminator: String = "\n") {
  FileHandle.standardError.write((message + terminator).data(using: .utf8)!)
}

/// Print the help message
func printHelp() {
  print("""
    Utility to test SwiftSyntax syntax tree deserialization.

    Actions (must specify one):
      -deserialize
            Deserialize a full pre-edit syntax tree (-pre-edit-tree) and write
            the source representation of the syntax tree to an out file (-out).
      -deserialize-incremental
            Deserialize a full pre-edit syntax tree (-pre-edit-tree), parse an
            incrementally transferred post-edit syntax tree (-incr-tree) and
            write the source representation of the post-edit syntax tree to an
            out file (-out).
      -classify-syntax
            Parse the given source file (-source-file) and output it with
            tokens classified for syntax colouring.
      -help
            Print this help message

    Arguments:
      -source-file FILENAME
            The path to a Swift source file to parse
      -pre-edit-tree FILENAME
            The path to a JSON serialized pre-edit syntax tree
      -incr-tree FILENAME
            The path to a JSON serialized incrementally transferred post-edit
            syntax tree
      -serialization-format {json,byteTree} [default: json]
            The format that shall be used to serialize/deserialize the syntax
            tree. Defaults to json.
      -out FILENAME
            The file to which the source representation of the post-edit syntax
            tree shall be written.
      -swiftc FILENAME
            If specified, the path to the swiftc executable to parse the file.
            If not specified, swiftc will be looked up from PATH.
    """)
}

extension CommandLineArguments {
  func getSerializationFormat() throws -> SerializationFormat {
    switch self["-serialization-format"] {
    case nil:
      return .json
    case "json":
      return .json
    case "byteTree":
      return .byteTree
    default:
      throw CommandLineArguments.InvalidArgumentValueError(
        argName: "-serialization-format",
        value: self["-serialization-format"]!
      )
    }
  }
}

func performDeserialize(args: CommandLineArguments) throws {
  let fileURL = URL(fileURLWithPath: try args.getRequired("-pre-edit-tree"))
  let outURL = URL(fileURLWithPath: try args.getRequired("-out"))
  let format = try args.getSerializationFormat()

  let fileData = try Data(contentsOf: fileURL)

  let deserializer = SyntaxTreeDeserializer()
  let tree = try deserializer.deserialize(fileData, serializationFormat: format)

  let sourceRepresenation = tree.description
  try sourceRepresenation.write(to: outURL, atomically: false, encoding: .utf8)
}

func performRoundTrip(args: CommandLineArguments) throws {
  let preEditTreeURL = URL(fileURLWithPath: try args.getRequired("-pre-edit-tree"))
  let incrTreeURL = URL(fileURLWithPath: try args.getRequired("-incr-tree"))
  let outURL = URL(fileURLWithPath: try args.getRequired("-out"))
  let format = try args.getSerializationFormat()

  let preEditTreeData = try Data(contentsOf: preEditTreeURL)
  let incrTreeData = try Data(contentsOf: incrTreeURL)

  let deserializer = SyntaxTreeDeserializer()
  _ = try deserializer.deserialize(preEditTreeData, serializationFormat: format)
  let tree = try deserializer.deserialize(incrTreeData,
                                          serializationFormat: format)
  let sourceRepresenation = tree.description
  try sourceRepresenation.write(to: outURL, atomically: false, encoding: .utf8)
}

func performClassifySyntax(args: CommandLineArguments) throws {
  let treeURL = URL(fileURLWithPath: try args.getRequired("-source-file"))
  let swiftcURL = args["-swiftc"].map(URL.init(fileURLWithPath:))

  let tree = try SyntaxTreeParser.parse(treeURL, swiftcURL: swiftcURL)
  let classifications = SyntaxClassifier.classifyTokensInTree(tree)
  let printer = ClassifiedSyntaxTreePrinter(classifications: classifications)
  let result = printer.print(tree: tree)

  if let outURL = args["-out"].map(URL.init(fileURLWithPath:)) {
    try result.write(to: outURL, atomically: false, encoding: .utf8)
  } else {
    print(result)
  }
}

class NodePrinter: SyntaxVisitor {
  override func visitPre(_ node: Syntax) {
    assert(!node.isUnknown)
    print("<\(type(of: node))>", terminator:"")
  }
  override func visitPost(_ node: Syntax) {
    print("</\(type(of: node))>", terminator:"")
  }
  override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
    print(token, terminator:"")
    return .visitChildren
  }
}

func printSyntaxTree(args: CommandLineArguments) throws {
  let treeURL = URL(fileURLWithPath: try args.getRequired("-source-file"))
  let swiftcURL = args["-swiftc"].map(URL.init(fileURLWithPath:))
  let tree = try SyntaxTreeParser.parse(treeURL, swiftcURL: swiftcURL)
  tree.walk(NodePrinter())
}

do {
  let args = try CommandLineArguments.parse(CommandLine.arguments.dropFirst())

  if args.has("-deserialize-incremental") {
    try performRoundTrip(args: args)
  } else if args.has("-classify-syntax") {
    try performClassifySyntax(args: args)
  } else if args.has("-deserialize") {
    try performDeserialize(args: args)
  } else if args.has("-print-source") {
    try printSyntaxTree(args: args)
  } else if args.has("-help") {
    printHelp()
  } else {
    printerr("""
      No action specified.
      See -help for information about available actions
      """)
    exit(1)
  }
  exit(0)
} catch {
  printerr("\(error)")
  printerr("Run swift-swiftsyntax-test -help for more help.")
  exit(1)
}
