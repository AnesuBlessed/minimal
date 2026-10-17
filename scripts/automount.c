/* Native, event-driven removable-volume mounting through GIO/UDisks.
 * Requires the standard gvfs UDisks volume monitor; no polling or shell loop. */
#include <gio/gio.h>
#include <glib-unix.h>
#include <signal.h>
static GMainLoop *loop;
static GHashTable *pending;
static void mounted(GObject *source, GAsyncResult *result, gpointer unused) {
    (void)unused;
    GError *error = NULL;
    gchar *name = g_volume_get_name(G_VOLUME(source));
    gboolean success = TRUE;
    if (!g_volume_mount_finish(G_VOLUME(source), result, &error)) {
        success = FALSE;
        g_printerr("Mount failed: %s\n", error->message);
        g_error_free(error);
    }
    gchar *command[] = {"notify-send", "-a", "minimal-usb", "--", success ? "Drive mounted" : "Drive could not be mounted", name ? name : "Removable drive", NULL};
    g_spawn_async(NULL, command, NULL, G_SPAWN_SEARCH_PATH, NULL, NULL, NULL, NULL);
    g_free(name);
    g_hash_table_remove(pending, source);
}
static void mount_volume(GVolumeMonitor *monitor, GVolume *volume, gpointer unused) {
    (void)monitor; (void)unused;
    if (!g_volume_should_automount(volume) || !g_volume_can_mount(volume) ||
        g_hash_table_contains(pending, volume)) return;
    GMount *mount = g_volume_get_mount(volume);
    if (mount) { g_object_unref(mount); return; }
    GDrive *drive = g_volume_get_drive(volume);
    gboolean removable = drive && (g_drive_is_removable(drive) || g_drive_is_media_removable(drive));
    g_clear_object(&drive);
    if (!removable) return;
    g_hash_table_add(pending, g_object_ref(volume));
    g_volume_mount(volume, G_MOUNT_MOUNT_NONE, NULL, NULL, mounted, NULL);
}
static gboolean stop(gpointer unused) {
    (void)unused; g_main_loop_quit(loop); return G_SOURCE_REMOVE;
}
int main(void) {
    loop = g_main_loop_new(NULL, FALSE);
    pending = g_hash_table_new_full(g_direct_hash, g_direct_equal, g_object_unref, NULL);
    GVolumeMonitor *monitor = g_volume_monitor_get();
    gulong handler_id = g_signal_connect(monitor, "volume-added", G_CALLBACK(mount_volume), NULL);
    GList *volumes = g_volume_monitor_get_volumes(monitor);
    for (GList *v = volumes; v; v = v->next) mount_volume(monitor, v->data, NULL);
    g_list_free_full(volumes, g_object_unref);
    g_unix_signal_add(SIGTERM, stop, NULL);
    g_unix_signal_add(SIGINT, stop, NULL);
    g_main_loop_run(loop);
    g_signal_handler_disconnect(monitor, handler_id);
    g_object_unref(monitor);
    g_hash_table_unref(pending);
    g_main_loop_unref(loop);
    return 0;
}
