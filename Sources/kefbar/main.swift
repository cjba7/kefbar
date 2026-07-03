// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Carlos B and kefbar contributors
//
// This file is part of kefbar.

import Foundation

// Entry point. Top-level async is allowed in main.swift; run and exit with the
// resolved code so libc flushes stdio.
let code = await CLI.main(Array(CommandLine.arguments.dropFirst()))
exit(code)
