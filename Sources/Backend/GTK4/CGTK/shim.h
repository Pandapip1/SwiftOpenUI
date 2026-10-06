#pragma once

#include <gtk/gtk.h>
#include <fontconfig/fontconfig.h>
#ifdef __linux__
#include <dlfcn.h>
#endif

// --- FontConfig process-local font shims ---

/// Register a font file for the current process only via FontConfig.
/// Used by SwiftOpenUI to load bundled fonts (Material Symbols) without
/// installing them to the user's system font directory. Returns non-zero
/// on success, 0 on failure. The file is added to the current FontConfig
/// context and made visible to Pango; it disappears when the process
/// exits.
static inline int
gtk_swift_fc_app_font_add_file(const char *path) {
    return (int)FcConfigAppFontAddFile(
        FcConfigGetCurrent(), (const FcChar8 *)path);
}

// --- CSS provider shims ---

static inline void
gtk_swift_add_css_provider_to_display(GdkDisplay *display,
                                      GtkCssProvider *provider,
                                      guint priority) {
    gtk_style_context_add_provider_for_display(
        display, GTK_STYLE_PROVIDER(provider), priority);
}

static inline void
gtk_swift_remove_css_provider_from_display(GdkDisplay *display,
                                           GtkCssProvider *provider) {
    gtk_style_context_remove_provider_for_display(
        display, GTK_STYLE_PROVIDER(provider));
}

/// Remove a CSS provider using gpointer (Swift-friendly).
static inline void
gtk_swift_remove_css_provider_gp(gpointer display, gpointer provider) {
    gtk_style_context_remove_provider_for_display(
        GDK_DISPLAY(display), GTK_STYLE_PROVIDER(provider));
}

// --- Label shims ---

static inline void
gtk_swift_label_set_xalign(GtkWidget *label, float xalign) {
    gtk_label_set_xalign(GTK_LABEL(label), xalign);
}

static inline void
gtk_swift_label_set_yalign(GtkWidget *label, float yalign) {
    gtk_label_set_yalign(GTK_LABEL(label), yalign);
}

static inline void
gtk_swift_label_set_text(GtkWidget *label, const char *text) {
    gtk_label_set_text(GTK_LABEL(label), text);
}

/// Set label text preserving use-markup and use-underline state.
static inline void
gtk_swift_label_set_label(GtkWidget *label, const char *text) {
    gtk_label_set_label(GTK_LABEL(label), text);
}

static inline gboolean
gtk_swift_label_get_use_markup(GtkWidget *label) {
    return gtk_label_get_use_markup(GTK_LABEL(label));
}

/// Make a label's text user-selectable. Guarded with GTK_IS_LABEL so it
/// is a safe no-op when the wrapped widget isn't a GtkLabel (e.g. a Text
/// whose modifiers rendered to a container).
static inline void
gtk_swift_label_set_selectable(GtkWidget *label, gboolean selectable) {
    if (GTK_IS_LABEL(label)) {
        gtk_label_set_selectable(GTK_LABEL(label), selectable);
    }
}

/// Set the accessible label (GTK_ACCESSIBLE_PROPERTY_LABEL) on a widget,
/// so screen readers announce this text instead of the widget's raw
/// contents. Wraps the variadic gtk_accessible_update_property, which
/// can't be called from Swift directly. Every GtkWidget is a
/// GtkAccessible in GTK4; the guard is defensive.
static inline void
gtk_swift_accessible_set_label(GtkWidget *widget, const char *label) {
    if (GTK_IS_ACCESSIBLE(widget)) {
        gtk_accessible_update_property(GTK_ACCESSIBLE(widget),
                                       GTK_ACCESSIBLE_PROPERTY_LABEL, label,
                                       -1);
    }
}

// --- Widget type shims ---

static inline gboolean
gtk_swift_is_widget(GtkWidget *widget) {
    return widget != NULL && GTK_IS_WIDGET(widget);
}

static inline gboolean
gtk_swift_is_label(GtkWidget *widget) {
    return widget != NULL && GTK_IS_LABEL(widget);
}

static inline GType
gtk_swift_get_widget_type(GtkWidget *widget) {
    return G_OBJECT_TYPE(widget);
}

static inline void
gtk_swift_widget_measure(GtkWidget *widget,
                         GtkOrientation orientation,
                         int for_size,
                         int *minimum,
                         int *natural) {
    int min = 0;
    int nat = 0;
    gtk_widget_measure(widget, orientation, for_size, &min, &nat, NULL, NULL);
    if (minimum) *minimum = min;
    if (natural) *natural = nat;
}

static inline GtkWidget *
gtk_swift_fixed_new(void) {
    return gtk_fixed_new();
}

static inline void
gtk_swift_fixed_put(GtkWidget *fixed, GtkWidget *child, double x, double y) {
    gtk_fixed_put(GTK_FIXED(fixed), child, x, y);
}

static inline void
gtk_swift_fixed_move(GtkWidget *fixed, GtkWidget *child, double x, double y) {
    gtk_fixed_move(GTK_FIXED(fixed), child, x, y);
}

static inline void
gtk_swift_fixed_get_child_position(GtkWidget *fixed,
                                   GtkWidget *child,
                                   double *x,
                                   double *y) {
    double child_x = 0;
    double child_y = 0;
    gtk_fixed_get_child_position(GTK_FIXED(fixed), child, &child_x, &child_y);
    if (x) *x = child_x;
    if (y) *y = child_y;
}

static inline GtkWidget *
gtk_swift_scrolled_window_new(void) {
    return gtk_scrolled_window_new();
}

static inline void
gtk_swift_scrolled_window_configure_clip(GtkWidget *scrolled,
                                         int width,
                                         int height) {
    GtkScrolledWindow *window = GTK_SCROLLED_WINDOW(scrolled);
    gtk_scrolled_window_set_policy(window, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL);
    gtk_scrolled_window_set_has_frame(window, FALSE);
    gtk_scrolled_window_set_min_content_width(window, width);
    gtk_scrolled_window_set_min_content_height(window, height);
    gtk_scrolled_window_set_max_content_width(window, width);
    gtk_scrolled_window_set_max_content_height(window, height);
    gtk_scrolled_window_set_propagate_natural_width(window, FALSE);
    gtk_scrolled_window_set_propagate_natural_height(window, FALSE);
}

static inline void
gtk_swift_scrolled_window_set_child(GtkWidget *scrolled, GtkWidget *child) {
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled), child);
}

// --- Focus shims ---

static inline gboolean
gtk_swift_grab_focus(GtkWidget *widget) {
    return gtk_widget_grab_focus(widget);
}

static inline void
gtk_swift_clear_focus(GtkWidget *widget) {
    GtkRoot *root = gtk_widget_get_root(widget);
    if (root) {
        gtk_root_set_focus(root, NULL);
    }
}

