#import "LogoPWM.h"
#include <signal.h>
#include <unistd.h>

static volatile sig_atomic_t interrupted;

static void stop(int signalNumber) {
    (void)signalNumber;
    interrupted = 1;
}

static int testPWM(io_service_t led, io_service_t display) {
    PWM initial = readPWM(led);
    uint64_t period = initial.high + initial.low;
    NSNumber *brightness = displayBrightness(display);
    if (!usablePWM(initial) || !brightness) {
        fputs("Need an awake built-in display and a lit logo with a stable PWM frequency.\n", stderr);
        return 1;
    }

    printf("uid=%u screen=%s logo=%llu/%llu at %llu Hz\n",
           geteuid(), brightness.stringValue.UTF8String, initial.high, period, initial.clock / period);
    PWM last = initial;
    int confirmed = 0;
    for (int step = 0; step < 2 && !interrupted; step++) {
        if (!samePWM(readPWM(led), last) || ![brightness isEqual:displayBrightness(display)]) {
            fputs("macOS changed the display or logo during the test.\n", stderr);
            break;
        }

        uint64_t high = step == 0 ? initial.high / 2 : initial.high * 3 / 4;
        PWM target = { high, period - high, initial.clock };
        kern_return_t result = setPWM(led, target);
        PWM observed = readPWM(led);
        printf("Step %d: requested %llu/%llu, read %llu/%llu, IOKit 0x%08x (%s)\n",
               step + 1, high, period, observed.high, observed.high + observed.low,
               result, mach_error_string(result));
        fflush(stdout);
        BOOL reachedTarget = reachedPWM(target, observed);
        BOOL changed = !samePWM(observed, last);
        if (reachedTarget) last = observed;
        if (result != KERN_SUCCESS || !reachedTarget || !changed) break;

        usleep(650000);
        if (!samePWM(readPWM(led), last) || ![brightness isEqual:displayBrightness(display)]) {
            fputs("The requested level did not hold at a fixed screen brightness.\n", stderr);
            break;
        }
        confirmed++;
    }

    PWM current = readPWM(led);
    if (!samePWM(last, initial) && samePWM(current, last)) {
        kern_return_t result = setPWM(led, initial);
        PWM restored = readPWM(led);
        printf("Restore: IOKit 0x%08x, read %llu/%llu\n",
               result, restored.high, restored.high + restored.low);
        if (result != KERN_SUCCESS || !samePWM(restored, initial)) return 1;
    } else if (!samePWM(current, initial)) {
        fputs("The controller changed independently. Left its latest value in place.\n", stderr);
        return 1;
    }

    if (confirmed == 2) puts("Verified two logo levels at a fixed screen brightness.");
    return confirmed == 2 ? 0 : 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2 || strcmp(argv[1], "--test") != 0) {
            fprintf(stderr, "Usage: %s --test\n", argv[0]);
            return 2;
        }
        signal(SIGINT, stop);
        signal(SIGTERM, stop);
        io_service_t led = openLogoPWM();
        io_service_t display = openDisplayBacklight();
        int result = 1;
        if (led && display) {
            result = testPWM(led, display);
        } else {
            fputs("Could not identify the lid LED and built-in display controllers.\n", stderr);
        }
        if (led) IOObjectRelease(led);
        if (display) IOObjectRelease(display);
        return result;
    }
}
