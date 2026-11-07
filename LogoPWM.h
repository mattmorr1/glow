#pragma once

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <math.h>

typedef struct {
    uint64_t high;
    uint64_t low;
    uint64_t clock;
} PWM;

static inline NSDictionary *properties(io_registry_entry_t entry) {
    CFMutableDictionaryRef dictionary = NULL;
    if (IORegistryEntryCreateCFProperties(entry, &dictionary, kCFAllocatorDefault, 0) != KERN_SUCCESS) {
        return nil;
    }
    return CFBridgingRelease(dictionary);
}

static inline PWM readPWM(io_service_t led) {
    NSDictionary *values = properties(led);
    if (![values[@"enabled"] boolValue]) return (PWM){0};
    return (PWM){ [values[@"high-period"] unsignedLongLongValue],
                  [values[@"low-period"] unsignedLongLongValue],
                  [values[@"pwm-frequency"] unsignedLongLongValue] };
}

static inline NSNumber *displayBrightness(io_service_t display) {
    return properties(display)[@"IODisplayParameters"][@"brightness"][@"value"];
}

static inline BOOL samePWM(PWM first, PWM second) {
    return first.high == second.high && first.low == second.low && first.clock == second.clock;
}

static inline uint64_t duty(PWM pwm) {
    return (uint64_t)llroundl((long double)pwm.high * 0x100000000ULL / (pwm.high + pwm.low));
}

static inline kern_return_t setPWM(io_service_t led, PWM pwm) {
    NSDictionary *request = @{
        @"set-duty-cycle": @(duty(pwm)),
        @"set-enabled": @YES,
        @"set-hz": @(pwm.clock / (pwm.high + pwm.low)),
    };
    return IORegistryEntrySetCFProperties(led, (__bridge CFDictionaryRef)request);
}

static inline kern_return_t setLogoEnabled(io_service_t led, BOOL enabled) {
    NSDictionary *request = @{@"set-enabled": @(enabled)};
    return IORegistryEntrySetCFProperties(led, (__bridge CFDictionaryRef)request);
}

static inline io_service_t openLogoPWM(void) {
    io_service_t led = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("bklb-backlight"));
    if (!led) led = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("bklb-backlight@0"));
    if (led && !IOObjectConformsTo(led, "AppleARMPWMDevice")) {
        IOObjectRelease(led);
        return IO_OBJECT_NULL;
    }
    return led;
}

static inline io_service_t openDisplayBacklight(void) {
    return IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleARMBacklight"));
}

static inline BOOL usablePWM(PWM pwm) {
    return pwm.high >= 1 && pwm.low && pwm.clock && pwm.clock % (pwm.high + pwm.low) == 0;
}

static inline BOOL reachedPWM(PWM target, PWM observed) {
    // The driver quantizes duty to clock ticks.
    return observed.clock == target.clock && observed.high + observed.low == target.high + target.low &&
        llabs((long long)observed.high - (long long)target.high) <= 1;
}
