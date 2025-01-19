#import "OverlayView.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#import <SystemConfiguration/SystemConfiguration.h>

// Add callback declaration at the top of the file
static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, 
                                  const CVTimeStamp *now,
                                  const CVTimeStamp *outputTime,
                                  CVOptionFlags flagsIn,
                                  CVOptionFlags *flagsOut,
                                  void *displayLinkContext) {
    OverlayView *view = (__bridge OverlayView *)displayLinkContext;
    dispatch_async(dispatch_get_main_queue(), ^{
        [view handleAnimation];
    });
    return kCVReturnSuccess;
}

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
        
        // Изменяем позицию кнопки закрытия (сдвигаем на 10 пикселей ниже)
        NSRect closeButtonFrame = NSMakeRect(frame.size.width - 30, frame.size.height - 50, 20, 20);
        NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:closeButtonFrame
                                                                   options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
                                                                     owner:self
                                                                  userInfo:nil];
        [self addTrackingArea:trackingArea];
        
        self.closeButton = [[NSButton alloc] initWithFrame:closeButtonFrame];
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
        
        // Initialize new properties
        self.is24HourFormat = YES;
        self.showSeconds = YES;
        self.opacity = 0.05;
        self.fontSize = 24;
        self.networkStatus = @"";
        
        // Register for notifications
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleWakeNotification:)
                                                     name:NSWorkspaceDidWakeNotification
                                                   object:nil];
        
        // Initialize cache
        self.imageCache = [[NSCache alloc] init];
        self.imageCache.countLimit = 10;
        self.lastNetworkUpdate = [NSDate date];
        self.networkTimeout = 30.0;
        self.needsFullRedraw = YES;
        
        // Layer-backed view for better performance
        self.wantsLayer = YES;
        self.layer.drawsAsynchronously = YES;
        
        // Optimize timers
        [self optimizeTimers];
        
        // Initialize calendar
        self.calendar = [NSCalendar currentCalendar];
        self.showCalendar = YES;
        NSDate *now = [NSDate date];
        NSDateComponents *components = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth) fromDate:now];
        self.selectedMonth = components.month;
        self.selectedYear = components.year;
        
        // Initialize holidays (можно расширить список)
        self.holidays = @{
            @"01-01": @"Новый год",
            @"01-07": @"Рождество",
            @"02-23": @"День защитника Отечества",
            @"03-08": @"Международный женский день",
            @"05-01": @"Праздник Весны и Труда",
            @"05-09": @"День Победы",
            @"06-12": @"День России",
            @"11-04": @"День народного единства",
            // Добавьте другие праздники
        };
        
        // Initialize new properties
        self.todayColor = [NSColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0];
        self.selectedDayColor = [NSColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
        self.selectedDay = -1;
        self.animationProgress = 0.0;
        self.isAnimating = NO;

        // Initialize and configure the toggle calendar button
        NSRect toggleButtonFrame = NSMakeRect(frame.size.width - 60, frame.size.height - 50, 20, 20);
        self.toggleCalendarButton = [[NSButton alloc] initWithFrame:toggleButtonFrame];
        [self.toggleCalendarButton setBezelStyle:NSBezelStyleCircular];
        [self.toggleCalendarButton setButtonType:NSButtonTypeMomentaryLight];
        [self.toggleCalendarButton setBordered:YES];
        [self.toggleCalendarButton setTitle:@"C"];
        [self.toggleCalendarButton setFont:[NSFont systemFontOfSize:12]];
        [self.toggleCalendarButton setTarget:self];
        [self.toggleCalendarButton setAction:@selector(toggleCalendarButtonClicked:)];
        [self.toggleCalendarButton setWantsLayer:YES];
        self.toggleCalendarButton.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.0 alpha:0.3] CGColor];
        [self addSubview:self.toggleCalendarButton];

        // Add tracking area for toggle calendar button
        NSTrackingArea *calendarButtonTracking = [[NSTrackingArea alloc] 
            initWithRect:self.toggleCalendarButton.frame
            options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways)
            owner:self
            userInfo:nil];
        [self addTrackingArea:calendarButtonTracking];
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
        
        // Add network status timer
        [NSTimer scheduledTimerWithTimeInterval:10.0
                                       target:self
                                     selector:@selector(updateNetworkStatus)
                                     userInfo:nil
                                      repeats:YES];
        
        [self updateTime];
        [self updateBatteryInfo];
        [self updateNetworkStatus];  // Add initial network status update
    });
}

