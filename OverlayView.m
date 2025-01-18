#import "OverlayView.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#include <ifaddrs.h>
#include <arpa/inet.h>

@implementation OverlayView

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.currentTime = @"";
        self.batteryStatus = @"";
        self.batteryLevel = 0.0;
        self.localIP = @"";
        self.publicIP = @"";
        [self startTimer];
        [self updateBatteryInfo];
        [self updateIPAddresses];
        
        NSRect buttonFrame = NSMakeRect(frame.size.width - 30, frame.size.height - 30, 20, 20);
        NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:buttonFrame
                                                                   options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
                                                                     owner:self
                                                                  userInfo:nil];
        [self addTrackingArea:trackingArea];
        
        self.closeButton = [[NSButton alloc] initWithFrame:buttonFrame];
        [self.closeButton setBezelStyle:NSBezelStyleCircular];
        [self.closeButton setButtonType:NSButtonTypeMomentaryLight];
        [self.closeButton setBordered:YES];
        [self.closeButton setTitle:@"×"];
        [self.closeButton setFont:[NSFont systemFontOfSize:16]];
        [self.closeButton setTarget:self];
        [self.closeButton setAction:@selector(closeButtonClicked:)];
        [self.closeButton setWantsLayer:YES];
        self.closeButton.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.0 alpha:0.3] CGColor];
        [self addSubview:self.closeButton];
    }
    return self;
}

- (void)startTimer {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                    target:self
                                                  selector:@selector(updateTime)
                                                  userInfo:nil
                                                   repeats:YES];
        
        [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
        
        NSTimer *batteryTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                       target:self
                                     selector:@selector(updateBatteryInfo)
                                     userInfo:nil
                                      repeats:YES];
        
        [[NSRunLoop currentRunLoop] addTimer:batteryTimer forMode:NSRunLoopCommonModes];
        
        [NSTimer scheduledTimerWithTimeInterval:300.0
                                       target:self
                                     selector:@selector(updateIPAddresses)
                                     userInfo:nil
                                      repeats:YES];
        
        [self updateTime];
        [self updateBatteryInfo];
    });
}

- (void)updateTime {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"HH:mm:ss"];
        self.currentTime = [formatter stringFromDate:[NSDate date]];
        [self setNeedsDisplay:YES];
    });
}

- (void)updateBatteryInfo {
    dispatch_async(dispatch_get_main_queue(), ^{
        CFTypeRef powerSourceInfo = IOPSCopyPowerSourcesInfo();
        CFArrayRef powerSources = IOPSCopyPowerSourcesList(powerSourceInfo);
        
        self.batteryLevel = 0.0;
        self.batteryStatus = @"No Battery";
        
        if (powerSources != NULL) {
            if (CFArrayGetCount(powerSources) > 0) {
                CFDictionaryRef powerSource = IOPSGetPowerSourceDescription(powerSourceInfo, CFArrayGetValueAtIndex(powerSources, 0));
                if (powerSource) {
                    NSNumber *capacity = (__bridge NSNumber *)CFDictionaryGetValue(powerSource, CFSTR(kIOPSCurrentCapacityKey));
                    NSNumber *maxCapacity = (__bridge NSNumber *)CFDictionaryGetValue(powerSource, CFSTR(kIOPSMaxCapacityKey));
                    NSString *powerState = (__bridge NSString *)CFDictionaryGetValue(powerSource, CFSTR(kIOPSPowerSourceStateKey));
                    
                    if (capacity && maxCapacity) {
                        self.batteryLevel = capacity.doubleValue / maxCapacity.doubleValue;
                        self.batteryStatus = [NSString stringWithFormat:@"%d%%", (int)(self.batteryLevel * 100)];
                        
                        if ([powerState isEqualToString:@"AC Power"]) {
                            self.batteryStatus = [self.batteryStatus stringByAppendingString:@" ⚡"];
                        }
                    }
                }
            }
        }
        
        if (powerSourceInfo) CFRelease(powerSourceInfo);
        if (powerSources) CFRelease(powerSources);
        
        [self setNeedsDisplay:YES];
    });
}

