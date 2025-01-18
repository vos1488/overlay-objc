#import <Cocoa/Cocoa.h>

@interface OverlayView : NSView
@property (strong, nonatomic) NSTimer *timer;
@property (strong, nonatomic) NSString *currentTime;
@property (strong, nonatomic) NSString *batteryStatus;
@property (assign, nonatomic) double batteryLevel;
@property (strong, nonatomic) NSString *localIP;
@property (strong, nonatomic) NSString *publicIP;
@property (strong, nonatomic) NSButton *closeButton;
@end