// --- Editable type check ---

static inline gboolean
gtk_swift_widget_is_editable(GtkWidget *widget) {
    return GTK_IS_EDITABLE(widget) ? TRUE : FALSE;
}

// --- Property setter shim (variadic g_object_set is not callable from Swift) ---

static inline void
g_object_set_double(gpointer object, const char *property, double value) {
    g_object_set(object, property, value, NULL);
}

// --- Gesture controller shim (GtkGesture → GtkEventController) ---

static inline void
gtk_swift_add_gesture(GtkWidget *widget, GtkGesture *gesture) {
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(gesture));
}

// --- Scale (Slider) type check ---

static inline gboolean
gtk_swift_widget_is_scale(GtkWidget *widget) {
    return GTK_IS_RANGE(widget) ? TRUE : FALSE;
}

// --- Image pixel size ---

static inline void
gtk_swift_image_set_pixel_size(GtkWidget *image, int size) {
    gtk_image_set_pixel_size(GTK_IMAGE(image), size);
}

// --- GtkPasswordEntry ---

static inline void
gtk_swift_password_entry_set_show_peek_icon(GtkWidget *entry, gboolean show) {
    gtk_password_entry_set_show_peek_icon(GTK_PASSWORD_ENTRY(entry), show);
}

// --- GtkSpinButton ---

static inline GtkWidget *
gtk_swift_spin_button_new_with_range(double min, double max, double step) {
    return gtk_spin_button_new_with_range(min, max, step);
}

static inline void
gtk_swift_spin_button_set_value(GtkWidget *widget, double value) {
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(widget), value);
}

static inline double
gtk_swift_spin_button_get_value(GtkWidget *widget) {
    return gtk_spin_button_get_value(GTK_SPIN_BUTTON(widget));
}

// --- GtkGrid shims ---

static inline void
gtk_swift_grid_attach(GtkWidget *grid, GtkWidget *child,
                      gint col, gint row, gint width, gint height) {
    gtk_grid_attach(GTK_GRID(grid), child, col, row, width, height);
}

static inline void
gtk_swift_grid_set_row_spacing(GtkWidget *grid, guint spacing) {
    gtk_grid_set_row_spacing(GTK_GRID(grid), spacing);
}

static inline void
gtk_swift_grid_set_column_spacing(GtkWidget *grid, guint spacing) {
    gtk_grid_set_column_spacing(GTK_GRID(grid), spacing);
}

static inline void
gtk_swift_grid_set_column_homogeneous(GtkWidget *grid, gboolean homogeneous) {
    gtk_grid_set_column_homogeneous(GTK_GRID(grid), homogeneous);
}

// --- GtkPicture shims ---

static inline GtkWidget *
gtk_swift_picture_new_for_filename(const char *filename) {
    return gtk_picture_new_for_filename(filename);
}

// Build a GtkPicture from an in-memory pixel buffer (for Image(decoded:)).
// Copies `pixels` into a GdkTexture (via GBytes), wraps it in a GtkPicture.
// The GDK_PAINTABLE cast and GdkMemoryFormat live here because Swift can't
// express the type-cast macros. `pixels` need not outlive this call.
static inline GtkWidget *
gtk_swift_picture_new_for_pixels(const unsigned char *pixels, gsize length,
                                 int width, int height, int stride,
                                 GdkMemoryFormat format) {
    GBytes *bytes = g_bytes_new(pixels, length);
    GdkTexture *texture = gdk_memory_texture_new(width, height, format, bytes, (gsize)stride);
    g_bytes_unref(bytes);
    GtkWidget *picture = gtk_picture_new_for_paintable(GDK_PAINTABLE(texture));
    g_object_unref(texture);  // GtkPicture holds its own ref
    return picture;
}

static inline void
gtk_swift_picture_set_content_fit(GtkWidget *picture, GtkContentFit fit) {
    gtk_picture_set_content_fit(GTK_PICTURE(picture), fit);
}

static inline void
gtk_swift_picture_set_can_shrink(GtkWidget *picture, gboolean can_shrink) {
    gtk_picture_set_can_shrink(GTK_PICTURE(picture), can_shrink);
}

static inline void
gtk_swift_picture_set_pixels(GtkWidget *picture, const unsigned char *pixels,
                             gsize length, int width, int height, int stride,
                             GdkMemoryFormat format) {
    GBytes *bytes = g_bytes_new(pixels, length);
    GdkTexture *texture = gdk_memory_texture_new(width, height, format, bytes, (gsize)stride);
    g_bytes_unref(bytes);
    gtk_picture_set_paintable(GTK_PICTURE(picture), NULL);
    gtk_picture_set_paintable(GTK_PICTURE(picture), GDK_PAINTABLE(texture));
    g_object_unref(texture);
    gtk_widget_queue_draw(picture);
}

typedef struct {
    guint8 *pixels;
    gint width;
    gint height;
    gint stride;
} SwiftOpenUIVideoSurface;

static inline GtkWidget *gtk_swift_video_surface_new(void) {
    static const guint8 black[4] = { 0, 0, 0, 255 };
    GtkWidget *picture = gtk_swift_picture_new_for_pixels(
        black, sizeof(black), 1, 1, 4, GDK_MEMORY_R8G8B8A8);
    gtk_picture_set_content_fit(GTK_PICTURE(picture), GTK_CONTENT_FIT_CONTAIN);
    gtk_picture_set_can_shrink(GTK_PICTURE(picture), TRUE);
    gtk_widget_set_hexpand(picture, TRUE);
    gtk_widget_set_vexpand(picture, TRUE);
    return picture;
}

// The GStreamer GTK sink owns its GPU textures; GtkPicture renders the same
// paintable directly without mapping, copying or uploading pixels in Swift.
static inline void gtk_swift_video_surface_set_paintable(GtkWidget *area, gpointer paintable) {
    gtk_picture_set_paintable(GTK_PICTURE(area), GDK_PAINTABLE(paintable));
}

static inline void gtk_swift_video_surface_set_pixels(GtkWidget *area, const guint8 *pixels,
                                                       gsize length, gint width, gint height,
                                                       gint stride) {
    if (!pixels || width <= 0 || height <= 0 || stride < width * 4 || length < (gsize)stride * height) return;
    gsize outputStride = (gsize)width * 4;
    guint8 *copy = g_malloc(outputStride * (gsize)height);
    for (gint y = 0; y < height; y++) {
        const guint8 *src = pixels + (gsize)y * stride;
        guint8 *dst = copy + (gsize)y * outputStride;
        memcpy(dst, src, outputStride);
    }
    GBytes *bytes = g_bytes_new_take(copy, outputStride * (gsize)height);
    GdkTexture *texture = gdk_memory_texture_new(width, height, GDK_MEMORY_R8G8B8A8, bytes, outputStride);
    g_bytes_unref(bytes);
    gtk_picture_set_paintable(GTK_PICTURE(area), NULL);
    gtk_picture_set_paintable(GTK_PICTURE(area), GDK_PAINTABLE(texture));
    g_object_unref(texture);
    gtk_widget_queue_draw(area);
}