- (void)updateIPAddresses {
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name containsString:@"en"]) {
                    self.localIP = [NSString stringWithUTF8String:
                                  inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *urlString = @"https://api.ipify.org";
        NSURL *url = [NSURL URLWithString:urlString];
        NSString *publicIP = [NSString stringWithContentsOfURL:url
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
        if (publicIP) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.publicIP = publicIP;
                [self setNeedsDisplay:YES];
            });
        }
    });
    
    [self setNeedsDisplay:YES];
}

- (void)drawBatteryIcon:(NSRect)rect {
    NSRect batteryFrame = NSMakeRect(rect.origin.x, rect.origin.y, 30, 15);
    NSRect batteryBody = NSInsetRect(batteryFrame, 1.5, 1.5);
    
    [[NSColor whiteColor] set];
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:batteryFrame xRadius:2 yRadius:2];
    [outline setLineWidth:1.5];
    [outline stroke];
    
    NSRect terminal = NSMakeRect(NSMaxX(batteryFrame), NSMidY(batteryFrame) - 4, 2, 8);
    NSRectFill(terminal);
    
    NSRect levelRect = batteryBody;
    levelRect.size.width *= self.batteryLevel;
    
    NSColor *levelColor;
    if (self.batteryLevel > 0.5) levelColor = [NSColor greenColor];
    else if (self.batteryLevel > 0.2) levelColor = [NSColor yellowColor];
    else levelColor = [NSColor redColor];
    
    [levelColor set];
    NSRectFill(levelRect);
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    
    [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:0.05] set];
    NSRectFill(dirtyRect);
    
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    [attrs setObject:[NSFont fontWithName:@"Helvetica" size:24] forKey:NSFontAttributeName];
    [attrs setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
    
    CGFloat topPadding = 30;
    CGFloat leftPadding = 15;
    NSPoint textPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 24);
    
    [self.currentTime drawAtPoint:textPoint withAttributes:attrs];
    
    [attrs setObject:[NSFont fontWithName:@"Helvetica" size:18] forKey:NSFontAttributeName];
    NSPoint batteryTextPoint = NSMakePoint(leftPadding + 40, NSHeight(self.bounds) - topPadding - 50);
    
    [self drawBatteryIcon:NSMakeRect(leftPadding,
                                    batteryTextPoint.y,
                                    30,
                                    15)];
    
    [self.batteryStatus drawAtPoint:batteryTextPoint withAttributes:attrs];
    
    [attrs setObject:[NSFont fontWithName:@"Helvetica" size:16] forKey:NSFontAttributeName];
    
    NSString *localIPText = [NSString stringWithFormat:@"Local IP: %@", self.localIP];
    NSPoint localIPPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 75);
    [localIPText drawAtPoint:localIPPoint withAttributes:attrs];
    
    NSString *publicIPText = [NSString stringWithFormat:@"Public IP: %@", self.publicIP];
    NSPoint publicIPPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 95);
    [publicIPText drawAtPoint:publicIPPoint withAttributes:attrs];
    
    // Draw author info
    NSString *authorText = @"© vos9.su";
    NSPoint authorPoint = NSMakePoint(NSWidth(self.bounds) - 80, 10);
    [attrs setObject:[NSFont fontWithName:@"Helvetica" size:12] forKey:NSFontAttributeName];
    [attrs setObject:[NSColor colorWithCalibratedWhite:1.0 alpha:0.5] forKey:NSForegroundColorAttributeName];
    [authorText drawAtPoint:authorPoint withAttributes:attrs];
}

- (void)closeButtonClicked:(id)sender {
    [[NSApplication sharedApplication] terminate:self];
    exit(0); // Принудительное завершение, если terminate не сработает
}

- (NSView *)hitTest:(NSPoint)point {
    NSPoint localPoint = [self convertPoint:point fromView:nil];
    if (NSPointInRect(localPoint, self.closeButton.frame)) {
        return [super hitTest:point];
    }
    return nil;
}

- (void)mouseEntered:(NSEvent *)event {
    [[self window] setIgnoresMouseEvents:NO];
}

- (void)mouseExited:(NSEvent *)event {
    [[self window] setIgnoresMouseEvents:YES];
}

- (void)dealloc {
    [self.timer invalidate];
    self.timer = nil;
}

@end