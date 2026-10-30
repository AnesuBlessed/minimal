/* Native port of Minimal's existing GTK4/Cairo coverflow.
 * Geometry, controls and easing intentionally match the original picker. */
#include <gtk/gtk.h>
#include <json-c/json.h>
#include <math.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

typedef struct {
  char *path, *category, *stem;
} Item;
typedef struct {
  cairo_surface_t *surface;
  guint64 used;
} Cached;
typedef struct {
  int index;
  double x, y, w, h;
} Bounds;
typedef struct App App;
typedef struct {
  App *app;
  char *key, *path, *file;
  int w, h;
  cairo_surface_t *surface;
} Job;
struct App {
  GtkApplication *application;
  GtkWidget *window, *area;
  GPtrArray *items, *filtered, *categories;
  GHashTable *cache, *pending;
  GThreadPool *workers;
  char *helper, *cache_dir, *state_dir, *error;
  int index, category;
  double position, target, accent[3];
  guint tick;
  guint64 serial;
  gboolean alive, applying, self_test;
  Bounds bounds[17];
  int n_bounds;
};
static void prewarm(App *a);
static void rounded(cairo_t *cr, double x, double y, double w, double h,
                    double r) {
  r = fmin(r, fmin(w / 2, h / 2));
  cairo_new_sub_path(cr);
  cairo_arc(cr, x + w - r, y + r, r, -G_PI / 2, 0);
  cairo_arc(cr, x + w - r, y + h - r, r, 0, G_PI / 2);
  cairo_arc(cr, x + r, y + h - r, r, G_PI / 2, G_PI);
  cairo_arc(cr, x + r, y + r, r, G_PI, 3 * G_PI / 2);
  cairo_close_path(cr);
}
static char *xdg(const char *key, const char *fallback) {
  const char *v = g_getenv(key);
  return v && *v
             ? g_build_filename(v, "minimal", NULL)
             : g_build_filename(g_get_home_dir(), fallback, "minimal", NULL);
}
static char *read_text(const char *path) {
  char *s = NULL;
  if (!g_file_get_contents(path, &s, NULL, NULL))
    return g_strdup("");
  g_strstrip(s);
  return s;
}
static void cached_free(gpointer p) {
  Cached *c = p;
  if (c->surface)
    cairo_surface_destroy(c->surface);
  g_free(c);
}
static gboolean completed(gpointer data) {
  Job *j = data;
  App *a = j->app;
  g_hash_table_remove(a->pending, j->key);
  if (a->alive) {
    /* Both successful images and failures are cached to avoid repeated work. */
    if (g_hash_table_size(a->cache) >= 48) {
      GHashTableIter iter;
      gpointer k, v;
      guint64 oldest = G_MAXUINT64;
      char *victim = NULL;
      g_hash_table_iter_init(&iter, a->cache);
      while (g_hash_table_iter_next(&iter, &k, &v)) {
        Cached *c = v;
        if (c->used < oldest) {
          oldest = c->used;
          victim = k;
        }
      }
      if (victim)
        g_hash_table_remove(a->cache, victim);
    }
    Cached *c = g_new0(Cached, 1);
    c->surface = j->surface;
    c->used = ++a->serial;
    g_hash_table_replace(a->cache, g_strdup(j->key), c);
    if (a->area)
      gtk_widget_queue_draw(a->area);
  } else if (j->surface)
    cairo_surface_destroy(j->surface);
  g_free(j->key);
  g_free(j->path);
  g_free(j->file);
  g_free(j);
  return G_SOURCE_REMOVE;
}
static void load_job(gpointer data, gpointer unused) {
  (void)unused;
  Job *j = data;
  cairo_surface_t *s = cairo_image_surface_create_from_png(j->file);
  if (cairo_surface_status(s) != CAIRO_STATUS_SUCCESS) {
    cairo_surface_destroy(s);
    s = NULL;
    char w[20], h[20];
    g_snprintf(w, sizeof w, "%d", j->w);
    g_snprintf(h, sizeof h, "%d", j->h);
    char *argv[] = {j->app->helper, "thumbnail", j->path, j->file, w, h, NULL};
    int status = 0;
    if (g_spawn_sync(NULL, argv, NULL,
                     G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_STDERR_TO_DEV_NULL,
                     NULL, NULL, NULL, NULL, &status, NULL) &&
        g_spawn_check_wait_status(status, NULL)) {
      s = cairo_image_surface_create_from_png(j->file);
      if (cairo_surface_status(s) != CAIRO_STATUS_SUCCESS) {
        cairo_surface_destroy(s);
        s = NULL;
      }
    }
  }
  j->surface = s;
  g_idle_add(completed, j);
}
static cairo_surface_t *surface(App *a, Item *item, gboolean preview) {
  /* Source identity and nanosecond mtime prevent namesake/stale thumbnail
   * reuse. */
  struct stat st = {0};
  stat(item->path, &st);
  char *identity = g_strdup_printf(
      "%s:%lld:%s:%dx%d", item->path,
      (long long)st.st_mtim.tv_sec * 1000000000LL + st.st_mtim.tv_nsec,
      preview ? "preview" : "card", preview ? 340 : 240, preview ? 190 : 680);
  char *key = g_compute_checksum_for_string(G_CHECKSUM_SHA256, identity, -1);
  g_free(identity);
  Cached *cached = g_hash_table_lookup(a->cache, key);
  if (cached) {
    cached->used = ++a->serial;
    g_free(key);
    return cached->surface;
  }
  if (!g_hash_table_contains(a->pending, key) &&
      g_hash_table_size(a->pending) < 36) {
    Job *j = g_new0(Job, 1);
    j->app = a;
    j->key = g_strdup(key);
    j->path = g_strdup(item->path);
    j->w = preview ? 340 : 240;
    j->h = preview ? 190 : 680;
    char *name = g_strconcat(key, ".png", NULL);
    j->file = g_build_filename(a->cache_dir,
                               preview ? "carousel_previews" : "carousel_cards",
                               name, NULL);
    g_free(name);
    g_hash_table_add(a->pending, g_strdup(key));
    g_thread_pool_push(a->workers, j, NULL);
  }
  g_free(key);
  return NULL;
}
static gboolean tick(GtkWidget *w, GdkFrameClock *clock, gpointer data) {
  (void)clock;
  App *a = data;
  double diff = a->target - a->position;
  if (fabs(diff) > 0.002) {
    a->position += diff * 0.24;
    gtk_widget_queue_draw(w);
    return G_SOURCE_CONTINUE;
  }
  a->position = a->target;
  a->tick = 0;
  gtk_widget_queue_draw(w);
  return G_SOURCE_REMOVE;
}
static void animate(App *a) {
  if (!a->tick)
    a->tick = gtk_widget_add_tick_callback(a->area, tick, a, NULL);
}
static void jump(App *a, int index) {
  if (!a->filtered->len || a->applying)
    return;
  index = CLAMP(index, 0, (int)a->filtered->len - 1);
  if (index != a->index) {
    a->index = index;
    a->target = index;
    animate(a);
    prewarm(a);
  }
}
static void prewarm(App *a) {
  if (!a->filtered->len)
    return;
  /* Focused preview and card first; nearby cards follow without extra threads.
   */
  Item *item = g_ptr_array_index(a->filtered, a->index);
  surface(a, item, TRUE);
  surface(a, item, FALSE);
  for (int offset = 1; offset <= 7; offset++)
    for (int sign = -1; sign <= 1; sign += 2) {
      int i = a->index + offset * sign;
      if (i >= 0 && i < (int)a->filtered->len)
        surface(a, g_ptr_array_index(a->filtered, i), FALSE);
    }
}
static void cycle(App *a) {
  if (a->applying)
    return;
  a->category = (a->category + 1) % a->categories->len;
  char *cat = g_ptr_array_index(a->categories, a->category);
  g_ptr_array_set_size(a->filtered, 0);
  for (guint i = 0; i < a->items->len; i++) {
    Item *item = g_ptr_array_index(a->items, i);
    if (a->category == 0 || strcmp(item->category, cat) == 0)
      g_ptr_array_add(a->filtered, item);
  }
  a->index = 0;
  a->position = a->target = 0;
  animate(a);
  prewarm(a);
}
static void applied(GObject *source, GAsyncResult *result, gpointer data) {
  App *a = data;
  GError *error = NULL;
  gboolean ok =
      g_subprocess_wait_check_finish(G_SUBPROCESS(source), result, &error);
  a->applying = FALSE;
  if (error) {
    g_warning("Wallpaper apply: %s", error->message);
    g_error_free(error);
  }
  g_object_unref(source);
  if (a->alive) {
    if (ok)
      gtk_window_close(GTK_WINDOW(a->window));
    else {
      gtk_widget_set_visible(a->window, TRUE);
      g_free(a->error);
      a->error =
          g_strdup("Apply failed — press Enter to retry or Esc to cancel");
      gtk_widget_queue_draw(a->area);
    }
  }
}
static void commit(App *a) {
  if (a->applying || !a->filtered->len)
    return;
  Item *item = g_ptr_array_index(a->filtered, a->index);
  GError *error = NULL;
  GSubprocess *child =
      g_subprocess_new(G_SUBPROCESS_FLAGS_STDOUT_SILENCE, &error, a->helper,
                       "wallpaper", "--apply", item->path, NULL);
  if (!child) {
    g_warning("%s", error->message);
    g_error_free(error);
    return;
  }
  a->applying = TRUE;
  g_clear_pointer(&a->error, g_free);
  /* Uncover the desktop so the compositor renders the background layer immediately */
  gtk_widget_set_visible(a->window, FALSE);
  g_subprocess_wait_check_async(child, NULL, applied, a);
}
static gboolean key(GtkEventControllerKey *controller, guint keyval,
                    guint keycode, GdkModifierType modifiers, gpointer data) {
  (void)controller;
  (void)keycode;
  (void)modifiers;
  App *a = data;
  switch (keyval) {
  case GDK_KEY_Right:
  case GDK_KEY_l:
  case GDK_KEY_Down:
  case GDK_KEY_j:
    jump(a, a->index + 1);
    break;
  case GDK_KEY_Left:
  case GDK_KEY_h:
  case GDK_KEY_Up:
  case GDK_KEY_k:
    jump(a, a->index - 1);
    break;
  case GDK_KEY_Page_Down:
    jump(a, a->index + 5);
    break;
  case GDK_KEY_Page_Up:
    jump(a, a->index - 5);
    break;
  case GDK_KEY_Home:
    jump(a, 0);
    break;
  case GDK_KEY_End:
    jump(a, (int)a->filtered->len - 1);
    break;
  case GDK_KEY_Tab:
    cycle(a);
    break;
  case GDK_KEY_Return:
  case GDK_KEY_KP_Enter:
  case GDK_KEY_space:
    commit(a);
    break;
  case GDK_KEY_Escape:
  case GDK_KEY_q:
    if (!a->applying)
      gtk_window_close(GTK_WINDOW(a->window));
    break;
  default:
    return FALSE;
  }
  return TRUE;
}
static gboolean scroll(GtkEventControllerScroll *controller, double dx,
                       double dy, gpointer data) {
  (void)controller;
  App *a = data;
  double d = fabs(dy) > fabs(dx) ? dy : dx;
  if (d > 0.15)
    jump(a, a->index + 1);
  else if (d < -0.15)
    jump(a, a->index - 1);
  return TRUE;
}
static void click(GtkGestureClick *gesture, int presses, double x, double y,
                  gpointer data) {
  (void)gesture;
  App *a = data;
  if (x >= 40 && x <= 380 && y >= 40 && y <= 270) {
    commit(a);
    return;
  }
  for (int i = a->n_bounds - 1; i >= 0; i--) {
    Bounds b = a->bounds[i];
    if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) {
      if (b.index == a->index || presses >= 2) {
        a->index = b.index;
        commit(a);
      } else {
        jump(a, b.index);
      }
      return;
    }
  }
}
static void paint_image(cairo_t *cr, cairo_surface_t *s, double x, double y,
                        double w, double h, double r) {
  cairo_save(cr);
  rounded(cr, x, y, w, h, r);
  cairo_clip(cr);
  cairo_translate(cr, x, y);
  cairo_scale(cr, w / cairo_image_surface_get_width(s),
              h / cairo_image_surface_get_height(s));
  cairo_set_source_surface(cr, s, 0, 0);
  cairo_paint(cr);
  cairo_restore(cr);
}
static void label(cairo_t *cr, double x, double y, const char *text) {
  cairo_move_to(cr, x, y);
  cairo_show_text(cr, text);
}
static void accent(App *a, cairo_t *cr, double alpha) {
  cairo_set_source_rgba(cr, a->accent[0], a->accent[1], a->accent[2], alpha);
}
typedef struct {
  double distance, relative;
  int index;
} Card;
static int compare_card(const void *aa, const void *bb) {
  const Card *a = aa, *b = bb;
  return (a->distance < b->distance) - (a->distance > b->distance);
}
static void draw(GtkDrawingArea *area, cairo_t *cr, int width, int height,
                 gpointer data) {
  (void)area;
  App *a = data;
  cairo_set_source_rgba(cr, 10 / 255., 16 / 255., 26 / 255., 0.78);
  cairo_paint(cr);
  cairo_select_font_face(cr, "JetBrainsMono Nerd Font", CAIRO_FONT_SLANT_NORMAL,
                         CAIRO_FONT_WEIGHT_BOLD);
  if (!a->filtered->len) {
    cairo_set_source_rgba(cr, 1, 1, 1, .8);
    cairo_set_font_size(cr, 24);
    label(cr, width / 2. - 120, height / 2., "No wallpapers found");
    return;
  }
  Card cards[17];
  int count = 0, center = (int)round(a->position);
  a->n_bounds = 0;
  for (int offset = -8; offset <= 8; offset++) {
    int index = center + offset;
    if (index >= 0 && index < (int)a->filtered->len)
      cards[count++] =
          (Card){fabs(index - a->position), index - a->position, index};
  }
  qsort(cards, count, sizeof(Card), compare_card);
  for (int i = 0; i < count; i++) {
    Card card = cards[i];
    double scale = fmax(.38, 1 - .075 * card.distance), w = 156 * scale,
           h = 410 * scale;
    double x = width / 2. + card.relative * 96 - w / 2,
           y = height * .54 - h / 2 + pow(card.distance, 1.25) * 14;
    double r = fmax(6, 14 * scale),
           brightness = fmax(.22, 1 - .11 * card.distance);
    gboolean active =
        card.index == a->index && fabs(a->position - card.index) < .3;
    a->bounds[a->n_bounds++] = (Bounds){card.index, x, y, w, h};
    cairo_surface_t *s =
        surface(a, g_ptr_array_index(a->filtered, card.index), FALSE);
    rounded(cr, x + 2, y + 4, w, h, r);
    cairo_set_source_rgba(cr, 0, 0, 0, .45 * brightness);
    cairo_fill(cr);
    if (s) {
      paint_image(cr, s, x, y, w, h, r);
      if (brightness < .98) {
        rounded(cr, x, y, w, h, r);
        cairo_set_source_rgba(cr, 0, 0, 0, 1 - brightness);
        cairo_fill(cr);
      }
    } else {
      rounded(cr, x, y, w, h, r);
      cairo_set_source_rgba(cr, 24 / 255., 34 / 255., 52 / 255., .8);
      cairo_fill(cr);
    }
    rounded(cr, x, y, w, h, r);
    if (active) {
      accent(a, cr, .95);
      cairo_set_line_width(cr, 3);
    } else {
      cairo_set_source_rgba(cr, 80 / 255., 97 / 255., 130 / 255.,
                            .38 * brightness);
      cairo_set_line_width(cr, 1.5);
    }
    cairo_stroke(cr);
  }
  Item *item = g_ptr_array_index(a->filtered, a->index);
  rounded(cr, 44, 42, 340, 192, 16);
  cairo_set_source_rgba(cr, 0, 0, 0, .5);
  cairo_fill(cr);
  cairo_surface_t *preview = surface(a, item, TRUE);
  if (preview)
    paint_image(cr, preview, 42, 38, 340, 192, 16);
  else {
    rounded(cr, 42, 38, 340, 192, 16);
    cairo_set_source_rgba(cr, 15 / 255., 26 / 255., 42 / 255., .9);
    cairo_fill(cr);
  }
  rounded(cr, 42, 38, 340, 192, 16);
  accent(a, cr, .8);
  cairo_set_line_width(cr, 2);
  cairo_stroke(cr);
  char *category = g_strdup_printf(" %s ", item->category);
  cairo_set_font_size(cr, 11);
  cairo_text_extents_t extents;
  cairo_text_extents(cr, category, &extents);
  double pill = extents.width + 16;
  rounded(cr, 42, 244, pill, 22, 8);
  accent(a, cr, .28);
  cairo_fill(cr);
  rounded(cr, 42, 244, pill, 22, 8);
  accent(a, cr, .6);
  cairo_set_line_width(cr, 1);
  cairo_stroke(cr);
  accent(a, cr, 1);
  label(cr, 50, 259, category);
  g_free(category);
  char counter[64];
  g_snprintf(counter, sizeof counter, "%d / %u", a->index + 1,
             a->filtered->len);
  cairo_set_source_rgba(cr, 180 / 255., 195 / 255., 220 / 255., .85);
  label(cr, 42 + pill + 14, 259, counter);
  char *stem =
      g_utf8_strlen(item->stem, -1) > 30
          ? g_strdup_printf(
                "%.*s…",
                (int)(g_utf8_offset_to_pointer(item->stem, 28) - item->stem),
                item->stem)
          : g_strdup(item->stem);
  cairo_set_font_size(cr, 14);
  cairo_set_source_rgba(cr, 235 / 255., 240 / 255., 1, .98);
  label(cr, 42, 288, stem);
  g_free(stem);
  cairo_set_font_size(cr, 10.5);
  cairo_set_source_rgba(cr, 140 / 255., 160 / 255., 190 / 255., .75);
  label(cr, 42, 304,
        a->applying ? "Applying wallpaper…"
                    : "← / → / Wheel: Browse  •  Enter: Apply");
  label(cr, 42, 319, "Tab: Category  •  Esc: Cancel");
  if (a->error) {
    cairo_set_source_rgb(cr, .9, .45, .45);
    label(cr, 42, 339, a->error);
  }
}
static gboolean close_requested(GtkWindow *window, gpointer data) {
  (void)window;
  App *a = data;
  if (a->applying)
    return TRUE;
  a->alive = FALSE;
  return FALSE;
}
/* Exercise the actual event handlers on an isolated GTK display. Never apply.
 */