// --- GtkExpander shims ---

static inline GtkWidget *
gtk_swift_expander_new(const char *label) {
    return gtk_expander_new(label);
}

static inline void
gtk_swift_expander_set_child(GtkWidget *expander, GtkWidget *child) {
    gtk_expander_set_child(GTK_EXPANDER(expander), child);
}

static inline void
gtk_swift_expander_set_expanded(GtkWidget *expander, gboolean expanded) {
    gtk_expander_set_expanded(GTK_EXPANDER(expander), expanded);
}

static inline gboolean
gtk_swift_expander_get_expanded(GtkWidget *expander) {
    return gtk_expander_get_expanded(GTK_EXPANDER(expander));
}

static inline void
gtk_swift_expander_set_label_widget(GtkWidget *expander, GtkWidget *label) {
    gtk_expander_set_label_widget(GTK_EXPANDER(expander), label);
}

// --- Label markup ---

static inline void
gtk_swift_label_set_markup(GtkWidget *label, const char *markup) {
    gtk_label_set_markup(GTK_LABEL(label), markup);
}

// --- GtkStack / GtkStackSwitcher shims ---

static inline void
gtk_swift_stack_set_transition_type(GtkWidget *stack, GtkStackTransitionType type) {
    gtk_stack_set_transition_type(GTK_STACK(stack), type);
}

static inline GtkWidget *
gtk_swift_stack_add_titled(GtkWidget *stack, GtkWidget *child,
                           const char *name, const char *title) {
    GtkStackPage *page = gtk_stack_add_titled(GTK_STACK(stack), child, name, title);
    (void)page;
    return child;
}

static inline void
gtk_swift_stack_set_visible_child_name(GtkWidget *stack, const char *name) {
    gtk_stack_set_visible_child_name(GTK_STACK(stack), name);
}

static inline const char *
gtk_swift_stack_get_visible_child_name(GtkWidget *stack) {
    return gtk_stack_get_visible_child_name(GTK_STACK(stack));
}

static inline void
gtk_swift_stack_switcher_set_stack(GtkWidget *switcher, GtkWidget *stack) {
    gtk_stack_switcher_set_stack(GTK_STACK_SWITCHER(switcher), GTK_STACK(stack));
}

// --- Picker shims ---

static inline void
gtk_swift_toggle_button_set_group(GtkWidget *button, GtkWidget *group_member) {
    gtk_toggle_button_set_group(GTK_TOGGLE_BUTTON(button),
                                group_member ? GTK_TOGGLE_BUTTON(group_member) : NULL);
}

static inline void
gtk_swift_toggle_button_set_active(GtkWidget *button, gboolean active) {
    gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(button), active);
}

static inline gboolean
gtk_swift_toggle_button_get_active(GtkWidget *button) {
    return gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(button));
}

// --- Calendar shims ---

static inline void
gtk_swift_calendar_get_ymd(GtkWidget *calendar, int *year, int *month, int *day) {
    GDateTime *dt = gtk_calendar_get_date(GTK_CALENDAR(calendar));
    *year = g_date_time_get_year(dt);
    *month = g_date_time_get_month(dt);
    *day = g_date_time_get_day_of_month(dt);
    g_date_time_unref(dt);
}

static inline void
gtk_swift_calendar_select_ymd(GtkWidget *calendar, int year, int month, int day) {
    GDateTime *dt = g_date_time_new_local(year, month, day, 0, 0, 0);
    if (dt) {
        gtk_calendar_select_day(GTK_CALENDAR(calendar), dt);
        g_date_time_unref(dt);
    }
}

// --- Search entry shims ---

static inline GtkWidget *
gtk_swift_search_entry_new(void) {
    return gtk_search_entry_new();
}

static inline void
gtk_swift_editable_set_text(GtkWidget *widget, const char *text) {
    gtk_editable_set_text(GTK_EDITABLE(widget), text);
}

static inline const char *
gtk_swift_editable_get_text(GtkWidget *widget) {
    return gtk_editable_get_text(GTK_EDITABLE(widget));
}

// --- GObject property setter (variadic g_object_set not callable from Swift) ---

static inline void
g_object_set_property_string(GtkWidget *widget, const char *property, const char *value) {
    g_object_set(G_OBJECT(widget), property, value, NULL);
}

// --- Menu / Action system shims ---

static inline gpointer
gtk_swift_menu_new(void) {
    return (gpointer)g_menu_new();
}

static inline void
gtk_swift_menu_append(gpointer menu, const char *label, const char *action) {
    g_menu_append(G_MENU(menu), label, action);
}

static inline void
gtk_swift_menu_append_section(gpointer menu, const char *label, gpointer section) {
    g_menu_append_section(G_MENU(menu), label, G_MENU_MODEL(section));
}

static inline void
gtk_swift_menu_append_submenu(gpointer menu, const char *label, gpointer submenu) {
    g_menu_append_submenu(G_MENU(menu), label, G_MENU_MODEL(submenu));
}

static inline void
gtk_swift_action_map_add_action(gpointer group, gpointer action) {
    g_action_map_add_action(G_ACTION_MAP(group), G_ACTION(action));
}

static inline void
gtk_swift_widget_insert_action_group(GtkWidget *widget, const char *prefix,
                                     gpointer group) {
    gtk_widget_insert_action_group(widget, prefix, G_ACTION_GROUP(group));
}

static inline GtkWidget *
gtk_swift_popover_menu_new_from_model(gpointer menu) {
    return gtk_popover_menu_new_from_model(G_MENU_MODEL(menu));
}

static inline void
gtk_swift_menu_button_set_popover(GtkWidget *button, GtkWidget *popover) {
    gtk_menu_button_set_popover(GTK_MENU_BUTTON(button), popover);
}

static inline void
gtk_swift_menu_button_set_label(GtkWidget *button, const char *label) {
    gtk_menu_button_set_label(GTK_MENU_BUTTON(button), label);
}

/// Set an arbitrary widget as the menu button's trigger (SwiftUI's
/// `Menu { } label: { <view> }`), instead of a string label.
static inline void
gtk_swift_menu_button_set_child(GtkWidget *button, GtkWidget *child) {
    gtk_menu_button_set_child(GTK_MENU_BUTTON(button), child);
}

/// Show/hide the menu button's frame (chrome). `false` →
/// `.menuStyle(.borderlessButton)`.
static inline void
gtk_swift_menu_button_set_has_frame(GtkWidget *button, gboolean has_frame) {
    gtk_menu_button_set_has_frame(GTK_MENU_BUTTON(button), has_frame);
}

