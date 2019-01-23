# Package

version       = "0.1.0"
author        = "Zachary Carter"
description   = "API for play.nim-lang.org"
license       = "MIT"

srcdir        = "src"
bin           = @["nim_playground"]

# Dependencies

requires "nim >= 0.16.1"
requires "jester >= 0.1.1"
requires "nuuid >= 0.1.0"