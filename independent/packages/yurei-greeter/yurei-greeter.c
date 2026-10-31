/* yurei-greeter: Yūrei's graphical login screen.
 *
 * One program, four jobs, which the login-screen script (run as root by
 * yurei-greeter.service on the first screen) puts together:
 *
 *   yurei-greeter drop USER COMMAND...  becomes USER, then runs COMMAND
 *   yurei-greeter ui [--user NAME] [--failed]
 *                                       the screen itself (GTK, in cage, as
 *                                       the unprivileged "greeter" user):
 *                                       prints the name and password typed,
 *                                       or an empty line and "poweroff" or
 *                                       "reboot", on standard output
 *   yurei-greeter check                 reads a name and password on standard
 *                                       input and checks them against
 *                                       /etc/shadow (root only)
 *   yurei-greeter session USER          starts USER's desktop on this screen
 *                                       (root only)
 *
 * So the screen people type into never runs as root; only the short checks
 * around it do.
 */
#define _GNU_SOURCE
#include <crypt.h>
#include <errno.h>
#include <grp.h>
#include <pwd.h>
#include <shadow.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <gtk/gtk.h>

static int fail(const char *what)
{
    fprintf(stderr, "yurei-greeter: %s: %s\n", what, errno ? strerror(errno) : "failed");
    return 1;
}

/* drop: USER's groups, group and user, in that order, and nothing left of root */
static int become(const struct passwd *pw)
{
    if (initgroups(pw->pw_name, pw->pw_gid) || setgid(pw->pw_gid) || setuid(pw->pw_uid))
        return fail("changing user");
    if (pw->pw_uid != 0 && (setuid(0) == 0 || geteuid() == 0)) {
        fprintf(stderr, "yurei-greeter: still root after changing user\n");
        return 1;
    }
    return 0;
}

static int cmd_drop(int argc, char **argv)
{
    if (argc < 4) return 2;
    struct passwd *pw = getpwnam(argv[2]);
    if (!pw) return fail("no such user");
    if (become(pw)) return 1;
    setenv("HOME", pw->pw_dir, 1);
    setenv("USER", pw->pw_name, 1);
    setenv("LOGNAME", pw->pw_name, 1);
    if (chdir(pw->pw_dir) != 0 && chdir("/") != 0) return fail("chdir");
    execvp(argv[3], argv + 3);
    return fail(argv[3]);
}

static int cmd_check(void)
{
    char *user = NULL, *pass = NULL;
    size_t n1 = 0, n2 = 0;
    int ok = 0;
    if (getline(&user, &n1, stdin) > 0 && getline(&pass, &n2, stdin) >= 0) {
        user[strcspn(user, "\n")] = 0;
        pass[strcspn(pass, "\n")] = 0;
        struct passwd *pw = getpwnam(user);
        struct spwd *sp = getspnam(user);
        const char *hash = sp ? sp->sp_pwdp : pw ? pw->pw_passwd : NULL;
        /* no password, or a locked account: no way in */
        if (pw && hash && hash[0] && hash[0] != '!' && hash[0] != '*') {
            const char *c = crypt(pass, hash);
            ok = c && strcmp(c, hash) == 0;
        }
        explicit_bzero(pass, n2);
    }
    if (ok) printf("%s\n", user);
    free(user);
    free(pass);
    return ok ? 0 : 1;
}