- (void)optimizeTimers {
    // Use weak timers to prevent retain cycles
    __unsafe_unretained typeof(self) weakSelf = self;
    
    dispatch_queue_t timerQueue = dispatch_queue_create("com.vos9.overlay.timer", DISPATCH_QUEUE_SERIAL);
    
    // Batch timer updates
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, timerQueue);
    dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC, 0.1 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(timer, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf updateTime];
            if (weakSelf.needsFullRedraw) {
                [weakSelf setNeedsDisplay:YES];
            }
        });
    });
    dispatch_resume(timer);
}

- (void)updateTime {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:self.is24HourFormat ? 
            (self.showSeconds ? @"HH:mm:ss" : @"HH:mm") :
            (self.showSeconds ? @"hh:mm:ss a" : @"hh:mm a")];
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

- (void)updateNetworkStatus {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Простая проверка доступности сети через системный домен
        SCNetworkReachabilityRef target = SCNetworkReachabilityCreateWithName(NULL, "www.apple.com");
        SCNetworkReachabilityFlags flags;
        BOOL reachable = NO;
        
        if (target != NULL) {
            if (SCNetworkReachabilityGetFlags(target, &flags)) {
                reachable = (flags & kSCNetworkFlagsReachable) &&
                           !(flags & kSCNetworkFlagsConnectionRequired);
            }
            CFRelease(target);
        }
        
        if (reachable) {
            // Проверка реального подключения через запрос
            NSURL *url = [NSURL URLWithString:@"https://www.apple.com"];
            NSURLRequest *request = [NSURLRequest requestWithURL:url
                                                   cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                               timeoutInterval:3.0];
            
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            __block BOOL hasConnection = NO;
            
            NSURLSession *session = [NSURLSession sharedSession];
            [[session dataTaskWithRequest:request
                      completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (!error && [(NSHTTPURLResponse *)response statusCode] == 200) {
                    hasConnection = YES;
                }
                dispatch_semaphore_signal(semaphore);
            }] resume];
            
            // Ждем ответ не более 3 секунд
            dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC));
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (hasConnection) {
                    self.networkStatus = @"Online ✓";
                } else {
                    self.networkStatus = @"Limited ⚠️";
                }
                [self setNeedsDisplay:YES];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.networkStatus = @"Offline ✖";
                [self setNeedsDisplay:YES];
            });
        }
    });
}

- (void)toggleTimeFormat {
    self.is24HourFormat = !self.is24HourFormat;
    [self updateTime];
}

- (void)increaseOpacity {
    self.opacity = MIN(1.0, self.opacity + 0.05);
    [self setNeedsDisplay:YES];
}

- (void)decreaseOpacity {
    self.opacity = MAX(0.05, self.opacity - 0.05);
    [self setNeedsDisplay:YES];
}

- (void)resetToDefaults {
    self.is24HourFormat = YES;
    self.showSeconds = YES;
    self.opacity = 0.05;
    self.fontSize = 24;
    [self updateTime];
    [self setNeedsDisplay:YES];
}

