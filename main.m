#import <Cocoa/Cocoa.h>
#import "OverlayWindowController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    return NSTerminateNow;
}
@end

int main(int __attribute__((unused)) argc, const char * __attribute__((unused)) argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [application setDelegate:delegate];
        
        OverlayWindowController *windowController = [[OverlayWindowController alloc] init];
        [windowController showWindow:nil];
        
        [application run];
    }
    return 0;
}
