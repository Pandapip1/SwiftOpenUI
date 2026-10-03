import Foundation

/// Just enough TrueType to answer "which glyph does this ligature produce, and
/// what codepoint draws that glyph" from the bundled font.
///
/// Only two tables are needed. `cmap` maps characters to glyphs, which both
/// spells a name out in glyph ids and, read the other way over the Private Use
/// Area, says which codepoint draws a given glyph. `GSUB`'s ligature lookups
/// map a glyph sequence to the single glyph the name renders as.
///
/// All offsets are big-endian and every read is bounds-checked: a malformed or
/// truncated font returns nil rather than reading past the end.
struct FontReader {
    let data: Data

    // MARK: Primitives

    private func byte(_ offset: Int) -> UInt8? {
        guard offset >= 0, offset < data.count else { return nil }
        return data[data.startIndex + offset]
    }

    func u16(_ offset: Int) -> UInt16? {
        guard let hi = byte(offset), let lo = byte(offset + 1) else { return nil }
        return UInt16(hi) << 8 | UInt16(lo)
    }

    func i16(_ offset: Int) -> Int16? {
        u16(offset).map { Int16(bitPattern: $0) }
    }

    func u32(_ offset: Int) -> UInt32? {
        guard let a = byte(offset), let b = byte(offset + 1),
              let c = byte(offset + 2), let d = byte(offset + 3) else { return nil }
        return UInt32(a) << 24 | UInt32(b) << 16 | UInt32(c) << 8 | UInt32(d)
    }

    private func tag(_ offset: Int) -> String? {
        var scalars = ""
        for i in 0..<4 {
            guard let b = byte(offset + i) else { return nil }
            scalars.append(Character(UnicodeScalar(b)))
        }
        return scalars
    }

    // MARK: Table directory

    /// Offset of a top-level table, e.g. "cmap" or "GSUB".
    func tableOffset(_ wanted: String) -> Int? {
        guard let numTables = u16(4) else { return nil }
        for i in 0..<Int(numTables) {
            let record = 12 + i * 16
            guard let name = tag(record) else { return nil }
            if name == wanted {
                return u32(record + 8).map(Int.init)
            }
        }
        return nil
    }

    // MARK: cmap

    /// Character → glyph, from the best Unicode subtable the font offers.
    func parseCmap(at offset: Int) -> [UInt32: UInt16]? {
        guard let count = u16(offset + 2) else { return nil }

        // Prefer a full-repertoire subtable (format 12 lives behind 3/10),
        // falling back to the BMP one. Either covers the PUA range the icons
        // use; taking both and merging keeps whichever is present.
        var best: Int?
        var bestScore = -1
        for i in 0..<Int(count) {
            let record = offset + 4 + i * 8
            guard let platform = u16(record), let encoding = u16(record + 2),
                  let subtableOffset = u32(record + 4) else { return nil }
            let score: Int
            switch (platform, encoding) {
            case (3, 10), (0, 4), (0, 6): score = 3 // full repertoire
            case (3, 1), (0, 3): score = 2          // BMP
            case (0, _): score = 1
            default: score = 0
            }
            if score > bestScore {
                bestScore = score
                best = offset + Int(subtableOffset)
            }
        }
        guard let subtable = best, let format = u16(subtable) else { return nil }
        switch format {
        case 4: return parseCmapFormat4(at: subtable)
        case 12: return parseCmapFormat12(at: subtable)
        default: return nil
        }
    }

    private func parseCmapFormat4(at offset: Int) -> [UInt32: UInt16]? {
        guard let segCountX2 = u16(offset + 6) else { return nil }
        let segCount = Int(segCountX2) / 2
        let segSpan = Int(segCountX2)
        let endCodes = offset + 14
        let startCodes = endCodes + segSpan + 2 // +2 for reservedPad
        let idDeltas = startCodes + segSpan
        let idRangeOffsets = idDeltas + segSpan

        var map: [UInt32: UInt16] = [:]
        for segment in 0..<segCount {
            guard let end = u16(endCodes + segment * 2),
                  let start = u16(startCodes + segment * 2),
                  let delta = i16(idDeltas + segment * 2),
                  let rangeOffset = u16(idRangeOffsets + segment * 2)
            else { return nil }
            if start > end { continue }
            for code in UInt32(start)...UInt32(end) {
                if code == 0xFFFF { continue }
                var glyph: UInt16
                if rangeOffset == 0 {
                    glyph = UInt16(truncatingIfNeeded: Int(code) + Int(delta))
                } else {
                    // The spec's pointer arithmetic: the offset is from the
                    // idRangeOffset slot itself.
                    let slot = idRangeOffsets + segment * 2
                    let target = slot + Int(rangeOffset) + Int(code - UInt32(start)) * 2
                    guard let raw = u16(target) else { return nil }
                    if raw == 0 { continue }
                    glyph = UInt16(truncatingIfNeeded: Int(raw) + Int(delta))
                }
                if glyph != 0 { map[code] = glyph }
            }
        }
        return map
    }