- (void)handleWakeNotification:(NSNotification *)notification {
    [self updateTime];
    [self updateBatteryInfo];
    [self updateIPAddresses];
    [self updateNetworkStatus];
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
    if (!self.needsFullRedraw && !NSEqualRects(dirtyRect, self.dirtyRect)) {
        [super drawRect:dirtyRect];
        return;
    }
    
    // Кэшируем часто используемые значения
    static NSFont *timeFont = nil;
    static NSFont *statusFont = nil;
    if (!timeFont) {
        timeFont = [NSFont fontWithName:@"Helvetica" size:self.fontSize];
        statusFont = [NSFont fontWithName:@"Helvetica" size:16];
    }
    
    [super drawRect:dirtyRect];
    
    [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:self.opacity] set];
    NSRectFill(dirtyRect);
    
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    [attrs setObject:timeFont forKey:NSFontAttributeName];
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
    
    [attrs setObject:statusFont forKey:NSFontAttributeName];
    
    NSString *localIPText = [NSString stringWithFormat:@"Local IP: %@", self.localIP];
    NSPoint localIPPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 75);
    [localIPText drawAtPoint:localIPPoint withAttributes:attrs];
    
    NSString *publicIPText = [NSString stringWithFormat:@"Public IP: %@", self.publicIP];
    NSPoint publicIPPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 95);
    [publicIPText drawAtPoint:publicIPPoint withAttributes:attrs];
    
    // Draw network status (make sure it's more visible)
    [attrs setObject:statusFont forKey:NSFontAttributeName];
    [attrs setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
    
    NSString *networkText = [NSString stringWithFormat:@"Network: %@", self.networkStatus ?: @"Unknown"];
    NSPoint networkPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 115);
    [networkText drawAtPoint:networkPoint withAttributes:attrs];
    
    // Draw author info
    NSString *authorText = @"© vos9.su";
    NSPoint authorPoint = NSMakePoint(NSWidth(self.bounds) - 80, 10);
    [attrs setObject:[NSFont fontWithName:@"Helvetica" size:12] forKey:NSFontAttributeName];
    [attrs setObject:[NSColor colorWithCalibratedWhite:1.0 alpha:0.5] forKey:NSForegroundColorAttributeName];
    [authorText drawAtPoint:authorPoint withAttributes:attrs];
    
    // Draw calendar if enabled
    if (self.showCalendar) {
        [self drawCalendar];
    }
    
    self.needsFullRedraw = NO;
    self.dirtyRect = dirtyRect;
}