static int cmd_session(const char *name)
{
    struct passwd *pw = getpwnam(name);
    if (!pw) return fail("no such user");
    /* the user's runtime directory, as a logind session would make it */
    char rt[64];
    snprintf(rt, sizeof rt, "/run/user/%u", (unsigned)pw->pw_uid);
    mkdir("/run/user", 0755);
    if (mkdir(rt, 0700) != 0 && errno != EEXIST) return fail(rt);
    if (chown(rt, pw->pw_uid, pw->pw_gid) || chmod(rt, 0700)) return fail(rt);
    char *shell = pw->pw_shell && pw->pw_shell[0] ? pw->pw_shell : "/bin/bash";
    char *term = getenv("TERM");
    char termbuf[64];
    snprintf(termbuf, sizeof termbuf, "%s", term ? term : "linux");
    clearenv();
    setenv("HOME", pw->pw_dir, 1);
    setenv("USER", pw->pw_name, 1);
    setenv("LOGNAME", pw->pw_name, 1);
    setenv("SHELL", shell, 1);
    setenv("TERM", termbuf, 1);
    setenv("PATH", "/usr/local/bin:/usr/bin", 1);
    setenv("XDG_RUNTIME_DIR", rt, 1);
    setenv("XDG_SESSION_TYPE", "wayland", 1);
    setenv("XDG_SEAT", "seat0", 1);
    setenv("XDG_VTNR", "1", 1);
    /* the screen and input devices through seatd, as a member of "seat" */
    setenv("LIBSEAT_BACKEND", "seatd", 1);
    /* the login profile shouldn't offer to start a second desktop */
    setenv("YUREI_NO_DESKTOP", "1", 1);
    if (become(pw)) return 1;
    if (chdir(pw->pw_dir) != 0 && chdir("/") != 0) return fail("chdir");
    execl(shell, shell, "-l", "-c", "exec yurei-desktop", (char *)NULL);
    return fail(shell);
}

/* --- the screen ---------------------------------------------------------- */

static GtkWidget *user_entry, *pass_entry, *clock_label;

static void submit(GtkWidget *w, gpointer data)
{
    (void)w; (void)data;
    const char *u = gtk_entry_get_text(GTK_ENTRY(user_entry));
    if (!u[0]) { gtk_widget_grab_focus(user_entry); return; }
    printf("%s\n%s\n", u, gtk_entry_get_text(GTK_ENTRY(pass_entry)));
    fflush(stdout);
    gtk_main_quit();
}

static void to_password(GtkWidget *w, gpointer data)
{
    (void)w; (void)data;
    gtk_widget_grab_focus(pass_entry);
}

static void power(GtkWidget *w, gpointer what)
{
    (void)w;
    printf("\n%s\n", (const char *)what);
    fflush(stdout);
    gtk_main_quit();
}

static gboolean tick(gpointer data)
{
    (void)data;
    char buf[64];
    time_t t = time(NULL);
    strftime(buf, sizeof buf, "%A %e %B   %H:%M", localtime(&t));
    gtk_label_set_text(GTK_LABEL(clock_label), buf);
    return G_SOURCE_CONTINUE;
}

static const char css[] =
    "window { background: linear-gradient(160deg, #10131c, #1d2233 60%, #2a2140); }"
    "label { color: #e8e6f0; }"
    ".title { font-size: 42px; font-weight: 300; letter-spacing: 6px; }"
    ".subtitle, .clock { color: #9a98b0; }"
    ".error { color: #ff8080; }"
    ".card { background: rgba(255,255,255,0.06); border-radius: 14px; padding: 28px; }"
    "entry { min-width: 280px; min-height: 36px; border-radius: 8px; }"
    "button.login { min-height: 36px; border-radius: 8px; background: #6c5ce7; color: white; }"
    "button.flat label { color: #c8c6d8; }";

static GtkWidget *label(const char *text, const char *cls)
{
    GtkWidget *l = gtk_label_new(text);
    if (cls) gtk_style_context_add_class(gtk_widget_get_style_context(l), cls);
    return l;
}

