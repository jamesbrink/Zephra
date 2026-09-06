#!/usr/bin/env swift

// Give the downloadable DMG the same icon as its app, before signing it.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let icon = NSImage(contentsOfFile: arguments[1]) else {
  fputs("usage: set-file-icon.swift <icon.icns> <file>\n", stderr)
  exit(1)
}
guard NSWorkspace.shared.setIcon(icon, forFile: arguments[2], options: []) else {
  fputs("icon: could not set the file icon\n", stderr)
  exit(1)
}