// --- GtkListView / GtkListItem / GtkStringObject shims ---

static inline gpointer
gtk_swift_signal_list_item_factory_new(void) {
    return (gpointer)gtk_signal_list_item_factory_new();
}

static inline gpointer
gtk_swift_string_list_new(void) {
    return (gpointer)gtk_string_list_new(NULL);
}

static inline void
gtk_swift_string_list_append(gpointer list, const char *string) {
    gtk_string_list_append(GTK_STRING_LIST(list), string);
}

static inline gpointer
gtk_swift_no_selection_new(gpointer model) {
    return (gpointer)gtk_no_selection_new(G_LIST_MODEL(model));
}

static inline GtkWidget *
gtk_swift_list_view_new(gpointer model, gpointer factory) {
    return gtk_list_view_new(GTK_SELECTION_MODEL(model),
                             GTK_LIST_ITEM_FACTORY(factory));
}

static inline void
gtk_swift_list_item_set_child(gpointer list_item, GtkWidget *child) {
    gtk_list_item_set_child(GTK_LIST_ITEM(list_item), child);
}

static inline GtkWidget *
gtk_swift_list_item_get_child(gpointer list_item) {
    return gtk_list_item_get_child(GTK_LIST_ITEM(list_item));
}

static inline gpointer
gtk_swift_list_item_get_item(gpointer list_item) {
    return gtk_list_item_get_item(GTK_LIST_ITEM(list_item));
}

static inline const char *
gtk_swift_string_object_get_string(gpointer string_object) {
    return gtk_string_object_get_string(GTK_STRING_OBJECT(string_object));
}

// --- GtkTreeListModel / GtkTreeListRow / GtkTreeExpander shims ---
//
// These back a lazily-realized tree (used by `OutlineGroup`): only the
// rows currently scrolled into view — and only the children of rows the
// user has actually expanded — are ever realized as widgets.
//
// `create_func` uses GTK's `GtkTreeListModelCreateModelFunc` signature
// `GListModel *(*)(gpointer item, gpointer user_data)` and is passed
// through as that exact typed function pointer (no bit-cast). GtkTreeListModel
// calls it lazily — once per row, only when that row is first expanded —
// to obtain the child model (or NULL for a leaf). The returned model is
// consumed with transfer-full, and `gtk_tree_list_model_new` also takes
// ownership of `root_model` (transfer full).
//
// `user_data` / `user_destroy` are GTK's own notified-lifetime hooks for
// the create-func data: the Swift side retains a `LazyTreeContext` and
// passes a destroy notify that releases it when the tree model is
// finalized, so the model owns its callback data independently of the
// factory (no reliance on factory-vs-model teardown order).

static inline gpointer
gtk_swift_tree_list_model_new(gpointer root_model,
                              GtkTreeListModelCreateModelFunc create_func,
                              gpointer user_data,
                              GDestroyNotify user_destroy) {
    return (gpointer)gtk_tree_list_model_new(
        G_LIST_MODEL(root_model),
        FALSE, // passthrough: list items are GtkTreeListRow wrappers
        FALSE, // autoexpand: keep everything collapsed initially
        create_func,
        user_data,
        user_destroy);
}

// The underlying user item (a GtkStringObject in our usage) wrapped by a
// GtkTreeListRow. Returns a NEW reference (transfer-full per the GTK
// annotation) — the caller must g_object_unref it after use.
static inline gpointer
gtk_swift_tree_list_row_get_item(gpointer row) {
    return (gpointer)gtk_tree_list_row_get_item(GTK_TREE_LIST_ROW(row));
}

static inline GtkWidget *
gtk_swift_tree_expander_new(void) {
    return gtk_tree_expander_new();
}

static inline void
gtk_swift_tree_expander_set_list_row(GtkWidget *expander, gpointer row) {
    gtk_tree_expander_set_list_row(GTK_TREE_EXPANDER(expander),
                                   row ? GTK_TREE_LIST_ROW(row) : NULL);
}

static inline void
gtk_swift_tree_expander_set_child(GtkWidget *expander, GtkWidget *child) {
    gtk_tree_expander_set_child(GTK_TREE_EXPANDER(expander), child);
}

static inline GtkWidget *
gtk_swift_tree_expander_get_child(GtkWidget *expander) {
    return gtk_tree_expander_get_child(GTK_TREE_EXPANDER(expander));
}

// --- GtkGridView shims ---

static inline GtkWidget *
gtk_swift_grid_view_new(gpointer model, gpointer factory) {
    return gtk_grid_view_new(GTK_SELECTION_MODEL(model),
                             GTK_LIST_ITEM_FACTORY(factory));
}

static inline void
gtk_swift_grid_view_set_min_columns(GtkWidget *view, guint min_columns) {
    gtk_grid_view_set_min_columns(GTK_GRID_VIEW(view), min_columns);
}

static inline void
gtk_swift_grid_view_set_max_columns(GtkWidget *view, guint max_columns) {
    gtk_grid_view_set_max_columns(GTK_GRID_VIEW(view), max_columns);
}

// --- GtkOrientable ---

static inline void
gtk_swift_orientable_set_orientation(GtkWidget *widget, GtkOrientation orientation) {
    gtk_orientable_set_orientation(GTK_ORIENTABLE(widget), orientation);
}

// --- GtkCustomLayout (flexible HStack equal-division) ---
//
// A GtkLayoutManager driven by plain C callbacks — no GObject subclass.
// The measure/allocate/request-mode funcs receive the container widget
// (not user_data); per-stack config is stashed on the widget via
// g_object_set_data and read back Swift-side. The func pointers are
// passed as their real GtkCustom*Func types (no bit-cast).

static inline gpointer
gtk_swift_custom_layout_new(GtkCustomRequestModeFunc request_mode,
                            GtkCustomMeasureFunc measure,
                            GtkCustomAllocateFunc allocate) {
    return (gpointer)gtk_custom_layout_new(request_mode, measure, allocate);
}

static inline void
gtk_swift_widget_set_layout_manager(GtkWidget *widget, gpointer manager) {
    // Takes ownership (transfer full) of the manager.
    gtk_widget_set_layout_manager(widget, GTK_LAYOUT_MANAGER(manager));
}

// Allocate a child at (x, y) with the given size. In GTK4 a child's
// position comes from a transform, not a GtkAllocation rect; a fresh
// translate is built per call and consumed transfer-full by
// gtk_widget_allocate.
static inline void
gtk_swift_allocate_child(GtkWidget *child, int x, int y,
                         int width, int height, int baseline) {
    graphene_point_t p = GRAPHENE_POINT_INIT((float)x, (float)y);
    GskTransform *t = gsk_transform_translate(NULL, &p);
    gtk_widget_allocate(child, width, height, baseline, t);
}

