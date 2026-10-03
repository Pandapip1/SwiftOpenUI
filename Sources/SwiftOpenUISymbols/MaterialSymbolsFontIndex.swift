import Foundation

/// Reads the bundled font to resolve a Material Symbols name to a codepoint.
///
/// Backends that can't apply ligature substitution need a codepoint to draw.
/// The name→codepoint data already exists inside the font, so this reads it
/// there instead of duplicating it in a hand-maintained table that has to be
/// re-derived whenever the font is bumped.
///
/// What it resolves is "a codepoint that draws this name's glyph", not the
/// name's canonical codepoint, and those differ: 218 glyphs in the bundled
/// font are reachable from more than one Private Use Area codepoint, so a
/// glyph does not identify which name it belongs to and the mapping cannot be
/// inverted. For drawing a glyph that distinction does not matter — any
/// codepoint mapping to the right glyph renders identically.
///
/// Parsing is `cmap` (for characters→glyphs and the PUA glyphs→codepoints) and
/// the `GSUB` ligature lookups (for name→glyph), done once, lazily.
enum MaterialSymbolsFontIndex {
    /// A codepoint whose glyph is the one `name`'s ligature produces, or nil
    /// if the font has no such ligature.
    static func codepoint(forLigature name: String) -> UInt32? {
        guard let index = shared else { return nil }
        return index.codepoint(forLigature: name)
    }

    private static let shared: Index? = {
        guard let data = try? Data(contentsOf: MaterialSymbolsResources.roundedRegularFontURL) else {
            return nil
        }
        return Index(font: data)
    }()
}

// MARK: - Index

private struct Index {
    /// Ligature components keyed by the first glyph, as the GSUB format stores
    /// them: the rest of the sequence plus the glyph it produces.
    private let ligatures: [UInt16: [(components: [UInt16], glyph: UInt16)]]
    /// Characters a name can be spelled with → glyph.
    private let charToGlyph: [UInt32: UInt16]
    /// Glyph → some PUA codepoint that draws it.
    private let glyphToCodepoint: [UInt16: UInt32]

    init?(font data: Data) {
        let reader = FontReader(data: data)
        guard let cmapOffset = reader.tableOffset("cmap"),
              let gsubOffset = reader.tableOffset("GSUB"),
              let cmap = reader.parseCmap(at: cmapOffset)
        else { return nil }

        // Names are spelled with lowercase ASCII, digits and underscore; that
        // is the whole alphabet a ligature lookup needs.
        var chars: [UInt32: UInt16] = [:]
        for scalar in UInt32(0x20)...UInt32(0x7E) {
            if let glyph = cmap[scalar] { chars[scalar] = glyph }
        }

        // Private Use Area is where the icon glyphs are addressed.
        var codepoints: [UInt16: UInt32] = [:]
        for scalar in UInt32(0xE000)...UInt32(0xF8FF) {
            guard let glyph = cmap[scalar], glyph != 0 else { continue }
            if codepoints[glyph] == nil { codepoints[glyph] = scalar }
        }

        guard let ligatures = reader.parseLigatures(gsubOffset: gsubOffset) else { return nil }

        self.ligatures = ligatures
        self.charToGlyph = chars
        self.glyphToCodepoint = codepoints
    }

    func codepoint(forLigature name: String) -> UInt32? {
        var glyphs: [UInt16] = []
        glyphs.reserveCapacity(name.unicodeScalars.count)
        for scalar in name.unicodeScalars {
            guard let glyph = charToGlyph[scalar.value] else { return nil }
            glyphs.append(glyph)
        }
        guard let first = glyphs.first else { return nil }
        let rest = Array(glyphs.dropFirst())
        guard let candidates = ligatures[first] else { return nil }
        for candidate in candidates where candidate.components == rest {
            return glyphToCodepoint[candidate.glyph]
        }
        return nil
    }
}
