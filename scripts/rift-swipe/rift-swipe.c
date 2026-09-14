/*
 * rift-swipe — turn a deliberate 3-finger horizontal swipe into rigid window
 * paging inside Rift's scrolling layout.
 *
 * Rift's own scroll gesture only pans the strip (no focus change, no snap on
 * release). This helper watches the same low-level HID gesture events Rift
 * decodes (CGEvent type 29 + the attached multi-touch digitizer), and when a
 * 3-finger horizontal swipe is detected it runs:
 *
 *     rift-cli window next      (fingers moved right)
 *     rift-cli window prev      (fingers moved left)
 *
 * Rift then reveals + focuses the next/prev maximized column, centered and
 * animated — one window per swipe, never resting mid-window.
 *
 * Direction/scale mirror Rift's own decode in src/sys/gesture.rs (digitizer
 * X/Y coordinates are normalized to the trackpad, ~1.0 across a full sweep,
 * so the default threshold of 0.45 fires part-way through a deliberate swipe
 * and ignores small flicks).
 *
 * Tuning via environment:
 *   RIFT_SWIPE_THRESHOLD  fraction of a full sweep to fire (default 0.45)
 *   RIFT_SWIPE_INVERT     match config invert_horizontal (default 1)
 *   RIFT_SWIPE_QUIET_MS   gesture gap that ends a session (default 150)
 *   RIFT_SWIPE_CLI        path to rift-cli (default: from PATH + brew prefixes)
 *
 * Build (Command Line Tools only — no Xcode needed):
 *   cc -O2 -Wall -Wextra -o rift-swipe rift-swipe.c \
 *      -framework CoreFoundation -framework CoreGraphics -framework IOKit
 *
 * Run under a LaunchAgent; grants Accessibility permission to its binary path.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>

#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

/*
 * IOHIDEvent private API — the header is not shipped in the public SDK, so the
 * handful of functions we need are declared manually. The symbols are exported
 * from IOKit.framework (Rift's own src/sys/gesture.rs links the same ones).
 */
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOHIDEventType;
typedef uint32_t IOHIDEventField;

IOHIDEventRef CGEventCopyIOHIDEvent(CGEventRef event);
IOHIDEventType IOHIDEventGetType(IOHIDEventRef event);
CFArrayRef IOHIDEventGetChildren(IOHIDEventRef event);
long IOHIDEventGetIntegerValue(IOHIDEventRef event, IOHIDEventField field);
double IOHIDEventGetFloatValue(IOHIDEventRef event, IOHIDEventField field);

/* CoreGraphicsServices event type 29 = multitouch gesture (mirrors Rift). */
#define CG_EVENT_GESTURE 29u
#define GESTURE_EVENT_MASK ((CGEventMask)1u << CG_EVENT_GESTURE)

/* IOHID digitizer fields, computed the same way Rift does (these constants
 * stopped being exported by the public SDK headers). */
#define IOHID_EVENT_TYPE_DIGITIZER 11u
#define FIELD_DIGITIZER_X      (IOHIDEventField)(IOHID_EVENT_TYPE_DIGITIZER << 16)
#define FIELD_DIGITIZER_Y      (IOHIDEventField)(FIELD_DIGITIZER_X + 1)
#define FIELD_DIGITIZER_INDEX  (IOHIDEventField)(FIELD_DIGITIZER_X + 5)
#define FIELD_DIGITIZER_EVENT_MASK (IOHIDEventField)(FIELD_DIGITIZER_X + 7)
#define FIELD_DIGITIZER_TOUCH  (IOHIDEventField)(FIELD_DIGITIZER_X + 9)
#define FIELD_DIGITIZER_COLLECTION (IOHIDEventField)(FIELD_DIGITIZER_X + 22)
#define DIGITIZER_EVENT_RESTING ((int64_t)1 << 9)

#define MAX_PATHS 16
#define MAX_CHILDREN 128

static int debug_enabled = 0;

static double
now_us(void)
{
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return (double)tv.tv_sec * 1e6 + (double)tv.tv_usec;
}

static void
dbg(const char *fmt, ...)
{
	if (!debug_enabled) return;
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fputc('\n', stderr);
}

/* Execute `rift-cli window {next,prev}` in the background. */
static pid_t spawned_child = -1;

static const char *
find_rift_cli(char *buf, size_t len)
{
	const char *env = getenv("RIFT_SWIPE_CLI");
	if (env && env[0]) {
		snprintf(buf, len, "%s", env);
		return buf;
	}
	/* posix_spawnp will search PATH; prepend the common brew install points. */
	const char *extra =
	    "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin";
	const char *path = getenv("PATH");
	if (!path || !path[0]) path = "";
	snprintf(buf, len, "%s:%s", extra, path);
	return buf;
}

static void
fire_window(int next)
{
	char pathbuf[4096];
	setenv("PATH", find_rift_cli(pathbuf, sizeof pathbuf), 1);

	char *const argv[] = {
	    "rift-cli", "window", next ? "next" : "prev", NULL,
	};
	pid_t pid = 0;
	int rc = posix_spawnp(&pid, "rift-cli", NULL, NULL, argv, environ);
	if (rc == 0) {
		spawned_child = pid;
		dbg("rift-cli window %s (pid %d)", next ? "next" : "prev", (int)pid);
		return;
	}
	fprintf(stderr, "rift-swipe: posix_spawnp: %s\n", strerror(rc));
}

static void
reap_child(void)
{
	if (spawned_child > 0) {
		waitpid(spawned_child, NULL, WNOHANG);
	}
}

/*
 * Decode one type-29 event: return >0 = number of active touching paths, and
 * output their centroid. Mirrors Rift's ScrollTouchFrame::from_digitizer.
 */