static inline GtkWidget *gtk_swift_widget_root(GtkWidget *widget) {
    GtkRoot *root = gtk_widget_get_root(widget);
    return root && GTK_IS_WIDGET(root) ? GTK_WIDGET(root) : widget;
}

static inline gboolean gtk_swift_widget_compute_point(GtkWidget *from, GtkWidget *to,
                                                       double x, double y,
                                                       double *result_x, double *result_y) {
    graphene_point_t point = GRAPHENE_POINT_INIT((float)x, (float)y);
    graphene_point_t result;
    gboolean success = gtk_widget_compute_point(from, to, &point, &result);
    if (success) { *result_x = result.x; *result_y = result.y; }
    return success;
}

static inline void gtk_swift_emit_motion_enter(GtkEventController *controller, double x, double y) {
    g_signal_emit_by_name(controller, "enter", x, y);
}
static inline void gtk_swift_emit_motion(GtkEventController *controller, double x, double y) {
    g_signal_emit_by_name(controller, "motion", x, y);
}
static inline void gtk_swift_emit_motion_leave(GtkEventController *controller) {
    g_signal_emit_by_name(controller, "leave");
}

// --- GtkPaned shims ---

static inline void
gtk_swift_paned_set_start_child(GtkWidget *paned, GtkWidget *child) {
    gtk_paned_set_start_child(GTK_PANED(paned), child);
}

static inline void
gtk_swift_paned_set_end_child(GtkWidget *paned, GtkWidget *child) {
    gtk_paned_set_end_child(GTK_PANED(paned), child);
}

static inline void
gtk_swift_paned_set_position(GtkWidget *paned, int position) {
    gtk_paned_set_position(GTK_PANED(paned), position);
}

static inline void
gtk_swift_paned_set_shrink_start_child(GtkWidget *paned, gboolean shrink) {
    gtk_paned_set_shrink_start_child(GTK_PANED(paned), shrink);
}

static inline void
gtk_swift_paned_set_shrink_end_child(GtkWidget *paned, gboolean shrink) {
    gtk_paned_set_shrink_end_child(GTK_PANED(paned), shrink);
}

static inline int
gtk_swift_paned_get_position(GtkWidget *paned) {
    return gtk_paned_get_position(GTK_PANED(paned));
}

// --- GtkDrawingArea shims ---

static inline void
gtk_swift_drawing_area_set_content_width(GtkWidget *area, int width) {
    gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(area), width);
}

static inline void
gtk_swift_drawing_area_set_content_height(GtkWidget *area, int height) {
    gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(area), height);
}

typedef void (*GtkSwiftDrawFunc)(GtkWidget *widget, cairo_t *cr,
                                  int width, int height, gpointer user_data);

static inline void
gtk_swift_drawing_area_set_draw_func(GtkWidget *area,
                                      GtkSwiftDrawFunc func,
                                      gpointer user_data,
                                      GDestroyNotify destroy) {
    gtk_drawing_area_set_draw_func(
        GTK_DRAWING_AREA(area),
        (GtkDrawingAreaDrawFunc)func,
        user_data,
        destroy);
}

static inline void
gtk_swift_widget_queue_draw(GtkWidget *widget) {
    gtk_widget_queue_draw(widget);
}

// --- Cairo drawing shims ---

static inline void
gtk_swift_cairo_set_source_rgb(cairo_t *cr, double r, double g, double b) {
    cairo_set_source_rgb(cr, r, g, b);
}

static inline void
gtk_swift_cairo_set_source_rgba(cairo_t *cr, double r, double g, double b, double a) {
    cairo_set_source_rgba(cr, r, g, b, a);
}

static inline void
gtk_swift_cairo_set_line_width(cairo_t *cr, double width) {
    cairo_set_line_width(cr, width);
}

static inline void
gtk_swift_cairo_set_line_cap(cairo_t *cr, cairo_line_cap_t cap) {
    cairo_set_line_cap(cr, cap);
}

static inline void
gtk_swift_cairo_set_line_join(cairo_t *cr, cairo_line_join_t join) {
    cairo_set_line_join(cr, join);
}

static inline void
gtk_swift_cairo_move_to(cairo_t *cr, double x, double y) {
    cairo_move_to(cr, x, y);
}

static inline void
gtk_swift_cairo_line_to(cairo_t *cr, double x, double y) {
    cairo_line_to(cr, x, y);
}

static inline void
gtk_swift_cairo_rectangle(cairo_t *cr, double x, double y, double w, double h) {
    cairo_rectangle(cr, x, y, w, h);
}

static inline void
gtk_swift_cairo_arc(cairo_t *cr, double xc, double yc, double radius,
                     double angle1, double angle2) {
    cairo_arc(cr, xc, yc, radius, angle1, angle2);
}

static inline void
gtk_swift_cairo_stroke(cairo_t *cr) {
    cairo_stroke(cr);
}

/// Set the dash pattern on a Cairo context. Pass n=0 and NULL to clear
/// (solid stroke). `dashes` is an alternating array of on/off lengths.
/// `offset` is the starting position into the pattern.
static inline void
gtk_swift_cairo_set_dash(cairo_t *cr, const double *dashes, int n, double offset) {
    cairo_set_dash(cr, dashes, n, offset);
}

static inline void
gtk_swift_cairo_fill(cairo_t *cr) {
    cairo_fill(cr);
}

static inline void
gtk_swift_cairo_paint(cairo_t *cr) {
    cairo_paint(cr);
}

static inline void
gtk_swift_cairo_save(cairo_t *cr) {
    cairo_save(cr);
}

static inline void
gtk_swift_cairo_restore(cairo_t *cr) {
    cairo_restore(cr);
}

static inline void
gtk_swift_cairo_scale(cairo_t *cr, double sx, double sy) {
    cairo_scale(cr, sx, sy);
}

static inline void
gtk_swift_cairo_curve_to(cairo_t *cr, double x1, double y1,
                          double x2, double y2, double x3, double y3) {
    cairo_curve_to(cr, x1, y1, x2, y2, x3, y3);
}

static inline void
gtk_swift_cairo_close_path(cairo_t *cr) {
    cairo_close_path(cr);
}

static inline void
gtk_swift_cairo_arc_negative(cairo_t *cr, double xc, double yc, double radius,
                              double angle1, double angle2) {
    cairo_arc_negative(cr, xc, yc, radius, angle1, angle2);
}

static inline void
gtk_swift_cairo_new_path(cairo_t *cr) {
    cairo_new_path(cr);
}

static inline void
gtk_swift_cairo_set_source_surface(cairo_t *cr, cairo_surface_t *surface,
                                    double x, double y) {
    cairo_set_source_surface(cr, surface, x, y);
}

// --- Window titlebar helpers ---