static gboolean test_controls(gpointer data) {
  App *a = data;
  g_assert_cmpuint(a->filtered->len, >, 1);
  key(NULL, GDK_KEY_Home, 0, 0, a);
  g_assert_cmpint(a->index, ==, 0);
  key(NULL, GDK_KEY_Right, 0, 0, a);
  g_assert_cmpint(a->index, ==, 1);
  key(NULL, GDK_KEY_Left, 0, 0, a);
  g_assert_cmpint(a->index, ==, 0);
  key(NULL, GDK_KEY_Page_Down, 0, 0, a);
  g_assert_cmpint(a->index, ==, MIN(5, (int)a->filtered->len - 1));
  key(NULL, GDK_KEY_End, 0, 0, a);
  g_assert_cmpint(a->index, ==, (int)a->filtered->len - 1);
  scroll(NULL, 0, -1, a);
  g_assert_cmpint(a->index, ==, (int)a->filtered->len - 2);
  key(NULL, GDK_KEY_Tab, 0, 0, a);
  g_assert_cmpint(a->category, ==, 1);
  g_assert_cmpint(a->index, ==, 0);
  if (a->filtered->len > 1) {
    a->bounds[0] = (Bounds){1, 500, 400, 100, 100};
    a->n_bounds = 1;
    click(NULL, 1, 550, 450, a);
    g_assert_cmpint(a->index, ==, 1);
  }
  g_assert_cmpuint(g_hash_table_size(a->cache), <=, 48);
  g_assert_cmpuint(g_hash_table_size(a->pending), <=, 36);
  g_print("PASS: native carousel keyboard, wheel, category, card click and "
          "cache bounds\n");
  key(NULL, GDK_KEY_Escape, 0, 0, a);
  return G_SOURCE_REMOVE;
}
static void activate(GtkApplication *application, gpointer data) {
  App *a = data;
  a->window = gtk_application_window_new(application);
  gtk_window_set_title(GTK_WINDOW(a->window), "minimal-wallpaper-carousel");
  gtk_window_set_default_size(GTK_WINDOW(a->window), 1366, 768);
  gtk_widget_set_focusable(a->window, TRUE);
  gtk_window_fullscreen(GTK_WINDOW(a->window));
  a->area = gtk_drawing_area_new();
  gtk_widget_set_hexpand(a->area, TRUE);
  gtk_widget_set_vexpand(a->area, TRUE);
  gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(a->area), draw, a, NULL);
  gtk_window_set_child(GTK_WINDOW(a->window), a->area);
  a->alive = TRUE;
  GtkEventController *keys = gtk_event_controller_key_new();
  g_signal_connect(keys, "key-pressed", G_CALLBACK(key), a);
  gtk_widget_add_controller(a->window, keys);
  GtkEventController *wheel =
      gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES);
  g_signal_connect(wheel, "scroll", G_CALLBACK(scroll), a);
  gtk_widget_add_controller(a->window, wheel);
  GtkGesture *gesture = gtk_gesture_click_new();
  g_signal_connect(gesture, "released", G_CALLBACK(click), a);
  gtk_widget_add_controller(a->window, GTK_EVENT_CONTROLLER(gesture));
  g_signal_connect(a->window, "close-request", G_CALLBACK(close_requested), a);
  prewarm(a);
  gtk_window_present(GTK_WINDOW(a->window));
  if (a->self_test)
    g_timeout_add(500, test_controls, a);
}
static const char *field(json_object *o, const char *name) {
  json_object *v = NULL;
  return json_object_object_get_ex(o, name, &v) &&
                 json_object_is_type(v, json_type_string)
             ? json_object_get_string(v)
             : "";
}
int main(int argc, char **argv) {
  if (!g_getenv("GSK_RENDERER"))
    g_setenv("GSK_RENDERER", "cairo", FALSE);
  App *a = g_new0(App, 1);
  a->self_test = argc == 2 && !strcmp(argv[1], "--self-test");
  const char *root = g_getenv("MINIMAL_ROOT");
  if (!root) {
    g_printerr("MINIMAL_ROOT must be set\n");
    return 1;
  }
  a->helper = g_build_filename(root, "build/minimal", NULL);
  a->cache_dir = xdg("XDG_CACHE_HOME", ".cache");
  a->state_dir = xdg("XDG_STATE_HOME", ".local/state");
  for (int i = 0; i < 2; i++) {
    char *p = g_build_filename(
        a->cache_dir, i ? "carousel_previews" : "carousel_cards", NULL);
    g_mkdir_with_parents(p, 0700);
    g_free(p);
  }
  char *out = NULL, *err = NULL;
  int status;
  char *command[] = {a->helper, "wallpaper", "--list", NULL};
  if (!g_spawn_sync(NULL, command, NULL, 0, NULL, NULL, &out, &err, &status,
                    NULL) ||
      !g_spawn_check_wait_status(status, NULL)) {
    g_printerr("Discovery failed: %s\n", err ? err : "");
    return 1;
  }
  g_free(err);
  json_object *list = json_tokener_parse(out);
  g_free(out);
  if (!list || !json_object_is_type(list, json_type_array))
    return 1;
  a->items = g_ptr_array_new();
  a->filtered = g_ptr_array_new();
  a->categories = g_ptr_array_new();
  g_ptr_array_add(a->categories, g_strdup("All"));
  char *p = g_build_filename(a->state_dir, "current_wallpaper", NULL);
  char *current = read_text(p);
  g_free(p);
  for (size_t i = 0; i < json_object_array_length(list); i++) {
    json_object *o = json_object_array_get_idx(list, i);
    Item *item = g_new0(Item, 1);
    item->path = g_strdup(field(o, "path"));
    item->category = g_strdup(field(o, "category"));
    item->stem = g_strdup(field(o, "stem"));
    if (!strcmp(current, item->path))
      a->index = (int)i;
    g_ptr_array_add(a->items, item);
    g_ptr_array_add(a->filtered, item);
    gboolean found = FALSE;
    for (guint j = 1; j < a->categories->len; j++)
      if (!strcmp(item->category, g_ptr_array_index(a->categories, j)))
        found = TRUE;
    if (!found)
      g_ptr_array_add(a->categories, g_strdup(item->category));
  }
  json_object_put(list);
  g_free(current);
  a->position = a->target = a->index;
  a->accent[0] = 202 / 255.;
  a->accent[1] = 158 / 255.;
  a->accent[2] = 230 / 255.;
  p = g_build_filename(a->state_dir, "theme", "palette.json", NULL);
  char *palette = read_text(p);
  g_free(p);
  json_object *pal = json_tokener_parse(palette);
  g_free(palette);
  if (pal) {
    const char *hex = field(pal, "accent");
    if (strlen(hex) == 6)
      for (int i = 0; i < 3; i++) {
        char part[3] = {hex[i * 2], hex[i * 2 + 1], 0};
        a->accent[i] = strtol(part, NULL, 16) / 255.;
      }
    json_object_put(pal);
  }
  a->cache =
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, cached_free);
  a->pending = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
  a->workers = g_thread_pool_new(load_job, NULL, 2, FALSE, NULL);
  /* Offscreen draw mode exercises the same geometry without opening a desktop
   * window. */
  if (argc == 3 && !strcmp(argv[1], "--snapshot")) {
    a->alive = TRUE;
    cairo_surface_t *s =
        cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 1366, 768);
    cairo_t *cr = cairo_create(s);
    draw(NULL, cr, 1366, 768, a);
    g_thread_pool_free(a->workers, FALSE, TRUE);
    a->workers = NULL;
    while (g_main_context_iteration(NULL, FALSE)) {
    }
    cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
    cairo_paint(cr);
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
    draw(NULL, cr, 1366, 768, a);
    cairo_surface_write_to_png(s, argv[2]);
    cairo_destroy(cr);
    cairo_surface_destroy(s);
    return 0;
  }
  a->application = gtk_application_new("minimal.wallpaper.carousel",
                                       G_APPLICATION_DEFAULT_FLAGS);
  g_signal_connect(a->application, "activate", G_CALLBACK(activate), a);
  int result = g_application_run(G_APPLICATION(a->application), 0, NULL);
  a->alive = FALSE;
  g_thread_pool_free(a->workers, FALSE, TRUE);
  g_object_unref(a->application);
  return result;
}