- (void)drawCalendar {
    // Calendar frame parameters
    CGFloat calendarWidth = 220;
    CGFloat calendarHeight = 160;
    CGFloat xOffset = 15;
    CGFloat yOffset = 40;
    
    // Calendar content setup
    NSDateComponents *comp = [[NSDateComponents alloc] init];
    comp.year = self.selectedYear;
    comp.month = self.selectedMonth;
    comp.day = 1;
    
    NSDate *firstDay = [self.calendar dateFromComponents:comp];
    
    // Calendar background with gradient
    NSRect calendarFrame = NSMakeRect(xOffset, yOffset, calendarWidth, calendarHeight);
    
    // Create gradient background
    NSGradient *backgroundGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.4]
                                                                  endingColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.3]];
    
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:calendarFrame xRadius:12 yRadius:12];
    [backgroundGradient drawInBezierPath:background angle:90];
    
    // Draw glass effect
    NSColor *glassColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.1];
    NSRect glassRect = NSMakeRect(xOffset, yOffset + calendarHeight/2, calendarWidth, calendarHeight/2);
    NSGradient *glassGradient = [[NSGradient alloc] initWithStartingColor:glassColor
                                                            endingColor:[NSColor clearColor]];
    [glassGradient drawInRect:glassRect angle:-90];
    
    // Draw month header with gradient
    NSRect headerRect = NSMakeRect(xOffset, yOffset + calendarHeight - 40, calendarWidth, 35);
    NSGradient *headerGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.15]
                                                              endingColor:[NSColor colorWithCalibratedWhite:1.0 alpha:0.05]];
    NSBezierPath *headerPath = [NSBezierPath bezierPathWithRoundedRect:headerRect 
                                                            xRadius:10 
                                                            yRadius:10];
    [headerGradient drawInBezierPath:headerPath angle:90];
    
    // Month and year text with shadow
    NSDateFormatter *monthFormatter = [[NSDateFormatter alloc] init];
    monthFormatter.dateFormat = @"MMMM yyyy";
    NSString *monthYear = [monthFormatter stringFromDate:firstDay];
    
    NSShadow *textShadow = [[NSShadow alloc] init];
    textShadow.shadowColor = [NSColor blackColor];
    textShadow.shadowOffset = NSMakeSize(0, -1);
    textShadow.shadowBlurRadius = 2;
    
    NSDictionary *headerAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:16],
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSShadowAttributeName: textShadow
    };
    
    NSSize monthSize = [monthYear sizeWithAttributes:headerAttrs];
    NSPoint monthPoint = NSMakePoint(xOffset + (calendarWidth - monthSize.width) / 2,
                                   yOffset + calendarHeight - 32);
    [monthYear drawAtPoint:monthPoint withAttributes:headerAttrs];
    
    // Draw rest of calendar content
    NSRange daysRange = [self.calendar rangeOfUnit:NSCalendarUnitDay
                                          inUnit:NSCalendarUnitMonth
                                         forDate:firstDay];
    
    NSInteger totalDays = (NSInteger)daysRange.length;
    NSInteger currentDay = 1;
    NSArray *weekDays = @[@"Пн", @"Вт", @"Ср", @"Чт", @"Пт", @"Сб", @"Вс"];
    
    // Draw weekday headers
    CGFloat dayWidth = calendarWidth / 7;
    CGFloat dayHeight = 25;
    
    NSDictionary *dayAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:12],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    
    for (NSInteger i = 0; i < 7; i++) {
        NSString *dayName = weekDays[i];
        NSPoint dayPoint = NSMakePoint(xOffset + i * dayWidth, yOffset + calendarHeight - 50);
        [dayName drawAtPoint:dayPoint withAttributes:dayAttrs];
    }
    
    // Draw calendar days
    NSInteger weekday = [self.calendar component:NSCalendarUnitWeekday fromDate:firstDay];
    NSInteger adjustedWeekday = (weekday + 5) % 7 + 1;
    NSInteger row = 0;
    
    while (currentDay <= totalDays) {
        for (NSInteger col = 0; col < 7 && currentDay <= totalDays; col++) {
            if (row == 0 && col < adjustedWeekday - 1) {
                continue;
            }
            
            NSString *dayStr = [NSString stringWithFormat:@"%ld", (long)currentDay];
            NSPoint dayPoint = NSMakePoint(xOffset + col * dayWidth,
                                         yOffset + calendarHeight - 75 - row * dayHeight);
            
            NSString *dateKey = [NSString stringWithFormat:@"%02ld-%02ld",
                               (long)self.selectedMonth, (long)currentDay];
            
            NSDateComponents *todayComponents = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                                                fromDate:[NSDate date]];
            if (todayComponents.year == self.selectedYear &&
                todayComponents.month == self.selectedMonth &&
                todayComponents.day == currentDay) {
                [self.todayColor set];
                NSRectFill(NSMakeRect(dayPoint.x, dayPoint.y, dayWidth, dayHeight));
            }
            
            if (self.holidays[dateKey]) {
                // Holiday styling
                NSDictionary *holidayAttrs = @{
                    NSFontAttributeName: [NSFont boldSystemFontOfSize:12],
                    NSForegroundColorAttributeName: [NSColor redColor]
                };
                [dayStr drawAtPoint:dayPoint withAttributes:holidayAttrs];
            } else {
                [dayStr drawAtPoint:dayPoint withAttributes:dayAttrs];
            }
            
            currentDay++;
        }
        row++;
    }
    
    // Apply animation effects
    CGFloat scale = 0.8 + (0.2 * self.animationProgress);
    CGFloat alpha = self.animationProgress;
    
    NSShadow *animShadow = [[NSShadow alloc] init];
    animShadow.shadowColor = [NSColor colorWithWhite:0.0 alpha:0.5 * alpha];
    animShadow.shadowOffset = NSMakeSize(0, -2 * scale);
    animShadow.shadowBlurRadius = 4.0 * scale;
    [animShadow set];
    
    // ...rest of existing code...
}

