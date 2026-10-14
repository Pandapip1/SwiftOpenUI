#pragma once

#include <pango/pangocairo.h>
#include <pango/pangofc-fontmap.h>
#include <fontconfig/fontconfig.h>

/// Tell Pango's default Fontconfig-backed map that its underlying
/// configuration has changed. This is required after adding an application
/// font because the default map may have been constructed by library startup
/// before SwiftOpenUI registers its bundled font.
static inline void
gtk_swift_pango_fontconfig_changed(void) {
    PangoFontMap *font_map = pango_cairo_font_map_get_default();
    if (PANGO_IS_FC_FONT_MAP(font_map)) {
        PangoFcFontMap *fc_font_map = PANGO_FC_FONT_MAP(font_map);
        // A default map created before registration retains the previous
        // FcConfig object. Point it at the process-local current config, which
        // contains the application font, before invalidating its caches.
        pango_fc_font_map_set_config(fc_font_map, FcConfigGetCurrent());
        pango_fc_font_map_config_changed(fc_font_map);
    }
}
