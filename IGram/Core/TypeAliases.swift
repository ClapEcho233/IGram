//
//  TypeAliases.swift
//  IGram
//

import Foundation
import SwiftUI

// TDLibKit generates a type for every td_api object, so it also declares
// `Date`, `Text`, `Animation`, `Error` and `Notification`. Declarations in this
// module shadow imported ones, so these aliases make the Apple types win
// everywhere in IGram. Spell the TDLib types with a `TDLibKit.` prefix.

typealias Date = Foundation.Date
typealias Notification = Foundation.Notification
typealias Text = SwiftUI.Text
typealias Animation = SwiftUI.Animation
typealias Error = Swift.Error