- (NSInteger)daysInCurrentMonth {
    NSDateComponents *comp = [[NSDateComponents alloc] init];
    comp.year = self.selectedYear;
    comp.month = self.selectedMonth;
    comp.day = 1;
    
    NSDate *firstDay = [self.calendar dateFromComponents:comp];
    NSRange range = [self.calendar rangeOfUnit:NSCalendarUnitDay
                                      inUnit:NSCalendarUnitMonth
                                     forDate:firstDay];
    
    return range.length;
}

- (void)animateCalendarOpen {
    if (self.isAnimating) return;
    
    self.isAnimating = YES;
    self.animationProgress = 0.0;
    
    if (!self.displayLink) {
        CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
        CVDisplayLinkSetOutputCallback(self.displayLink, DisplayLinkCallback, (__bridge void *)self);
    }
    CVDisplayLinkStart(self.displayLink);
}

- (void)animateCalendarClose {
    if (self.isAnimating) return;
    
    self.isAnimating = YES;
    self.animationProgress = 1.0;
    
    if (!self.displayLink) {
        CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
        CVDisplayLinkSetOutputCallback(self.displayLink, DisplayLinkCallback, (__bridge void *)self);
    }
    CVDisplayLinkStart(self.displayLink);
}

- (void)handleAnimation {
    if (self.showCalendar) {
        self.animationProgress = MIN(1.0, self.animationProgress + 0.1);
        if (self.animationProgress >= 1.0) {
            CVDisplayLinkStop(self.displayLink);
            self.isAnimating = NO;
        }
    } else {
        self.animationProgress = MAX(0.0, self.animationProgress - 0.1);
        if (self.animationProgress <= 0.0) {
            CVDisplayLinkStop(self.displayLink);
            self.isAnimating = NO;
        }
    }
    [self setNeedsDisplay:YES];
}

- (void)updateCalendar {
    NSDate *now = [NSDate date];
    NSDateComponents *components = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth)
                                                 fromDate:now];
    self.selectedMonth = components.month;
    self.selectedYear = components.year;
    [self setNeedsDisplay:YES];
}

- (void)toggleCalendar {
    self.showCalendar = !self.showCalendar;
    [self setNeedsDisplay:YES];
}

- (void)nextMonth {
    self.selectedMonth++;
    if (self.selectedMonth > 12) {
        self.selectedMonth = 1;
        self.selectedYear++;
    }
    [self setNeedsDisplay:YES];
}

- (void)previousMonth {
    self.selectedMonth--;
    if (self.selectedMonth < 1) {
        self.selectedMonth = 12;
        self.selectedYear--;
    }
    [self setNeedsDisplay:YES];
}

- (BOOL)isHoliday:(NSDate *)date {
    NSDateComponents *components = [self.calendar components:(NSCalendarUnitMonth | NSCalendarUnitDay)
                                                 fromDate:date];
    NSString *dateKey = [NSString stringWithFormat:@"%02ld-%02ld",
                        (long)components.month, (long)components.day];
    return self.holidays[dateKey] != nil;
}

- (void)selectDate:(NSDate *)date {
    NSDateComponents *components = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                                 fromDate:date];
    
    if (components.year != self.selectedYear || components.month != self.selectedMonth) {
        self.selectedYear = components.year;
        self.selectedMonth = components.month;
    }
    
    self.selectedDay = components.day;
    [self setNeedsDisplay:YES];
}

