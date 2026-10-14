#include "CGTKWidgets.h"

typedef struct {
    GtkWidget parent_instance;
    GtkWidget *child;
    double ratio;
} GtkSwiftAspectLayout;

typedef GtkWidgetClass GtkSwiftAspectLayoutClass;

G_DEFINE_TYPE(GtkSwiftAspectLayout, gtk_swift_aspect_layout, GTK_TYPE_WIDGET)

static GtkSizeRequestMode
gtk_swift_aspect_layout_request_mode(GtkWidget *widget) {
    (void)widget;
    return GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH;
}

static void
gtk_swift_aspect_layout_measure(GtkWidget *widget, GtkOrientation orientation,
                                int for_size, int *minimum, int *natural,
                                int *minimum_baseline, int *natural_baseline) {
    GtkSwiftAspectLayout *self = (GtkSwiftAspectLayout *)widget;
    *minimum_baseline = *natural_baseline = -1;
    if (!self->child) { *minimum = *natural = 0; return; }

    if (orientation == GTK_ORIENTATION_VERTICAL && for_size >= 0) {
        int height = MAX(1, (int)((double)for_size / self->ratio + 0.5));
        *minimum = *natural = height;
        return;
    }

    gtk_widget_measure(self->child, orientation, for_size,
                       minimum, natural, minimum_baseline, natural_baseline);
    if (orientation == GTK_ORIENTATION_VERTICAL) {
        int child_min_width = 0, child_nat_width = 0;
        gtk_widget_measure(self->child, GTK_ORIENTATION_HORIZONTAL, -1,
                           &child_min_width, &child_nat_width, NULL, NULL);
        *minimum = MAX(1, (int)((double)child_min_width / self->ratio + 0.5));
        *natural = MAX(*minimum, (int)((double)child_nat_width / self->ratio + 0.5));
    }
}

static void
gtk_swift_aspect_layout_size_allocate(GtkWidget *widget, int width, int height, int baseline) {
    GtkSwiftAspectLayout *self = (GtkSwiftAspectLayout *)widget;
    if (self->child) gtk_widget_allocate(self->child, width, height, baseline, NULL);
}

static void
gtk_swift_aspect_layout_dispose(GObject *object) {
    GtkSwiftAspectLayout *self = (GtkSwiftAspectLayout *)object;
    if (self->child) {
        gtk_widget_unparent(self->child);
        self->child = NULL;
    }
    G_OBJECT_CLASS(gtk_swift_aspect_layout_parent_class)->dispose(object);
}

static void
gtk_swift_aspect_layout_class_init(GtkSwiftAspectLayoutClass *klass) {
    GtkWidgetClass *widget_class = GTK_WIDGET_CLASS(klass);
    GObjectClass *object_class = G_OBJECT_CLASS(klass);
    widget_class->get_request_mode = gtk_swift_aspect_layout_request_mode;
    widget_class->measure = gtk_swift_aspect_layout_measure;
    widget_class->size_allocate = gtk_swift_aspect_layout_size_allocate;
    object_class->dispose = gtk_swift_aspect_layout_dispose;
}

static void
gtk_swift_aspect_layout_init(GtkSwiftAspectLayout *self) {
    self->ratio = 1.0;
}

GtkWidget *
gtk_swift_aspect_layout_new(GtkWidget *child, double ratio) {
    GtkSwiftAspectLayout *self = g_object_new(gtk_swift_aspect_layout_get_type(), NULL);
    self->ratio = ratio > 0.0 ? ratio : 1.0;
    self->child = child;
    gtk_widget_set_parent(child, GTK_WIDGET(self));
    return GTK_WIDGET(self);
}
