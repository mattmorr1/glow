// Draws AppIcon.icns: a dark lid with a glowing emblem.
// Build and run: clang -fobjc-arc -framework AppKit tools/make-icon.m -o /tmp/make-icon && /tmp/make-icon
#import <AppKit/AppKit.h>

static void drawIcon(CGFloat size) {
    CGFloat s = size / 1024;
    NSRect tile = NSMakeRect(100 * s, 100 * s, 824 * s, 824 * s);
    NSBezierPath *shape = [NSBezierPath bezierPathWithRoundedRect:tile xRadius:185 * s yRadius:185 * s];
    NSGradient *body = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:0.22 alpha:1]
                                                     endingColor:[NSColor colorWithWhite:0.07 alpha:1]];
    [body drawInBezierPath:shape angle:-90];

    NSPoint center = NSMakePoint(512 * s, 512 * s);
    NSGradient *glow = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithRed:1 green:0.98 blue:0.92 alpha:0.9], 0.0,
        [NSColor colorWithRed:0.75 green:0.85 blue:1 alpha:0.35], 0.35,
        [NSColor colorWithRed:0.4 green:0.55 blue:1 alpha:0], 1.0, nil];
    [NSGraphicsContext saveGraphicsState];
    [shape addClip];
    [glow drawFromCenter:center radius:0 toCenter:center radius:360 * s options:0];
    [NSGraphicsContext restoreGraphicsState];

    [[NSColor whiteColor] setFill];
    CGFloat r = 92 * s;
    [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - r, center.y - r, 2 * r, 2 * r)] fill];
}

int main(void) {
    @autoreleasepool {
        NSString *set = [NSTemporaryDirectory() stringByAppendingPathComponent:@"AppIcon.iconset"];
        [NSFileManager.defaultManager removeItemAtPath:set error:nil];
        [NSFileManager.defaultManager createDirectoryAtPath:set withIntermediateDirectories:YES attributes:nil error:nil];
        for (NSNumber *points in @[@16, @32, @128, @256, @512]) {
            for (int scale = 1; scale <= 2; scale++) {
                NSInteger px = points.integerValue * scale;
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                    pixelsWide:px pixelsHigh:px bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                    colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                [NSGraphicsContext saveGraphicsState];
                NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
                drawIcon(px);
                [NSGraphicsContext restoreGraphicsState];
                NSString *name = scale == 1
                    ? [NSString stringWithFormat:@"icon_%@x%@.png", points, points]
                    : [NSString stringWithFormat:@"icon_%@x%@@2x.png", points, points];
                [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
                    writeToFile:[set stringByAppendingPathComponent:name] atomically:YES];
            }
        }
        NSTask *task = [NSTask launchedTaskWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/iconutil"]
            arguments:@[@"-c", @"icns", set, @"-o", @"AppIcon.icns"] error:nil terminationHandler:nil];
        [task waitUntilExit];
        return task.terminationStatus;
    }
}
