//
//  Plugin.swift
//  SpellTimerPlugin
//
//  Created by Joe McBride on 1/20/22.
//

import Foundation
import Plugins

@objc public class SpellTimerPlugin: NSObject, OPlugin {
    private var host: IHost?
    private var spells = SpellTimer()
    private var spellExpression: NSRegularExpression
    private var roisaenExpression: NSRegularExpression
    private var omExpression: NSRegularExpression

    public var name: String = "Spell Timer Plugin"

    override public required init() {
        spellExpression = try! NSRegularExpression(pattern: "(.+?)\\s+\\((.+)\\)", options: [])
        roisaenExpression = try! NSRegularExpression(pattern: "(\\d+) roisae?n", options: [])
        omExpression = try! NSRegularExpression(pattern: "(\\d+)%", options: [])
        super.init()
    }

    public func initialize(host: IHost) {
        self.host = host
    }

    public func variableChanged(variable _: String, value _: String) {}

    public func parse(input: String) -> String {
        let trimmed = input.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard trimmed.hasPrefix("/spelltimer") else {
            return input
        }

        host?.send(text: "#echo SpellTimer Plugin v1")

        host?.send(text: "#echo Active:")
        for spell in spells.spells.values.filter({ $0.active }) {
            host?.send(text: "#echo   \(spell.name) (\(spell.duration) roisaen)")
        }

        host?.send(text: "#echo Inactive:")
        for spell in spells.spells.values.filter({ !$0.active }) {
            host?.send(text: "#echo   \(spell.name) (\(spell.duration) roisaen)")
        }

        return ""
    }

    var cleared = false

    public func parse(xml: String) -> String {
        if xml.hasPrefix("<clearStream id=\"percWindow\"/>") {
            spells.cleared()
            cleared = true
        }

        if cleared, xml.contains("<prompt") {
            cleared = false
            spells.update()
            updateVariables()
        }

        return xml
    }

    public func parse(text: String, window: String) -> String {
        guard window.lowercased() == "percwindow" else {
            return text
        }

        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return text
        }

        let matches = spellExpression.firstMatch(input: text)

        if matches.count > 2 {
            let name = matches[1]
            var duration = 0

            if name == "Osrel Meraud" {
                let omMatches = omExpression.firstMatch(input: matches[2])
                if omMatches.count == 2 {
                    duration = Int(omMatches[1]) ?? 0
                }
            } else if matches[2] == "Indefinite" || matches[2] == "OM" {
                duration = 999
            } else {
                let roisMatches = roisaenExpression.firstMatch(input: matches[2])
                if roisMatches.count == 2 {
                    duration = Int(roisMatches[1]) ?? 0
                }
            }

            spells.streamed(name: name, duration: duration)
        }

        return text
    }

    private func updateVariables() {
        let prefix = "SpellTimer."
        for spell in spells.spells.values {
            let active = spell.active ? "1" : "0"
            host?.set(variable: "\(prefix)\(spell.name).active", value: "\(active)")
            host?.set(variable: "\(prefix)\(spell.name).duration", value: "\(spell.duration)")
        }
    }
}

class Spell {
    var name: String
    var duration: Int
    var active: Bool

    init(name: String, duration: Int, active: Bool = false) {
        self.name = name
        self.duration = duration
        self.active = active
    }
}

class SpellTimer {
    var spells: [String: Spell] = [:]
    var streamed: [String] = []

    func find(name: String) -> Spell {
        let varName = convertToVariableName(name: name)
        var spell = spells[varName]

        if spell == nil {
            spell = Spell(name: varName, duration: 0, active: false)
            spells[varName] = spell
        }

        return spell!
    }

    func streamed(name: String, duration: Int) {
        let spell = find(name: name)
        spell.duration = duration
        spell.active = true
        streamed.append(spell.name)
    }

    func cleared() {
        streamed = []
    }

    func update() {
        for spell in spells.values {
            guard streamed.contains(spell.name) else {
                spell.active = false
                spell.duration = 0
                continue
            }
        }
    }

    private func convertToVariableName(name: String) -> String {
        name
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: "")
    }
}

extension String {
    subscript(i: Int) -> Character {
        self[index(startIndex, offsetBy: i)]
    }

    subscript(_ range: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        let end = index(start, offsetBy: min(count - range.lowerBound,
                                             range.upperBound - range.lowerBound))
        return String(self[start ..< end])
    }

    subscript(_ range: CountablePartialRangeFrom<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        return String(self[start...])
    }
}

extension NSRegularExpression {
    func firstMatch(input: String) -> [String] {
        let nsrange = NSRange(input.startIndex ..< input.endIndex,
                              in: input)

        guard let match = firstMatch(in: input, options: [], range: nsrange) else {
            return []
        }

        return (0 ... match.numberOfRanges).compactMap { match.valueAt(index: $0, for: input) }
    }
}

extension NSTextCheckingResult {
    func valueAt(index: Int, for input: String) -> String? {
        guard index < numberOfRanges else {
            return nil
        }

        let rangeIndex = range(at: index)
        if let range = Range(rangeIndex, in: input) {
            return String(input[range])
        }

        return nil
    }
}