    private func parseCmapFormat12(at offset: Int) -> [UInt32: UInt16]? {
        guard let groups = u32(offset + 12) else { return nil }
        var map: [UInt32: UInt16] = [:]
        for group in 0..<Int(groups) {
            let record = offset + 16 + group * 12
            guard let start = u32(record), let end = u32(record + 4),
                  let startGlyph = u32(record + 8) else { return nil }
            if start > end || end &- start > 0x10FFFF { continue }
            for code in start...end {
                let glyph = startGlyph &+ (code &- start)
                if glyph != 0, glyph <= UInt32(UInt16.max) { map[code] = UInt16(glyph) }
            }
        }
        return map
    }

    // MARK: GSUB ligatures

    /// Ligatures keyed by their first glyph, as GSUB stores them: the rest of
    /// the sequence, and the glyph the whole sequence produces.
    func parseLigatures(gsubOffset: Int) -> [UInt16: [(components: [UInt16], glyph: UInt16)]]? {
        guard let lookupListOffset = u16(gsubOffset + 8) else { return nil }
        let lookupList = gsubOffset + Int(lookupListOffset)
        guard let lookupCount = u16(lookupList) else { return nil }

        var ligatures: [UInt16: [(components: [UInt16], glyph: UInt16)]] = [:]
        for i in 0..<Int(lookupCount) {
            guard let lookupOffset = u16(lookupList + 2 + i * 2) else { return nil }
            let lookup = lookupList + Int(lookupOffset)
            guard let type = u16(lookup), let subtableCount = u16(lookup + 4) else { return nil }
            for s in 0..<Int(subtableCount) {
                guard let subtableOffset = u16(lookup + 6 + s * 2) else { return nil }
                let subtable = lookup + Int(subtableOffset)
                collectLigatures(at: subtable, lookupType: type, into: &ligatures)
            }
        }
        return ligatures
    }

    private func collectLigatures(
        at subtable: Int,
        lookupType: UInt16,
        into ligatures: inout [UInt16: [(components: [UInt16], glyph: UInt16)]]
    ) {
        // Type 7 wraps the real subtable, which is how a font with more than
        // 64k of lookup data stores them — and how this one does.
        if lookupType == 7 {
            guard let innerType = u16(subtable + 2), let delta = u32(subtable + 4) else { return }
            collectLigatures(at: subtable + Int(delta), lookupType: innerType, into: &ligatures)
            return
        }
        guard lookupType == 4 else { return }
        guard let coverageOffset = u16(subtable + 2), let setCount = u16(subtable + 4),
              let covered = parseCoverage(at: subtable + Int(coverageOffset))
        else { return }

        for index in 0..<Int(setCount) {
            guard index < covered.count,
                  let setOffset = u16(subtable + 6 + index * 2) else { return }
            let set = subtable + Int(setOffset)
            guard let ligCount = u16(set) else { return }
            let firstGlyph = covered[index]
            for l in 0..<Int(ligCount) {
                guard let ligOffset = u16(set + 2 + l * 2) else { return }
                let lig = set + Int(ligOffset)
                guard let glyph = u16(lig), let componentCount = u16(lig + 2) else { return }
                guard componentCount >= 1 else { continue }
                var components: [UInt16] = []
                components.reserveCapacity(Int(componentCount) - 1)
                var truncated = false
                for c in 0..<(Int(componentCount) - 1) {
                    guard let component = u16(lig + 4 + c * 2) else { truncated = true; break }
                    components.append(component)
                }
                if truncated { continue }
                ligatures[firstGlyph, default: []].append((components, glyph))
            }
        }
    }

    /// Glyphs in coverage order, which is the order ligature sets are in.
    private func parseCoverage(at offset: Int) -> [UInt16]? {
        guard let format = u16(offset) else { return nil }
        switch format {
        case 1:
            guard let count = u16(offset + 2) else { return nil }
            var glyphs: [UInt16] = []
            glyphs.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                guard let glyph = u16(offset + 4 + i * 2) else { return nil }
                glyphs.append(glyph)
            }
            return glyphs
        case 2:
            guard let rangeCount = u16(offset + 2) else { return nil }
            var glyphs: [UInt16] = []
            for r in 0..<Int(rangeCount) {
                let record = offset + 4 + r * 6
                guard let start = u16(record), let end = u16(record + 2),
                      let startIndex = u16(record + 4) else { return nil }
                if start > end { continue }
                // Ranges are in coverage-index order; place each glyph at its index.
                for glyph in start...end {
                    let index = Int(startIndex) + Int(glyph - start)
                    if glyphs.count <= index {
                        glyphs.append(contentsOf: repeatElement(0, count: index - glyphs.count + 1))
                    }
                    glyphs[index] = glyph
                }
            }
            return glyphs
        default:
            return nil
        }
    }
}