/// Set or clear the window titlebar. Pass NULL to remove a custom titlebar.
static inline void
gtk_swift_set_root_window_titlebar(GtkWidget *widget, GtkWidget *titlebar) {
    GtkRoot *root = gtk_widget_get_root(widget);
    if (root && GTK_IS_WINDOW(root)) {
        gtk_window_set_titlebar(GTK_WINDOW(root), titlebar);
    }
}

// --- GtkSwitch shims ---

static inline GtkWidget *
gtk_swift_switch_new(void) {
    return gtk_switch_new();
}

static inline void
gtk_swift_switch_set_active(GtkWidget *sw, gboolean active) {
    gtk_switch_set_active(GTK_SWITCH(sw), active);
}

static inline gboolean
gtk_swift_switch_get_active(GtkWidget *sw) {
    return gtk_switch_get_active(GTK_SWITCH(sw));
}

// --- GtkGestureSingle shim ---

static inline void
gtk_swift_gesture_single_set_button(GtkGesture *gesture, guint button) {
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(gesture), button);
}

// --- GtkPopover shims ---

static inline void
gtk_swift_popover_set_pointing_to(GtkWidget *popover, int x, int y, int w, int h) {
    GdkRectangle rect = { x, y, w, h };
    gtk_popover_set_pointing_to(GTK_POPOVER(popover), &rect);
}

static inline void
gtk_swift_popover_popup(GtkWidget *popover) {
    gtk_popover_popup(GTK_POPOVER(popover));
}

static inline void
gtk_swift_popover_set_child(GtkWidget *popover, GtkWidget *child) {
    gtk_popover_set_child(GTK_POPOVER(popover), child);
}

static inline void
gtk_swift_popover_popdown(GtkWidget *popover) {
    // GTK_IS_POPOVER guards against a stale pointer (e.g. a menu-item tap
    // that triggers a synchronous rebuild freeing the popover before the
    // deferred popdown handler runs).
    if (GTK_IS_POPOVER(popover)) {
        gtk_popover_popdown(GTK_POPOVER(popover));
    }
}

// --- GtkWindow shims ---

static inline void
gtk_swift_window_set_modal(GtkWidget *window, gboolean modal) {
    gtk_window_set_modal(GTK_WINDOW(window), modal);
}

static inline void
gtk_swift_window_set_transient_for(GtkWidget *window, GtkWidget *parent) {
    gtk_window_set_transient_for(GTK_WINDOW(window), GTK_WINDOW(parent));
}

static inline void
gtk_swift_window_set_child(GtkWidget *window, GtkWidget *child) {
    gtk_window_set_child(GTK_WINDOW(window), child);
}

static inline GtkWidget *
gtk_swift_window_get_child(GtkWidget *window) {
    return gtk_window_get_child(GTK_WINDOW(window));
}

static inline void
gtk_swift_window_fullscreen(GtkWidget *window) {
    gtk_window_fullscreen(GTK_WINDOW(window));
}

static inline void
gtk_swift_window_unfullscreen(GtkWidget *window) {
    gtk_window_unfullscreen(GTK_WINDOW(window));
}

static inline void
gtk_swift_window_destroy(GtkWidget *window) {
    gtk_window_destroy(GTK_WINDOW(window));
}

// --- Pango attribute shims for GtkLabel ---

static inline void
gtk_swift_label_set_underline(GtkWidget *label, gboolean underline) {
    PangoAttrList *attrs = gtk_label_get_attributes(GTK_LABEL(label));
    PangoAttrList *newAttrs = attrs ? pango_attr_list_copy(attrs) : pango_attr_list_new();
    pango_attr_list_change(newAttrs,
        pango_attr_underline_new(underline ? PANGO_UNDERLINE_SINGLE : PANGO_UNDERLINE_NONE));
    gtk_label_set_attributes(GTK_LABEL(label), newAttrs);
    pango_attr_list_unref(newAttrs);
}

static inline void
gtk_swift_label_set_strikethrough(GtkWidget *label, gboolean strikethrough) {
    PangoAttrList *attrs = gtk_label_get_attributes(GTK_LABEL(label));
    PangoAttrList *newAttrs = attrs ? pango_attr_list_copy(attrs) : pango_attr_list_new();
    pango_attr_list_change(newAttrs, pango_attr_strikethrough_new(strikethrough));
    gtk_label_set_attributes(GTK_LABEL(label), newAttrs);
    pango_attr_list_unref(newAttrs);
}

// --- GtkAlertDialog shims (GTK 4.10+) ---

static inline gpointer
gtk_swift_alert_dialog_new(const char *message) {
    return (gpointer)gtk_alert_dialog_new("%s", message);
}

static inline void
gtk_swift_alert_dialog_set_detail(gpointer dialog, const char *detail) {
    gtk_alert_dialog_set_detail(GTK_ALERT_DIALOG(dialog), detail);
}

static inline void
gtk_swift_alert_dialog_set_buttons(gpointer dialog,
                                    const char * const *labels) {
    gtk_alert_dialog_set_buttons(GTK_ALERT_DIALOG(dialog), labels);
}

static inline void
gtk_swift_alert_dialog_set_cancel_button(gpointer dialog, int button) {
    gtk_alert_dialog_set_cancel_button(GTK_ALERT_DIALOG(dialog), button);
}

static inline void
gtk_swift_alert_dialog_set_default_button(gpointer dialog, int button) {
    gtk_alert_dialog_set_default_button(GTK_ALERT_DIALOG(dialog), button);
}

static inline void
gtk_swift_alert_dialog_choose(gpointer dialog,
                               GtkWindow *parent,
                               GCancellable *cancellable,
                               GAsyncReadyCallback callback,
                               gpointer user_data) {
    gtk_alert_dialog_choose(GTK_ALERT_DIALOG(dialog), parent,
                            cancellable, callback, user_data);
}

static inline int
gtk_swift_alert_dialog_choose_finish(gpointer dialog,
                                      GAsyncResult *result,
                                      GError **error) {
    return gtk_alert_dialog_choose_finish(GTK_ALERT_DIALOG(dialog),
                                          result, error);
}

// --- GtkFileDialog shims (GTK 4.10+) ---

static inline gpointer
gtk_swift_file_dialog_new(void) {
    return (gpointer)gtk_file_dialog_new();
}

static inline void
gtk_swift_file_dialog_set_title(gpointer dialog, const char *title) {
    gtk_file_dialog_set_title(GTK_FILE_DIALOG(dialog), title);
}

static inline void
gtk_swift_file_dialog_set_initial_name(gpointer dialog, const char *name) {
    gtk_file_dialog_set_initial_name(GTK_FILE_DIALOG(dialog), name);
}

static inline void
gtk_swift_file_dialog_set_initial_folder(gpointer dialog, gpointer folder) {
    gtk_file_dialog_set_initial_folder(GTK_FILE_DIALOG(dialog), G_FILE(folder));
}

