import Foundation

/// Material Symbols name → Unicode codepoint lookup.
///
/// Google publishes each Material Symbols glyph at a Unicode Private Use
/// Area codepoint (the `U+E000…U+F8FF` range Unicode reserves for
/// application-defined glyphs). Backends that can't apply OpenType
/// ligature substitution — notably GDI on Win32 — use this to draw the
/// glyph directly by its PUA codepoint instead of relying on ligatures.
///
/// Backends that do apply ligatures (GTK4 / Pango, Web / CSS) don't need
/// this; they draw the literal name as text and let the font's ligature
/// feature substitute the glyph during shaping.
///
/// The answers are read out of the bundled font rather than kept in a table
/// here. A hand-maintained table meant every new entry in
/// `SFSymbolCompatibility.map` needed a second edit carrying a value nobody
/// could check without opening the font, and the whole thing silently went
/// stale whenever the font was bumped.
///
/// What comes back is "a codepoint that draws this name's glyph", not the
/// name's canonical codepoint. Those differ: 218 glyphs in this font are
/// reachable from more than one PUA codepoint, so the mapping cannot be
/// inverted and a glyph does not identify its name. For drawing a glyph the
/// distinction does not matter — every codepoint reaching that glyph renders
/// identically — but it does mean these values are not interchangeable with
/// the upstream `.codepoints` metadata file.
public enum MaterialSymbolsCodepoints {
    /// Look up a codepoint that draws `name`'s glyph, or nil if the bundled
    /// font has no ligature for it.
    public static func codepoint(for name: String) -> UInt32? {
        MaterialSymbolsFontIndex.codepoint(forLigature: name)
    }

    /// Fallback codepoint used when a requested name isn't in the font.
    /// Matches `SFSymbolCompatibility.missingSymbolPlaceholderName`
    /// (`help_outline`) so both unknown SF names and unknown Material
    /// names render the same "icon missing" glyph.
    ///
    /// The literal is the upstream codepoint for `help_outline`, used only if
    /// the font cannot be read at all.
    public static let missingGlyphCodepoint: UInt32 =
        codepoint(for: SFSymbolCompatibility.missingSymbolPlaceholderName) ?? 0xE8FD
}
