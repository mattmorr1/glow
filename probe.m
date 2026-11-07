#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
@interface NSObject (BrightnessProbe)
- (BOOL)activateWithError:(NSError **)error;
@end
int main() {
 @autoreleasepool {
 dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW);
 id client = [NSClassFromString(@"BrightnessSystemClient") new];
 NSError *error = nil;
 BOOL active = [client activateWithError:&error];
 NSLog(@"Active: %d %@", active, error);
 for (NSString *key in @[@"DisplayBrightness", @"LEContainersInfo", @"LEBacklightMode", @"LEPWMState", @"ClientLE-mapping", @"NitsMultiplier"]) {
   NSLog(@"%@: %@", key, [client performSelector:@selector(copyPropertyForKey:) withObject:key]);
 }

 }
}