static int
decode_frame(CGEventRef event, double *out_x, double *out_y)
{
	IOHIDEventRef hid = CGEventCopyIOHIDEvent(event);
	if (!hid) return 0;

	int count = 0;
	double sx = 0, sy = 0;
	CFArrayRef children = IOHIDEventGetChildren(hid);
	if (children) {
		CFIndex n = CFArrayGetCount(children);
		if (n > MAX_CHILDREN) n = MAX_CHILDREN;
		for (CFIndex i = 0; i < n; i++) {
			IOHIDEventRef child =
			    (IOHIDEventRef)CFArrayGetValueAtIndex(children, i);
			if (!child) continue;
			if (IOHIDEventGetType(child) != IOHID_EVENT_TYPE_DIGITIZER) continue;
			if (IOHIDEventGetIntegerValue(child, FIELD_DIGITIZER_COLLECTION) != 0)
				continue; /* collection node, not a touch path */
			if (IOHIDEventGetIntegerValue(child, FIELD_DIGITIZER_TOUCH) == 0)
				continue;
			int64_t mask = IOHIDEventGetIntegerValue(child, FIELD_DIGITIZER_EVENT_MASK);
			if (mask & DIGITIZER_EVENT_RESTING) continue;
			double x = (double)IOHIDEventGetFloatValue(child, FIELD_DIGITIZER_X);
			double y = (double)IOHIDEventGetFloatValue(child, FIELD_DIGITIZER_Y);
			if (!isfinite(x) || !isfinite(y)) continue;
			sx += x;
			sy += y;
			count++;
		}
	}
	CFRelease(hid);

	if (out_x) *out_x = count ? sx / (double)count : 0;
	if (out_y) *out_y = count ? sy / (double)count : 0;
	return count;
}

static CGEventRef
tap_callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info)
{
	(void)proxy;
	(void)info;

	if ((uint32_t)type != CG_EVENT_GESTURE) {
		return event;
	}

	double cx, cy;
	int count = decode_frame(event, &cx, &cy);

	static double prev_x, prev_y;
	static double accum;        /* effective horizontal progress, invert applied */
	static int fired;           /* 1 fired next this session, -1 fired prev */
	static int active;
	static double last_event;

	double t = now_us();
	reap_child();

	if (count == 3) {
		if (!active) {
			prev_x = cx;
			prev_y = cy;
			accum = 0;
			fired = 0;
			active = 1;
			last_event = t;
			return event;
		}
		double dx = cx - prev_x;
		double dy = cy - prev_y;
		prev_x = cx;
		prev_y = cy;
		last_event = t;

		/* Reject vertical/rotational movement. */
		double adx = fabs(dx), ady = fabs(dy);
		if (adx <= 0.0001 && ady <= 0.0001) return event;
		if (ady > adx) return event;

		if (!fired) {
			int invert = 1;
			const char *inv = getenv("RIFT_SWIPE_INVERT");
			if (inv && inv[0]) invert = atoi(inv) != 0;

			/* Match Rift's scroll decode: with invert_horizontal=true (the
			 * shipped config), fingers moving LEFT advance to the next column,
			 * fingers moving RIGHT step back to the previous one. */
			double eff = invert ? -dx : dx;
			accum += eff;

			double threshold = 0.45;
			const char *thr = getenv("RIFT_SWIPE_THRESHOLD");
			if (thr && thr[0]) threshold = atof(thr);

			if (fabs(accum) >= threshold) {
				fired = accum > 0 ? 1 : -1;
				fire_window(fired == 1);
			}
		}
		return event;
	}

	/* No 3-finger contact in this frame. End the session once the gesture
	 * stream goes quiet, so consecutive physical swipes stay independent. */
	if (active) {
		unsigned long quiet = 150;
		const char *q = getenv("RIFT_SWIPE_QUIET_MS");
		if (q && q[0]) quiet = strtoul(q, NULL, 10);
		if (t - last_event >= (double)quiet * 1000.0) {
			active = 0;
			accum = 0;
			fired = 0;
			dbg("session ended (quiet)");
		}
	} else {
		last_event = t;
	}

	return event;
}

int
main(void)
{
	/* Single instance: the LaunchAgent and manual runs must not stack. */
	int lockfd = open("/tmp/rift-swipe.lock", O_CREAT | O_RDWR, 0600);
	if (lockfd < 0 || flock(lockfd, LOCK_EX | LOCK_NB) != 0) {
		fprintf(stderr, "rift-swipe: another instance is already running\n");
		return 0;
	}

	if (getenv("RIFT_SWIPE_DEBUG")) debug_enabled = 1;

	/* Run permanently regardless of accessibility permission; without it the
	 * tap simply never fires, and it recovers as soon as the grant lands. */
	CFMachPortRef tap = CGEventTapCreate(
	    kCGHIDEventTap,        /* same tap Rift uses to see the raw gesture */
	    kCGHeadInsertEventTap,
	    kCGEventTapOptionListenOnly, /* observe only; never consume */
	    GESTURE_EVENT_MASK,
	    tap_callback,
	    NULL);
	if (!tap) {
		fprintf(stderr,
			"rift-swipe: CGEventTapCreate failed "
			"(grant Accessibility to this binary and relaunch)\n");
		return 1;
	}

	CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(
	    kCFAllocatorDefault, tap, 0);
	if (!src) {
		CFRelease(tap);
		return 1;
	}
	CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
	CFRelease(src);
	CFRelease(tap);

	dbg("rift-swipe: listening for 3-finger horizontal swipes");
	CFRunLoopRun();

	return 0;
}