static inline void
gtk_swift_file_dialog_set_filters(gpointer dialog, gpointer filters) {
    gtk_file_dialog_set_filters(GTK_FILE_DIALOG(dialog), G_LIST_MODEL(filters));
}

static inline void
gtk_swift_file_dialog_select_folder(gpointer dialog,
                                     GtkWindow *parent,
                                     GCancellable *cancellable,
                                     GAsyncReadyCallback callback,
                                     gpointer user_data) {
    gtk_file_dialog_select_folder(GTK_FILE_DIALOG(dialog), parent,
                                  cancellable, callback, user_data);
}

static inline gpointer
gtk_swift_file_dialog_select_folder_finish(gpointer dialog,
                                            GAsyncResult *result,
                                            GError **error) {
    return (gpointer)gtk_file_dialog_select_folder_finish(
        GTK_FILE_DIALOG(dialog), result, error);
}

static inline void
gtk_swift_file_dialog_open(gpointer dialog,
                            GtkWindow *parent,
                            GCancellable *cancellable,
                            GAsyncReadyCallback callback,
                            gpointer user_data) {
    gtk_file_dialog_open(GTK_FILE_DIALOG(dialog), parent,
                         cancellable, callback, user_data);
}

static inline gpointer
gtk_swift_file_dialog_open_finish(gpointer dialog,
                                   GAsyncResult *result,
                                   GError **error) {
    return (gpointer)gtk_file_dialog_open_finish(
        GTK_FILE_DIALOG(dialog), result, error);
}

static inline void
gtk_swift_file_dialog_save(gpointer dialog,
                            GtkWindow *parent,
                            GCancellable *cancellable,
                            GAsyncReadyCallback callback,
                            gpointer user_data) {
    gtk_file_dialog_save(GTK_FILE_DIALOG(dialog), parent,
                         cancellable, callback, user_data);
}

static inline gpointer
gtk_swift_file_dialog_save_finish(gpointer dialog,
                                   GAsyncResult *result,
                                   GError **error) {
    return (gpointer)gtk_file_dialog_save_finish(
        GTK_FILE_DIALOG(dialog), result, error);
}

// --- GtkFileFilter shims ---

static inline gpointer
gtk_swift_file_filter_new(void) {
    return (gpointer)gtk_file_filter_new();
}

static inline void
gtk_swift_file_filter_set_name(gpointer filter, const char *name) {
    gtk_file_filter_set_name(GTK_FILE_FILTER(filter), name);
}

static inline void
gtk_swift_file_filter_add_suffix(gpointer filter, const char *suffix) {
    gtk_file_filter_add_suffix(GTK_FILE_FILTER(filter), suffix);
}

// --- GListStore shims (for file filter lists) ---

static inline gpointer
gtk_swift_list_store_new_for_file_filters(void) {
    return (gpointer)g_list_store_new(GTK_TYPE_FILE_FILTER);
}

static inline void
gtk_swift_list_store_append_object(gpointer store, gpointer object) {
    g_list_store_append(G_LIST_STORE(store), object);
}

// --- GFile shims ---

static inline const char *
gtk_swift_gfile_get_path(gpointer file) {
    return g_file_get_path(G_FILE(file));
}

static inline gpointer
gtk_swift_gfile_new_for_path(const char *path) {
    return (gpointer)g_file_new_for_path(path);
}

// --- Window activation shim ---

static inline gboolean
gtk_swift_window_is_active(GtkWidget *window) {
    return gtk_window_is_active(GTK_WINDOW(window));
}

// --- Menu bar shims ---

static inline GtkWidget *
gtk_swift_popover_menu_bar_new_from_model(gpointer menu_model) {
    return gtk_popover_menu_bar_new_from_model(G_MENU_MODEL(menu_model));
}

static inline void
gtk_swift_action_set_enabled(gpointer action, gboolean enabled) {
    g_simple_action_set_enabled(G_SIMPLE_ACTION(action), enabled);
}

// --- Drop target shims ---

/// Create a GtkDropTarget for file list drops.
/// GDK_TYPE_FILE_LIST is a boxed type that wraps a GSList of GFile*.
static inline GtkDropTarget *
gtk_swift_drop_target_new_for_file_list(void) {
    return gtk_drop_target_new(GDK_TYPE_FILE_LIST, GDK_ACTION_COPY);
}

/// Get the GValue from a GtkDropTarget drop signal's GdkDrop.
/// The value is valid only during the "drop" signal handler.
static inline const GValue *
gtk_swift_drop_target_get_value(GtkDropTarget *target) {
    return gtk_drop_target_get_value(target);
}

/// Extract the GSList of GFile* from a GdkFileList boxed value.
static inline GSList *
gtk_swift_file_list_get_gslist(const GValue *value) {
    GdkFileList *file_list = (GdkFileList *)g_value_get_boxed(value);
    if (!file_list) return NULL;
    return gdk_file_list_get_files(file_list);
}

/// Get the number of items in a GSList.
static inline guint
gtk_swift_gslist_length(GSList *list) {
    return g_slist_length(list);
}

/// Get the nth data pointer from a GSList (for iteration).
static inline gpointer
gtk_swift_gslist_nth_data(GSList *list, guint n) {
    return g_slist_nth_data(list, n);
}

/// Get the widget attached to a GtkEventController (or subclass like
/// GtkDropTarget). Returns NULL if not attached. Used by the drop-target
/// Swift wrapper to ref the controlled widget for the duration of a drop
/// dispatch so SwiftOpenUI's @State-triggered view rebuild can't destroy
/// the widget before GTK's post-drop state-flag cleanup runs on it.
static inline GtkWidget *
gtk_swift_event_controller_get_widget(gpointer controller) {
    return gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(controller));
}

/// Return the currently active GtkWindow for the default GApplication, or
/// NULL if there is no default application or no active window. Used to
/// supply a parent window to GtkFileDialog / GtkAlertDialog — without a
/// parent, GTK's internal dialog widgets (sidebar GtkListBox, trash
/// monitor icon, etc.) aren't properly rooted and emit Gtk-CRITICAL
/// assertions during dialog realization on GTK 4.14.
static inline GtkWindow *
gtk_swift_get_active_window(void) {
    GApplication *app = g_application_get_default();
    if (!app || !GTK_IS_APPLICATION(app)) return NULL;
    return gtk_application_get_active_window(GTK_APPLICATION(app));
}


// --- GtkVideo shims (used by the VideoPlayer renderer) ---