- (void)closeButtonClicked:(id)sender {
    [[NSApplication sharedApplication] terminate:self];
    exit(0); // Принудительное завершение, если terminate не сработает
}

- (NSView *)hitTest:(NSPoint)point {
    NSPoint localPoint = [self convertPoint:point fromView:nil];
    if (NSPointInRect(localPoint, self.closeButton.frame) ||
        NSPointInRect(localPoint, self.toggleCalendarButton.frame)) {
        return [super hitTest:point];
    }
    return nil;
}

- (void)mouseEntered:(NSEvent *)event {
    NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
    if (NSPointInRect(location, self.closeButton.frame) ||
        NSPointInRect(location, self.toggleCalendarButton.frame)) {
        [[self window] setIgnoresMouseEvents:NO];
    }
}

- (void)mouseExited:(NSEvent *)event {
    [[self window] setIgnoresMouseEvents:YES];
}

- (void)mouseDown:(NSEvent *)event {
    if (self.showCalendar) {
        NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
        [self handleCalendarClick:point];
    }
}

- (void)handleCalendarClick:(NSPoint)point {
    // Calendar frame parameters
    CGFloat calendarWidth = 280;
    CGFloat calendarHeight = 200;
    CGFloat xOffset = 15;
    CGFloat yOffset = 40;
    
    // Convert point to calendar coordinates
    CGFloat relativeX = point.x - xOffset;
    CGFloat relativeY = point.y - yOffset;
    
    // Check if click is within calendar bounds
    if (relativeX < 0 || relativeX > calendarWidth ||
        relativeY < 0 || relativeY > calendarHeight) {
        return;
    }
    
    // Calculate day area
    CGFloat dayWidth = calendarWidth / 7;
    CGFloat dayHeight = 25;
    CGFloat headerHeight = 65; // Space for month name and weekday headers
    
    // Adjust for header area
    if (relativeY > calendarHeight - headerHeight) {
        return; // Click in header area
    }
    
    // Calculate row and column
    NSInteger col = floor(relativeX / dayWidth);
    NSInteger row = floor((calendarHeight - relativeY - headerHeight) / dayHeight);
    
    // Get first day of month info
    NSDateComponents *comp = [[NSDateComponents alloc] init];
    comp.year = self.selectedYear;
    comp.month = self.selectedMonth;
    comp.day = 1;
    
    NSDate *firstDay = [self.calendar dateFromComponents:comp];
    NSInteger firstWeekday = [self.calendar component:NSCalendarUnitWeekday fromDate:firstDay];
    NSInteger adjustedWeekday = (firstWeekday + 5) % 7 + 1;
    
    // Calculate clicked day
    NSInteger clickedDay = row * 7 + col + 1 - (adjustedWeekday - 1);
    
    if (clickedDay > 0 && clickedDay <= [self daysInCurrentMonth]) {
        self.selectedDay = clickedDay;
        [self setNeedsDisplay:YES];
    }
}

- (void)dealloc {
    if (self.displayLink) {
        CVDisplayLinkStop(self.displayLink);
        CVDisplayLinkRelease(self.displayLink);
    }
    [self.timer invalidate];
    self.timer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)suspendUpdates {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)resumeUpdates {
    [self optimizeTimers];
    [self updateTime];
    [self updateNetworkStatus];
}

- (void)invalidateCache {
    [self.imageCache removeAllObjects];
    self.needsFullRedraw = YES;
    [self setNeedsDisplay:YES];
}

- (void)toggleCalendarButtonClicked:(id)sender {
    if (self.isAnimating) return;
    
    self.showCalendar = !self.showCalendar;
    
    if (self.showCalendar) {
        [self animateCalendarOpen];
    } else {
        [self animateCalendarClose];
    }
    
    [self setNeedsDisplay:YES];
}

@end