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
        spells.initializeLookup(host: host)
    }

    public func variableChanged(variable _: String, value _: String) {}

    public func parse(input: String) -> String {
        let trimmed = input.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
        guard trimmed.hasPrefix("/spelltimer") || trimmed.hasPrefix("/spelltracker") else {
            return input
        }

        host?.send(text: "#echo SpellTimer Plugin v1")

        host?.send(text: "#echo Active:")
        for spell in spells.spells.values.filter({ $0.active }) {
            let duration = spell.duration == 999 ? "Indefinite" : "\(spell.duration) roisaen"
            host?.send(text: "#echo   \(spell.name) (\(duration))")
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
        var activeSpells: [String] = []
        var inActiveSpells: [String] = []
        for spell in spells.spells.values {
            let active = spell.active ? "1" : "0"
            host?.set(variable: "\(prefix)\(spell.name).name", value: "\(spell.originalName)")
            host?.set(variable: "\(prefix)\(spell.name).active", value: "\(active)")
            host?.set(variable: "\(prefix)\(spell.name).duration", value: "\(spell.duration)")
            host?.set(variable: "\(prefix)\(spell.name).alias", value: "\(spell.alias)")
            host?.set(variable: "\(prefix)\(spell.name).type", value: "\(spell.type)")
            
            if spell.active {
                activeSpells.append(spell.name)
            } else {
                inActiveSpells.append(spell.name)
            }
        }

        host?.set(variable: "activespells", value: activeSpells.joined(separator: "|"))
        host?.set(variable: "inactivespells", value: inActiveSpells.joined(separator: "|"))
    }
}

class Spell {
    var name: String
    var originalName: String
    var alias: String
    var type: String
    var duration: Int
    var active: Bool

    init(name: String, originalName: String, alias: String, type: String, duration: Int, active: Bool = false) {
        self.name = name
        self.originalName = originalName
        self.alias = alias
        self.type = type
        self.duration = duration
        self.active = active
    }
}

class SpellTimer {
    var spellLookup: [String: Spell] = [:]
    var spells: [String: Spell] = [:]
    var streamed: [String] = []

    func find(name: String) -> Spell {
        let varName = convertToVariableName(name: name)
        var spell = spells[varName]

        if spell == nil {
            let config = spellLookup[varName]
            spell = Spell(name: varName, originalName: name, alias: config?.alias ?? "", type: config?.type ?? "", duration: 0, active: false)
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

    var spellLookupInitialized = false
    func initializeLookup(host: IHost) {
        guard spellLookupInitialized == false else {
            return
        }
        guard let allspells = host.load(from: "allspells.txt") else {
            return
        }

        let lines = allspells.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines {
            let options = line.components(separatedBy: "|")
            //print("options \(options)")
            guard options.count == 3 else {
                print("Invalid spell config: \(line)")
                continue
            }

            let varName = convertToVariableName(name: options[0])
            let alias = options[1].count == 0 ? options[0] : options[1]
            spellLookup[varName] = Spell(name: varName, originalName: options[0], alias: alias, type: options[2], duration: 0)
        }
        
        spellLookupInitialized = true
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