static int cmd_ui(int argc, char **argv)
{
    const char *user = NULL;
    int failed = 0;
    for (int i = 2; i < argc; i++) {
        if (!strcmp(argv[i], "--user") && i + 1 < argc) user = argv[++i];
        else if (!strcmp(argv[i], "--failed")) failed = 1;
    }
    gtk_init(NULL, NULL);
    GtkCssProvider *p = gtk_css_provider_new();
    gtk_css_provider_load_from_data(p, css, -1, NULL);
    gtk_style_context_add_provider_for_screen(gdk_screen_get_default(), GTK_STYLE_PROVIDER(p),
                                              GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

    GtkWidget *win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(win), "Yūrei login");
    gtk_window_fullscreen(GTK_WINDOW(win));
    g_signal_connect(win, "destroy", G_CALLBACK(gtk_main_quit), NULL);

    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_container_add(GTK_CONTAINER(win), outer);

    clock_label = label("", "clock");
    gtk_widget_set_margin_top(clock_label, 24);
    gtk_box_pack_start(GTK_BOX(outer), clock_label, FALSE, FALSE, 0);
    tick(NULL);
    g_timeout_add_seconds(10, tick, NULL);

    GtkWidget *center = gtk_box_new(GTK_ORIENTATION_VERTICAL, 14);
    gtk_widget_set_halign(center, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(center, GTK_ALIGN_CENTER);
    gtk_box_pack_start(GTK_BOX(outer), center, TRUE, TRUE, 0);
    gtk_box_pack_start(GTK_BOX(center), label("Yūrei", "title"), FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(center), label("Sign in", "subtitle"), FALSE, FALSE, 0);

    GtkWidget *card = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10);
    gtk_style_context_add_class(gtk_widget_get_style_context(card), "card");
    gtk_box_pack_start(GTK_BOX(center), card, FALSE, FALSE, 8);

    user_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(user_entry), "User name");
    if (user) gtk_entry_set_text(GTK_ENTRY(user_entry), user);
    g_signal_connect(user_entry, "activate", G_CALLBACK(to_password), NULL);
    gtk_box_pack_start(GTK_BOX(card), user_entry, FALSE, FALSE, 0);

    pass_entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(pass_entry), "Password");
    gtk_entry_set_visibility(GTK_ENTRY(pass_entry), FALSE);
    gtk_entry_set_input_purpose(GTK_ENTRY(pass_entry), GTK_INPUT_PURPOSE_PASSWORD);
    g_signal_connect(pass_entry, "activate", G_CALLBACK(submit), NULL);
    gtk_box_pack_start(GTK_BOX(card), pass_entry, FALSE, FALSE, 0);

    if (failed) gtk_box_pack_start(GTK_BOX(card), label("Wrong user name or password.", "error"), FALSE, FALSE, 0);

    GtkWidget *go = gtk_button_new_with_label("Log in");
    gtk_style_context_add_class(gtk_widget_get_style_context(go), "login");
    g_signal_connect(go, "clicked", G_CALLBACK(submit), NULL);
    gtk_box_pack_start(GTK_BOX(card), go, FALSE, FALSE, 4);

    GtkWidget *bottom = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8);
    gtk_widget_set_halign(bottom, GTK_ALIGN_END);
    gtk_widget_set_margin_bottom(bottom, 18);
    gtk_widget_set_margin_end(bottom, 18);
    GtkWidget *rb = gtk_button_new_with_label("Restart");
    GtkWidget *sb = gtk_button_new_with_label("Shut down");
    gtk_button_set_relief(GTK_BUTTON(rb), GTK_RELIEF_NONE);
    gtk_button_set_relief(GTK_BUTTON(sb), GTK_RELIEF_NONE);
    gtk_style_context_add_class(gtk_widget_get_style_context(rb), "flat");
    gtk_style_context_add_class(gtk_widget_get_style_context(sb), "flat");
    g_signal_connect(rb, "clicked", G_CALLBACK(power), "reboot");
    g_signal_connect(sb, "clicked", G_CALLBACK(power), "poweroff");
    gtk_box_pack_start(GTK_BOX(bottom), rb, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(bottom), sb, FALSE, FALSE, 0);
    gtk_box_pack_end(GTK_BOX(outer), bottom, FALSE, FALSE, 0);

    gtk_widget_show_all(win);
    gtk_widget_grab_focus(user && user[0] ? pass_entry : user_entry);
    gtk_main();
    return 0;
}

int main(int argc, char **argv)
{
    if (argc >= 2 && !strcmp(argv[1], "drop")) return cmd_drop(argc, argv);
    if (argc >= 2 && !strcmp(argv[1], "ui")) return cmd_ui(argc, argv);
    if (argc == 2 && !strcmp(argv[1], "check")) return cmd_check();
    if (argc == 3 && !strcmp(argv[1], "session")) return cmd_session(argv[2]);
    fprintf(stderr, "usage: yurei-greeter drop USER COMMAND... | ui [--user NAME] [--failed] | check | session USER\n");
    return 2;
}
