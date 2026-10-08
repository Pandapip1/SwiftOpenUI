#pragma once

#include <adwaita.h>

static inline GtkWidget *swift_adw_view_stack_new(void) {
    return GTK_WIDGET(adw_view_stack_new());
}

static inline AdwViewStackPage *swift_adw_view_stack_add_titled(
    GtkWidget *stack, GtkWidget *child, const char *name, const char *title) {
    return adw_view_stack_add_titled(ADW_VIEW_STACK(stack), child, name, title);
}

static inline void swift_adw_view_stack_set_visible_child_name(GtkWidget *stack, const char *name) {
    adw_view_stack_set_visible_child_name(ADW_VIEW_STACK(stack), name);
}

static inline const char *swift_adw_view_stack_get_visible_child_name(GtkWidget *stack) {
    return adw_view_stack_get_visible_child_name(ADW_VIEW_STACK(stack));
}

static inline GtkWidget *swift_adw_view_stack_get_visible_child(GtkWidget *stack) {
    return adw_view_stack_get_visible_child(ADW_VIEW_STACK(stack));
}

static inline GtkWidget *swift_adw_view_stack_get_child_by_name(GtkWidget *stack, const char *name) {
    return adw_view_stack_get_child_by_name(ADW_VIEW_STACK(stack), name);
}

static inline void swift_adw_view_stack_set_visible_child(GtkWidget *stack, GtkWidget *child) {
    adw_view_stack_set_visible_child(ADW_VIEW_STACK(stack), child);
}

static inline GtkWidget *swift_adw_view_switcher_new(GtkWidget *stack) {
    AdwViewSwitcher *switcher = ADW_VIEW_SWITCHER(adw_view_switcher_new());
    adw_view_switcher_set_stack(switcher, ADW_VIEW_STACK(stack));
    return GTK_WIDGET(switcher);
}

static inline GtkWidget *swift_adw_view_switcher_sidebar_new(GtkWidget *stack) {
    AdwViewSwitcherSidebar *sidebar = ADW_VIEW_SWITCHER_SIDEBAR(adw_view_switcher_sidebar_new());
    adw_view_switcher_sidebar_set_stack(sidebar, ADW_VIEW_STACK(stack));
    return GTK_WIDGET(sidebar);
}

static inline GtkWidget *swift_adw_tab_view_new(void) {
    return GTK_WIDGET(adw_tab_view_new());
}

static inline AdwTabPage *swift_adw_tab_view_append(GtkWidget *view, GtkWidget *child) {
    return adw_tab_view_append(ADW_TAB_VIEW(view), child);
}

static inline void swift_adw_tab_page_set_title(AdwTabPage *page, const char *title) {
    adw_tab_page_set_title(page, title);
}

static inline void swift_adw_tab_view_set_page_pinned(GtkWidget *view, AdwTabPage *page, gboolean pinned) {
    adw_tab_view_set_page_pinned(ADW_TAB_VIEW(view), page, pinned);
}

static inline void swift_adw_tab_view_set_selected_page(GtkWidget *view, AdwTabPage *page) {
    adw_tab_view_set_selected_page(ADW_TAB_VIEW(view), page);
}

static inline AdwTabPage *swift_adw_tab_view_get_selected_page(GtkWidget *view) {
    return adw_tab_view_get_selected_page(ADW_TAB_VIEW(view));
}

static inline int swift_adw_tab_view_get_n_pages(GtkWidget *view) {
    return adw_tab_view_get_n_pages(ADW_TAB_VIEW(view));
}

static inline AdwTabPage *swift_adw_tab_view_get_nth_page(GtkWidget *view, int position) {
    return adw_tab_view_get_nth_page(ADW_TAB_VIEW(view), position);
}

static inline gboolean swift_adw_tab_page_get_pinned(AdwTabPage *page) {
    return adw_tab_page_get_pinned(page);
}

static inline void swift_adw_tab_view_close_page(GtkWidget *view, AdwTabPage *page) {
    adw_tab_view_close_page(ADW_TAB_VIEW(view), page);
}

static inline GtkWidget *swift_adw_tab_bar_new(GtkWidget *view) {
    AdwTabBar *bar = ADW_TAB_BAR(adw_tab_bar_new());
    adw_tab_bar_set_view(bar, ADW_TAB_VIEW(view));
    adw_tab_bar_set_autohide(bar, FALSE);
    adw_tab_bar_set_expand_tabs(bar, TRUE);
    return GTK_WIDGET(bar);
}

static inline GtkWidget *swift_adw_tab_bar_get_view(GtkWidget *bar) {
    return GTK_WIDGET(adw_tab_bar_get_view(ADW_TAB_BAR(bar)));
}