/// GTK's GStreamer backend aborts if playbin3 is unavailable. Probe the already
/// loaded GStreamer library before creating a media file, without making it a
/// dependency of GTK builds that use a different media backend.
static inline const char *
gtk_swift_video_prerequisite_error(void) {
#ifdef __linux__
    const char *backend = g_getenv("GTK_MEDIA");
    if (backend && strcmp(backend, "gstreamer") != 0) return NULL;
    typedef gboolean (*InitCheck)(int *, char ***, GError **);
    typedef gpointer (*FindFactory)(const char *);
    InitCheck init_check = (InitCheck)dlsym(RTLD_DEFAULT, "gst_init_check");
    FindFactory find_factory = (FindFactory)dlsym(RTLD_DEFAULT, "gst_element_factory_find");
    if (!init_check || !find_factory) return NULL;
    if (!init_check(NULL, NULL, NULL)) return "GStreamer could not initialize playback.";
    gpointer factory = find_factory("playbin3");
    if (!factory) {
        return "Video playback is unavailable: GStreamer's playbin3 plugin is missing. "
               "Install the GStreamer base plugins or launch from your configured development environment.";
    }
    g_object_unref(factory);
#endif
    return NULL;
}

static inline GtkWidget *
gtk_swift_video_new(void) {
    GtkWidget *video = gtk_video_new();
    gtk_widget_set_hexpand(video, TRUE);
    gtk_widget_set_vexpand(video, TRUE);
    return video;
}

static inline void
gtk_swift_video_open_uri(GtkWidget *video, const char *uri, int autoplay) {
    GFile *file = g_file_new_for_uri(uri);
    gtk_video_set_autoplay(GTK_VIDEO(video), autoplay ? TRUE : FALSE);
    gtk_video_set_file(GTK_VIDEO(video), file);
    g_object_unref(file);
}

static inline void
gtk_swift_video_clear(GtkWidget *video) {
    gtk_video_set_file(GTK_VIDEO(video), NULL);
}

static inline GtkMediaStream *
gtk_swift_video_stream(GtkWidget *video) {
    return gtk_video_get_media_stream(GTK_VIDEO(video));
}

// --- Color scheme detection ---

/// Whether the desktop prefers a dark appearance, per the XDG settings portal.
///
/// Returns 1 for dark, 0 for light, -1 if the portal is unavailable or states
/// no preference. This is the only place the preference reliably appears:
/// GtkSettings does not learn it (a COSMIC or GNOME session set to dark still
/// reports `gtk-theme-name = Adwaita` and
/// `gtk-application-prefer-dark-theme = FALSE`), and the GNOME GSettings key
/// is not set outside GNOME. libadwaita's AdwStyleManager reads this portal;
/// SwiftOpenUI does not link libadwaita, so it reads it directly.
///
/// The reply is `(v)` wrapping a variant wrapping a `u`:
/// 0 = no preference, 1 = prefer dark, 2 = prefer light.
static inline int
gtk_swift_portal_prefers_dark(void) {
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
    if (!bus) return -1;

    GVariant *reply = g_dbus_connection_call_sync(
        bus,
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Settings",
        "Read",
        g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE,
        1000 /* ms; never block startup on a missing portal */,
        NULL, NULL);
    g_object_unref(bus);
    if (!reply) return -1;

    GVariant *inner = NULL;
    g_variant_get(reply, "(v)", &inner);

    guint32 value = 0;
    int known = 0;
    if (inner) {
        GVariant *scalar = g_variant_is_of_type(inner, G_VARIANT_TYPE_VARIANT)
            ? g_variant_get_variant(inner)
            : g_variant_ref(inner);
        if (scalar && g_variant_is_of_type(scalar, G_VARIANT_TYPE_UINT32)) {
            value = g_variant_get_uint32(scalar);
            known = 1;
        }
        if (scalar) g_variant_unref(scalar);
        g_variant_unref(inner);
    }
    g_variant_unref(reply);

    if (!known) return -1;
    if (value == 1) return 1;
    if (value == 2) return 0;
    return -1; /* 0 = no preference */
}

/// Whether to render dark.
///
/// Prefers the XDG appearance portal, and falls back to what GtkSettings
/// exposes: the explicit `gtk-application-prefer-dark-theme` flag, then the
/// conventional `-dark` suffix on the theme name.
static inline int
gtk_swift_prefers_dark_theme(void) {
    int portal = gtk_swift_portal_prefers_dark();
    if (portal >= 0) return portal;

    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) return 0;

    gboolean prefer_dark = FALSE;
    char *theme_name = NULL;
    g_object_get(settings,
                 "gtk-application-prefer-dark-theme", &prefer_dark,
                 "gtk-theme-name", &theme_name,
                 NULL);

    int dark = prefer_dark ? 1 : 0;
    if (!dark && theme_name) {
        char *lowered = g_ascii_strdown(theme_name, -1);
        dark = (lowered && strstr(lowered, "dark") != NULL) ? 1 : 0;
        g_free(lowered);
    }
    g_free(theme_name);
    return dark;
}

/// Tell GTK to use the dark variant of its theme.
///
/// Needed alongside the SwiftOpenUI-side color scheme: GTK draws its own
/// widget chrome from GtkSettings, which does not learn the portal preference
/// on its own. Without this, resolving the scheme to dark would paint dark
/// SwiftOpenUI colors onto light GTK chrome.
static inline void
gtk_swift_set_prefer_dark_theme(int dark) {
    GtkSettings *settings = gtk_settings_get_default();
    if (!settings) return;
    g_object_set(settings, "gtk-application-prefer-dark-theme", dark ? TRUE : FALSE, NULL);
}

// --- Theme palette ---

/// Look up a named color from the current GTK theme.
///
/// Returns non-zero when the theme defines `name`. Prefer the libadwaita-style
/// names (`window_bg_color`, `card_bg_color`, `accent_color`): on a COSMIC or
/// GNOME dark session those carry the real values, while the legacy GTK3 names
/// (`theme_bg_color`, `theme_fg_color`) are often left at stale light defaults.
static inline int
gtk_swift_theme_lookup_color(const char *name, double *r, double *g, double *b, double *a) {
    GtkWidget *probe = gtk_label_new("");
    g_object_ref_sink(probe);
    GtkStyleContext *ctx = gtk_widget_get_style_context(probe);
    GdkRGBA rgba;
    int found = gtk_style_context_lookup_color(ctx, name, &rgba) ? 1 : 0;
    if (found) { *r = rgba.red; *g = rgba.green; *b = rgba.blue; *a = rgba.alpha; }
    g_object_unref(probe);
    return found;
}

/// The theme's primary text color, as GTK would paint a plain label.
///
/// Unlike the named-color table this always reflects the stylesheet actually in
/// force, so it is the reliable source for the foreground.
static inline void
gtk_swift_theme_foreground(double *r, double *g, double *b, double *a) {
    GtkWidget *probe = gtk_label_new("");
    g_object_ref_sink(probe);
    GdkRGBA rgba;
    gtk_widget_get_color(probe, &rgba);
    *r = rgba.red; *g = rgba.green; *b = rgba.blue; *a = rgba.alpha;
    g_object_unref(probe);
}
