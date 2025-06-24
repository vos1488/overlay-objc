#import "OverlayView.h"
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <mach/mach.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach_host.h>
#import <mach/processor_info.h>
#import <mach/mach_time.h>
#include <sys/sysctl.h>

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

#define SMC_KEY_CPU_TEMP "TC0P"
#define SMC_KEY_FAN_SPEED "F0Ac"

typedef struct {
    char major;
    char minor;
    char build;
    char reserved[1];
    UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
    UInt32 key;
    SMCKeyData_vers_t vers;
    UInt8 length;
    UInt8 dataType[4];
    UInt32 dataSize;
    UInt8 data[32];
} SMCKeyData_t;

typedef struct {
    host_t host;
    processor_info_array_t processor_info;
    mach_msg_type_number_t processor_count;
    processor_cpu_load_info_data_t prev_load;
    uint64_t prev_time;
} CPUInfo;

static CPUInfo cpuInfo = {0};

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
        self.isCompactMode = NO;  // По умолчанию полный режим
        
        // Initialize settings properties
        self.showNetworkInfo = YES;
        self.showSystemInfo = YES;
        self.showCalendarByDefault = NO;
        self.refreshRate = 1;
        self.backgroundOpacity = 0.05;
        
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

        // Initialize power monitoring properties
        self.cpuUsage = 0.0;
        self.powerConsumption = 0.0;
        self.powerUsageStatus = @"";
        
        // Start power monitoring
        [self startPowerMonitoring];
        
        [self setupControlButtons];
        self.isDarkTheme = YES; // По умолчанию тёмная тема

        // Initialize network monitoring
        self.lastBytesIn = 0;
        self.lastBytesOut = 0;
        self.lastNetworkCheck = [NSDate timeIntervalSinceReferenceDate];
        
        // Start network monitoring timer
        self.networkUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                 target:self
                                                               selector:@selector(updateNetworkThroughput)
                                                               userInfo:nil
                                                                repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self.networkUpdateTimer forMode:NSRunLoopCommonModes];

        self.memoryUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                                  target:self
                                                                selector:@selector(updateMemoryUsage)
                                                                userInfo:nil
                                                                 repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:self.memoryUpdateTimer forMode:NSRunLoopCommonModes];
        
        // Load saved settings
        [self loadSettings];
    }
    return self;
}

- (void)setupControlButtons {
    NSRect frame = self.frame;
    CGFloat buttonSize = 20;
    CGFloat spacing = 25;
    CGFloat topMargin = frame.size.height - 50;
    
    // Сдвигаем все кнопки правее, начиная с правого края
    CGFloat rightEdge = frame.size.width - 30;
    
    // Close button (самая правая) - всегда видна
    if (!self.closeButton) {
        self.closeButton = [self createButtonWithFrame:NSMakeRect(rightEdge, topMargin, buttonSize, buttonSize)
                                               title:@"✕"
                                             action:@selector(closeButtonClicked:)];
    } else {
        self.closeButton.frame = NSMakeRect(rightEdge, topMargin, buttonSize, buttonSize);
    }
    
    // Settings button - скрывается в компактном режиме
    rightEdge -= spacing;
    if (!self.settingsButton) {
        self.settingsButton = [self createButtonWithFrame:NSMakeRect(rightEdge, topMargin, buttonSize, buttonSize)
                                                   title:@"⚙"
                                                 action:@selector(handleSettingsButton:)];
    } else {
        self.settingsButton.frame = NSMakeRect(rightEdge, topMargin, buttonSize, buttonSize);
    }
    
    // Устанавливаем видимость кнопок в зависимости от режима
    self.closeButton.hidden = NO;  // Кнопка закрытия всегда видна
    self.settingsButton.hidden = self.isCompactMode;  // Настройки скрыты в компактном режиме
    
    // Add tracking areas for all buttons after creating them
    [self updateTrackingAreas];
}

- (NSButton *)createButtonWithFrame:(NSRect)frame title:(NSString *)title action:(SEL)action {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    [button setBezelStyle:NSBezelStyleCircular];
    [button setButtonType:NSButtonTypeMomentaryLight];
    [button setBordered:YES];
    [button setTitle:title];
    [button setFont:[NSFont systemFontOfSize:12]];
    [button setTarget:self];
    [button setAction:action];
    [button setWantsLayer:YES];
    button.layer.backgroundColor = [[NSColor colorWithCalibratedWhite:0.0 alpha:0.3] CGColor];
    [self addSubview:button];
    
    return button;
}

- (void)handleTimeFormatButton:(id)sender {
    [self toggleTimeFormat];
}

- (void)handleRefreshButton:(id)sender {
    [self updateTime];
    [self updateBatteryInfo];
    [self updateIPAddresses];
    [self updateNetworkStatus];
    [self updateMemoryUsage];
    [self updateNetworkThroughput];
    [self updateCPUTemperature];
    [self setNeedsDisplay:YES];
}

- (void)handleSettingsButton:(id)sender {
    [self showSettingsDialog];
}

- (void)showSettingsDialog {
    [self showAdvancedSettingsWindow];
}

- (void)showAdvancedSettingsWindow {
    if (!self.settingsWindow) {
        [self createSettingsWindow];
    }
    
    [self.settingsWindow makeKeyAndOrderFront:nil];
    [self.settingsWindow center];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)createSettingsWindow {
    // Создаем окно настроек
    NSRect windowFrame = NSMakeRect(0, 0, 500, 600);
    self.settingsWindow = [[NSWindow alloc] initWithContentRect:windowFrame
                                                     styleMask:(NSWindowStyleMaskTitled | 
                                                               NSWindowStyleMaskClosable | 
                                                               NSWindowStyleMaskMiniaturizable)
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
    
    [self.settingsWindow setTitle:@"Overlay Settings"];
    [self.settingsWindow setReleasedWhenClosed:NO];
    
    // Создаем табы для группировки настроек
    NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(20, 20, 460, 520)];
    [tabView setTabViewType:NSTopTabsBezelBorder];
    
    // Вкладка "Отображение"
    NSTabViewItem *displayTab = [[NSTabViewItem alloc] initWithIdentifier:@"display"];
    [displayTab setLabel:@"🎨 Отображение"];
    NSView *displayView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 490)];
    [self setupDisplaySettings:displayView];
    [displayTab setView:displayView];
    [tabView addTabViewItem:displayTab];
    
    // Вкладка "Система"
    NSTabViewItem *systemTab = [[NSTabViewItem alloc] initWithIdentifier:@"system"];
    [systemTab setLabel:@"⚙️ Система"];
    NSView *systemView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 490)];
    [self setupSystemSettings:systemView];
    [systemTab setView:systemView];
    [tabView addTabViewItem:systemTab];
    
    // Вкладка "Время"
    NSTabViewItem *timeTab = [[NSTabViewItem alloc] initWithIdentifier:@"time"];
    [timeTab setLabel:@"🕒 Время"];
    NSView *timeView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 490)];
    [self setupTimeSettings:timeView];
    [timeTab setView:timeView];
    [tabView addTabViewItem:timeTab];
    
    // Вкладка "Дополнительно"
    NSTabViewItem *advancedTab = [[NSTabViewItem alloc] initWithIdentifier:@"advanced"];
    [advancedTab setLabel:@"🔧 Дополнительно"];
    NSView *advancedView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 490)];
    [self setupAdvancedSettings:advancedView];
    [advancedTab setView:advancedView];
    [tabView addTabViewItem:advancedTab];
    
    // Кнопки управления
    NSButton *saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(300, 550, 80, 30)];
    [saveButton setTitle:@"💾 Сохранить"];
    [saveButton setTarget:self];
    [saveButton setAction:@selector(applySettings)];
    [saveButton setKeyEquivalent:@"\r"];
    
    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(390, 550, 80, 30)];
    [cancelButton setTitle:@"❌ Отмена"];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(closeSettingsWindow:)];
    [cancelButton setKeyEquivalent:@"\033"];
    
    NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, 550, 120, 30)];
    [resetButton setTitle:@"🔄 Сбросить"];
    [resetButton setTarget:self];
    [resetButton setAction:@selector(resetSettingsToDefaults)];
    
    // Добавляем элементы в окно
    [[self.settingsWindow contentView] addSubview:tabView];
    [[self.settingsWindow contentView] addSubview:saveButton];
    [[self.settingsWindow contentView] addSubview:cancelButton];
    [[self.settingsWindow contentView] addSubview:resetButton];
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
    
    [super drawRect:dirtyRect];
    
    // Прозрачный фон
    [[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:self.opacity] set];
    NSRectFill(dirtyRect);
    
    // Проверяем режим отображения
    if (self.isCompactMode) {
        [self drawCompactMode];
    } else {
        [self drawFullMode];
    }
    
    // Календарь отображается в любом режиме
    if (self.showCalendar) {
        [self drawCalendar];
    }
    
    self.needsFullRedraw = NO;
    self.dirtyRect = dirtyRect;
}

- (void)drawCompactMode {
    // Компактный режим - минимальная информация в одной строке в верхней части экрана
    CGFloat topMargin = 20;
    CGFloat compactHeight = 30;
    CGFloat leftPadding = 20;
    CGFloat rightPadding = 20;
    
    // Создаем полупрозрачную панель для компактного режима
    NSRect compactRect = NSMakeRect(leftPadding, 
                                   NSHeight(self.bounds) - topMargin - compactHeight,
                                   NSWidth(self.bounds) - leftPadding - rightPadding,
                                   compactHeight);
    
    // Фон панели с округлыми углами
    NSBezierPath *compactPath = [NSBezierPath bezierPathWithRoundedRect:compactRect xRadius:15 yRadius:15];
    [[NSColor colorWithCalibratedWhite:0.0 alpha:0.3] set];
    [compactPath fill];
    
    // Рамка панели
    [[NSColor colorWithCalibratedWhite:1.0 alpha:0.2] set];
    [compactPath setLineWidth:1.0];
    [compactPath stroke];
    
    // Форматируем компактную информацию
    NSString *timeText = self.currentTime ?: @"--:--";
    NSString *batteryText = [NSString stringWithFormat:@"🔋%.0f%%", self.batteryLevel * 100];
    NSString *memoryText = [NSString stringWithFormat:@"💾%.1fGB", self.memoryUsage / 1024.0];
    NSString *cpuText = [NSString stringWithFormat:@"⚡%.0f%%", self.cpuUsage];
    
    // Собираем все в одну строку
    NSString *compactInfo = [NSString stringWithFormat:@"%@ • %@ • %@ • %@", 
                            timeText, batteryText, memoryText, cpuText];
    
    // Атрибуты текста
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    
    // Центрируем текст в панели
    NSSize textSize = [compactInfo sizeWithAttributes:attrs];
    CGFloat textX = compactRect.origin.x + (compactRect.size.width - textSize.width) / 2.0;
    CGFloat textY = compactRect.origin.y + (compactRect.size.height - textSize.height) / 2.0;
    
    [compactInfo drawAtPoint:NSMakePoint(textX, textY) withAttributes:attrs];
    
    // Добавляем индикатор активности в правом углу
    NSRect activityRect = NSMakeRect(NSWidth(self.bounds) - 35, 
                                    NSHeight(self.bounds) - 35, 
                                    10, 10);
    NSBezierPath *activityPath = [NSBezierPath bezierPathWithOvalInRect:activityRect];
    [[NSColor colorWithRed:0.0 green:0.8 blue:0.2 alpha:0.8] set];
    [activityPath fill];
}

- (void)drawFullMode {
    // Кэшируем часто используемые значения
    static NSFont *timeFont = nil;
    static NSFont *statusFont = nil;
    if (!timeFont) {
        timeFont = [NSFont fontWithName:@"Helvetica" size:self.fontSize];
        statusFont = [NSFont fontWithName:@"Helvetica" size:16];
    }
    
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
    
    [attrs setObject:statusFont forKey:NSFontAttributeName];
    [attrs setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
    
    NSString *networkText = [NSString stringWithFormat:@"Network: %@", self.networkStatus ?: @"Unknown"];
    NSPoint networkPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 115);
    [networkText drawAtPoint:networkPoint withAttributes:attrs];
    
    NSString *powerText = [NSString stringWithFormat:@"Энергопотребление: %@", self.powerUsageStatus];
    NSPoint powerPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 135);
    [powerText drawAtPoint:powerPoint withAttributes:attrs];
    
    NSString *memoryText = [NSString stringWithFormat:@"Memory: %@ / %@",
                           [self formatMemorySize:self.memoryUsage],
                           [self formatMemorySize:self.memoryTotal]];
    NSPoint memoryPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 155);
    [memoryText drawAtPoint:memoryPoint withAttributes:attrs];
    
    NSString *networkThroughputText = [NSString stringWithFormat:@"Network: %@", 
                           self.networkThroughput ?: @"N/A"];
    NSPoint networkThroughputPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 175);
    [networkThroughputText drawAtPoint:networkThroughputPoint withAttributes:attrs];
    
    if (self.cpuTemp > 0) {
        NSString *tempText = [NSString stringWithFormat:@"CPU Temp: %.1f°C", 
                            self.cpuTemp];
        NSPoint tempPoint = NSMakePoint(leftPadding, NSHeight(self.bounds) - topPadding - 195);
        [tempText drawAtPoint:tempPoint withAttributes:attrs];
    }
    
    NSString *authorText = @"© vos9.su";
    NSPoint authorPoint = NSMakePoint(NSWidth(self.bounds) - 80, 10);
    [attrs setObject:[NSFont fontWithName:@"Helvetica" size:12] forKey:NSFontAttributeName];
    [attrs setObject:[NSColor colorWithCalibratedWhite:1.0 alpha:0.5] forKey:NSForegroundColorAttributeName];
    [authorText drawAtPoint:authorPoint withAttributes:attrs];
}

- (void)drawCalendar {
    CGFloat calendarWidth = 220;
    CGFloat calendarHeight = 200; // Увеличиваем высоту
    CGFloat xOffset = 15;
    CGFloat yOffset = 40;
    
    NSDateComponents *comp = [[NSDateComponents alloc] init];
    comp.year = self.selectedYear;
    comp.month = self.selectedMonth;
    comp.day = 1;
    
    NSDate *firstDay = [self.calendar dateFromComponents:comp];
    NSRect calendarFrame = NSMakeRect(xOffset, yOffset, calendarWidth, calendarHeight);

    // Основной фон календаря (темный с градиентом)
    NSGradient *backgroundGradient;
    if (self.isDarkTheme) {
        backgroundGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95]
                                                          endingColor:[NSColor colorWithRed:0.15 green:0.15 blue:0.2 alpha:0.95]];
    } else {
        backgroundGradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithRed:0.95 green:0.95 blue:1.0 alpha:0.95]
                                                          endingColor:[NSColor colorWithRed:0.9 green:0.9 blue:0.95 alpha:0.95]];
    }
    
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:calendarFrame xRadius:15 yRadius:15];
    [backgroundGradient drawInBezierPath:background angle:90];
    
    // Эффект внутреннего свечения
    NSColor *glowColor = self.isDarkTheme ? 
        [NSColor colorWithRed:0.3 green:0.3 blue:0.4 alpha:0.1] :
        [NSColor colorWithRed:0.7 green:0.7 blue:0.8 alpha:0.1];
    NSRect glowRect = NSInsetRect(calendarFrame, -2, -2);
    NSBezierPath *glowPath = [NSBezierPath bezierPathWithRoundedRect:glowRect xRadius:15 yRadius:15];
    [glowColor set];
    [glowPath setLineWidth:2.0];
    [glowPath stroke];
    
    // Заголовок календаря
    NSRect headerRect = NSMakeRect(xOffset, yOffset + calendarHeight - 40, calendarWidth, 35);
    NSGradient *headerGradient;
    if (self.isDarkTheme) {
        headerGradient = [[NSGradient alloc] initWithColors:@[
            [NSColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:0.9],
            [NSColor colorWithRed:0.15 green:0.15 blue:0.2 alpha:0.9]
        ]];
    } else {
        headerGradient = [[NSGradient alloc] initWithColors:@[
            [NSColor colorWithRed:0.85 green:0.85 blue:0.9 alpha:0.9],
            [NSColor colorWithRed:0.8 green:0.8 blue:0.85 alpha:0.9]
        ]];
    }
    NSBezierPath *headerPath = [NSBezierPath bezierPathWithRoundedRect:headerRect xRadius:12 yRadius:12];
    [headerGradient drawInBezierPath:headerPath angle:90];
    
    // Форматирование и отображение месяца/года
    NSDateFormatter *monthFormatter = [[NSDateFormatter alloc] init];
    monthFormatter.dateFormat = @"MMMM yyyy";
    NSString *monthYear = [[monthFormatter stringFromDate:firstDay] capitalizedString];
    
    NSShadow *textShadow = [[NSShadow alloc] init];
    textShadow.shadowColor = [NSColor colorWithWhite:0.0 alpha:0.5];
    textShadow.shadowOffset = NSMakeSize(0, -1);
    textShadow.shadowBlurRadius = 2;
    
    NSDictionary *headerAttrs = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:16],
        NSForegroundColorAttributeName: self.isDarkTheme ? 
            [NSColor colorWithRed:0.9 green:0.9 blue:1.0 alpha:1.0] :
            [NSColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:1.0],
        NSShadowAttributeName: textShadow
    };
    
    NSSize monthSize = [monthYear sizeWithAttributes:headerAttrs];
    NSPoint monthPoint = NSMakePoint(xOffset + (calendarWidth - monthSize.width) / 2,
                                   yOffset + calendarHeight - 32);
    [monthYear drawAtPoint:monthPoint withAttributes:headerAttrs];

    // Дни недели
    NSArray *weekDays = @[@"ПН", @"ВТ", @"СР", @"ЧТ", @"ПТ", @"СБ", @"ВС"];
    CGFloat dayWidth = calendarWidth / 7;
    CGFloat dayHeight = 28; // Увеличиваем высоту ячейки
    
    NSDictionary *weekdayAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11],
        NSForegroundColorAttributeName: self.isDarkTheme ?
            [NSColor colorWithRed:0.6 green:0.6 blue:0.7 alpha:1.0] :
            [NSColor colorWithRed:0.4 green:0.4 blue:0.5 alpha:1.0]
    };
    
    for (NSInteger i = 0; i < 7; i++) {
        NSString *dayName = weekDays[i];
        NSPoint dayPoint = NSMakePoint(xOffset + i * dayWidth + (dayWidth - [dayName sizeWithAttributes:weekdayAttrs].width) / 2,
                                     yOffset + calendarHeight - 60);
        [dayName drawAtPoint:dayPoint withAttributes:weekdayAttrs];
    }

    // Числа месяца
    NSRange daysRange = [self.calendar rangeOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitMonth forDate:firstDay];
    NSInteger totalDays = (NSInteger)daysRange.length; // Явное приведение типа
    NSInteger weekday = [self.calendar component:NSCalendarUnitWeekday fromDate:firstDay];
    NSInteger adjustedWeekday = (weekday + 5) % 7 + 1;
    NSInteger row = 0;
    NSInteger currentDay = 1;
    
    // Добавляем объявление todayComponents
    NSDateComponents *todayComponents = [self.calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay)
                                                     fromDate:[NSDate date]];
    
    while (currentDay <= totalDays) { // Используем totalDays вместо daysRange.length
        for (NSInteger col = 0; col < 7 && currentDay <= totalDays; col++) { // Используем totalDays
            if (row == 0 && col < adjustedWeekday - 1) {
                continue;
            }
            
            NSString *dayStr = [NSString stringWithFormat:@"%ld", (long)currentDay];
            CGFloat x = xOffset + col * dayWidth;
            CGFloat y = yOffset + calendarHeight - 85 - row * dayHeight;
            NSRect dayRect = NSMakeRect(x, y, dayWidth, dayHeight);
            
            // Определяем стиль для текущего дня
            BOOL isToday = (todayComponents.year == self.selectedYear &&
                           todayComponents.month == self.selectedMonth &&
                           todayComponents.day == currentDay);
            
            BOOL isSelected = (currentDay == self.selectedDay);
            
            if (isToday) {
                // Фон для текущего дня
                NSBezierPath *todayPath = [NSBezierPath bezierPathWithRoundedRect:
                                         NSInsetRect(dayRect, 2, 2) xRadius:8 yRadius:8];
                [[NSColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.3] set];
                [todayPath fill];
            } else if (isSelected) {
                // Фон для выбранного дня
                NSBezierPath *selectedPath = [NSBezierPath bezierPathWithRoundedRect:
                                            NSInsetRect(dayRect, 2, 2) xRadius:8 yRadius:8];
                [[NSColor colorWithRed:0.8 green:0.4 blue:0.0 alpha:0.3] set];
                [selectedPath fill];
            }
            
            // Проверяем, является ли день праздником
            NSString *dateKey = [NSString stringWithFormat:@"%02ld-%02ld",
                               (long)self.selectedMonth, (long)currentDay];
            BOOL isHoliday = (self.holidays[dateKey] != nil);
            
            NSDictionary *dayAttrs;
            if (isHoliday) {
                dayAttrs = @{
                    NSFontAttributeName: [NSFont boldSystemFontOfSize:13],
                    NSForegroundColorAttributeName: [NSColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0]
                };
            } else if (isToday) {
                dayAttrs = @{
                    NSFontAttributeName: [NSFont boldSystemFontOfSize:13],
                    NSForegroundColorAttributeName: self.isDarkTheme ?
                        [NSColor colorWithRed:0.4 green:0.8 blue:1.0 alpha:1.0] :
                        [NSColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0]
                };
            } else {
                dayAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:13],
                    NSForegroundColorAttributeName: self.isDarkTheme ?
                        [NSColor colorWithWhite:0.9 alpha:1.0] :
                        [NSColor colorWithWhite:0.2 alpha:1.0]
                };
            }
            
            NSSize daySize = [dayStr sizeWithAttributes:dayAttrs];
            NSPoint dayPoint = NSMakePoint(x + (dayWidth - daySize.width) / 2,
                                         y + (dayHeight - daySize.height) / 2);
            [dayStr drawAtPoint:dayPoint withAttributes:dayAttrs];
            
            currentDay++;
        }
        row++;
    }
    
    // Применяем анимацию
    if (self.isAnimating) {
        CGFloat scale = 0.8 + (0.2 * self.animationProgress);
        CGFloat alpha = self.animationProgress;
        
        NSShadow *animShadow = [[NSShadow alloc] init];
        animShadow.shadowColor = [NSColor colorWithWhite:0.0 alpha:0.3 * alpha];
        animShadow.shadowOffset = NSMakeSize(0, -3 * scale);
        animShadow.shadowBlurRadius = 6.0 * scale;
        [animShadow set];
    }
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
    
    return (NSInteger)range.length; // Явное приведение типа
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
    exit(0);
}

- (NSView *)hitTest:(NSPoint)point {
    NSPoint localPoint = [self convertPoint:point fromView:nil];
    
    NSArray *buttons = @[
        self.closeButton,
        self.settingsButton
    ];
    
    for (NSButton *button in buttons) {
        if (NSPointInRect(localPoint, button.frame)) {
            return [super hitTest:point];
        }
    }
    
    return nil;
}

- (void)mouseEntered:(NSEvent *)event {
    NSWindow *window = [self window];
    NSPoint location = [self convertPoint:[event locationInWindow] fromView:nil];
    
    NSArray *buttons = @[
        self.closeButton,
        self.settingsButton
    ];
    
    for (NSButton *button in buttons) {
        if (NSPointInRect(location, button.frame)) {
            [window setIgnoresMouseEvents:NO];
            return;
        }
    }
    
    [window setIgnoresMouseEvents:YES];
}

- (void)mouseExited:(NSEvent *)event {
    [[self window] setIgnoresMouseEvents:YES];
}

- (void)updateTrackingAreas {
    // Remove existing tracking areas
    for (NSTrackingArea *area in [self trackingAreas]) {
        [self removeTrackingArea:area];
    }
    
    NSArray *buttons = @[
        self.closeButton,
        self.settingsButton
    ];
    
    // Создаем области отслеживания только для кнопок
    for (NSButton *button in buttons) {
        if (button) {
            NSTrackingArea *area = [[NSTrackingArea alloc] 
                initWithRect:button.frame
                    options:(NSTrackingMouseEnteredAndExited | 
                            NSTrackingActiveAlways | 
                            NSTrackingMouseMoved)
                      owner:self
                   userInfo:nil];
            [self addTrackingArea:area];
        }
    }
}

- (void)mouseDown:(NSEvent *)event {
    if (self.showCalendar) {
        NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
        [self handleCalendarClick:point];
    }
}

- (void)handleCalendarClick:(NSPoint)point {
    CGFloat calendarWidth = 280;
    CGFloat calendarHeight = 200;
    CGFloat xOffset = 15;
    CGFloat yOffset = 40;

    CGFloat relativeX = point.x - xOffset;
    CGFloat relativeY = point.y - yOffset;

    if (relativeX < 0 || relativeX > calendarWidth ||
        relativeY < 0 || relativeY > calendarHeight) {
        return;
    }
    
    CGFloat dayWidth = calendarWidth / 7;
    CGFloat dayHeight = 25;
    CGFloat headerHeight = 65;

    if (relativeY > calendarHeight - headerHeight) {
        return;
    }

    NSInteger col = floor(relativeX / dayWidth);
    NSInteger row = floor((calendarHeight - relativeY - headerHeight) / dayHeight);

    NSDateComponents *comp = [[NSDateComponents alloc] init];
    comp.year = self.selectedYear;
    comp.month = self.selectedMonth;
    comp.day = 1;
    
    NSDate *firstDay = [self.calendar dateFromComponents:comp];
    NSInteger firstWeekday = [self.calendar component:NSCalendarUnitWeekday fromDate:firstDay];
    NSInteger adjustedWeekday = (firstWeekday + 5) % 7 + 1;

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
    [self stopPowerMonitoring];
    [self.networkUpdateTimer invalidate];
    self.networkUpdateTimer = nil;
    [self.memoryUpdateTimer invalidate];
    self.memoryUpdateTimer = nil;
    // Note: [super dealloc] not needed with ARC
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

- (void)startPowerMonitoring {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:2.0
                                       target:self
                                     selector:@selector(updatePowerConsumption)
                                     userInfo:nil
                                      repeats:YES];
        [self updatePowerConsumption];
    });
}

- (void)initCPUInfo {
    cpuInfo.host = mach_host_self();
    natural_t processorCount;
    kern_return_t kr = host_processor_info(cpuInfo.host,
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &processorCount,
                                         &cpuInfo.processor_info,
                                         &cpuInfo.processor_count);
    
    if (kr == KERN_SUCCESS) {
        processor_cpu_load_info_t processorInfo = (processor_cpu_load_info_t)cpuInfo.processor_info;
        cpuInfo.prev_load = processorInfo[0];
        cpuInfo.prev_time = mach_absolute_time();
    }
}

- (float)calculateCPUUsage {
    processor_cpu_load_info_data_t new_load;
    processor_info_array_t processorInfo;
    mach_msg_type_number_t processorMsgCount;
    natural_t processorCount;
    
    kern_return_t kr = host_processor_info(cpuInfo.host,
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &processorCount,
                                         &processorInfo,
                                         &processorMsgCount);
    
    if (kr != KERN_SUCCESS) {
        return -1.0;
    }
    
    new_load = ((processor_cpu_load_info_t)processorInfo)[0];
    
    natural_t user = new_load.cpu_ticks[CPU_STATE_USER] - cpuInfo.prev_load.cpu_ticks[CPU_STATE_USER];
    natural_t system = new_load.cpu_ticks[CPU_STATE_SYSTEM] - cpuInfo.prev_load.cpu_ticks[CPU_STATE_SYSTEM];
    natural_t idle = new_load.cpu_ticks[CPU_STATE_IDLE] - cpuInfo.prev_load.cpu_ticks[CPU_STATE_IDLE];
    natural_t nice = new_load.cpu_ticks[CPU_STATE_NICE] - cpuInfo.prev_load.cpu_ticks[CPU_STATE_NICE];
    
    natural_t total = user + system + idle + nice;
    float usage = total > 0 ? ((float)(user + system + nice) / total) * 100.0 : 0.0;
    
    cpuInfo.prev_load = new_load;
    vm_deallocate(mach_task_self_, (vm_address_t)processorInfo, processorMsgCount);
    
    return usage;
}

- (void)updatePowerConsumption {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [self initCPUInfo];
        });
        
        float cpuUsage = [self calculateCPUUsage];
        self.cpuUsage = cpuUsage;
        
        CFTypeRef powerInfo = IOPSCopyPowerSourcesInfo();
        CFArrayRef powerSources = IOPSCopyPowerSourcesList(powerInfo);
        
        double currentPower = 0.0;
        NSString *powerSourceType = @"Battery";
        BOOL isCharging = NO;
        
        if (powerSources && CFArrayGetCount(powerSources) > 0) {
            CFDictionaryRef powerSource = IOPSGetPowerSourceDescription(powerInfo, CFArrayGetValueAtIndex(powerSources, 0));
            NSString *powerState = (__bridge NSString *)CFDictionaryGetValue(powerSource, CFSTR(kIOPSPowerSourceStateKey));
            
            if ([powerState isEqualToString:@"AC Power"]) {
                powerSourceType = @"AC";
                isCharging = YES;
            }
            
            double loadFactor = self.cpuUsage / 100.0;
            
            if (isCharging) {
                currentPower = 5.0 + (loadFactor * 25.0);
            } else {
                currentPower = 2.0 + (loadFactor * 15.0);
            }
        }
        
        NSString *loadStatus;
        if (self.cpuUsage < 30) {
            loadStatus = @"Низкая";
        } else if (self.cpuUsage < 60) {
            loadStatus = @"Средняя";
        } else if (self.cpuUsage < 85) {
            loadStatus = @"Высокая";
        } else {
            loadStatus = @"Критическая";
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.powerUsageStatus = [NSString stringWithFormat:@"%@ (%@ %.1fW)",
                                   loadStatus,
                                   powerSourceType,
                                   currentPower];
            [self setNeedsDisplay:YES];
        });
        
        if (powerInfo) CFRelease(powerInfo);
        if (powerSources) CFRelease(powerSources);
    });
}

- (void)stopPowerMonitoring {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(updatePowerConsumption)
                                             object:nil];
}

- (void)handleThemeButton:(id)sender {
    self.isDarkTheme = !self.isDarkTheme;
    [self setNeedsDisplay:YES];
}

- (void)updateMemoryUsage {
    // Get system memory statistics
    vm_size_t pageSize;
    host_page_size(mach_host_self(), &pageSize);
    
    mach_msg_type_number_t hostCount = HOST_VM_INFO64_COUNT;
    vm_statistics64_data_t vmStats;
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64, (host_info64_t)&vmStats, &hostCount) == KERN_SUCCESS) {
        uint64_t activeMemory = vmStats.active_count * pageSize;
        uint64_t inactiveMemory = vmStats.inactive_count * pageSize;
        uint64_t wiredMemory = vmStats.wire_count * pageSize;
        
        uint64_t usedMemory = activeMemory + inactiveMemory + wiredMemory;
        
        // Get total physical memory
        int mib[2] = {CTL_HW, HW_MEMSIZE};
        u_int namelen = sizeof(mib) / sizeof(mib[0]);
        uint64_t totalMemory = 0;
        size_t len = sizeof(totalMemory);
        
        if (sysctl(mib, namelen, &totalMemory, &len, NULL, 0) == 0) {
            self.memoryTotal = totalMemory / (1024.0 * 1024.0); // Convert to MB
            self.memoryUsage = usedMemory / (1024.0 * 1024.0); // Convert to MB
        }
    }
    
    [self setNeedsDisplay:YES];
}

- (NSString *)formatMemorySize:(double)memoryInMB {
    if (memoryInMB < 1024) {
        return [NSString stringWithFormat:@"%.0f MB", memoryInMB];
    } else {
        return [NSString stringWithFormat:@"%.2f GB", memoryInMB / 1024.0];
    }
}

- (void)updateNetworkThroughput {
    struct ifaddrs *ifaddrs;
    uint64_t currentBytesIn = 0;
    uint64_t currentBytesOut = 0;
    
    if (getifaddrs(&ifaddrs) == 0) {
        struct ifaddrs *interface;
        
        // Sum up all interface statistics
        for (interface = ifaddrs; interface; interface = interface->ifa_next) {
            // Skip loopback and inactive interfaces
            if (!interface->ifa_addr || 
                (interface->ifa_flags & IFF_LOOPBACK) || 
                !(interface->ifa_flags & IFF_UP) ||
                !(interface->ifa_flags & IFF_RUNNING)) {
                continue;
            }
            
            // Only count IPv4 interfaces
            if (interface->ifa_addr->sa_family == AF_LINK) {
                struct if_data *data = (struct if_data *)interface->ifa_data;
                if (data) {
                    currentBytesIn += data->ifi_ibytes;
                    currentBytesOut += data->ifi_obytes;
                }
            }
        }
        freeifaddrs(ifaddrs);
        
        // Calculate throughput
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        NSTimeInterval timeDelta = now - self.lastNetworkCheck;
        
        if (timeDelta > 0 && self.lastBytesIn > 0) {
            double bytesInPerSec = (currentBytesIn - self.lastBytesIn) / timeDelta;
            double bytesOutPerSec = (currentBytesOut - self.lastBytesOut) / timeDelta;
            
            // Format with appropriate units
            NSString *inRate = [self formatDataRate:bytesInPerSec];
            NSString *outRate = [self formatDataRate:bytesOutPerSec];
            
            self.networkThroughput = [NSString stringWithFormat:@"↓%@ ↑%@", inRate, outRate];
        }
        
        self.lastBytesIn = currentBytesIn;
        self.lastBytesOut = currentBytesOut;
        self.lastNetworkCheck = now;
        
        [self setNeedsDisplay:YES];
    }
}

- (NSString *)formatDataRate:(double)bytesPerSecond {
    if (bytesPerSecond < 1024) {
        return [NSString stringWithFormat:@"%.0f B/s", bytesPerSecond];
    } else if (bytesPerSecond < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.1f KB/s", bytesPerSecond / 1024.0];
    } else {
        return [NSString stringWithFormat:@"%.1f MB/s", bytesPerSecond / 1024.0 / 1024.0];
    }
}

- (void)updateCPUTemperature {
    // This is a simplified example - real implementation would need IOKit
    self.cpuTemp = 0.0;
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                     IOServiceMatching("AppleSMC"));
    if (service) {
        // Read CPU temperature using SMC
        // Implementation depends on macOS version and hardware
        IOObjectRelease(service);
    }
}

- (void)saveSettings {
    NSString *settingsPath = [NSString stringWithFormat:@"%@/Library/Application Support/Overlay/settings.plist",
                             NSHomeDirectory()];
    [[NSFileManager defaultManager] createDirectoryAtPath:[settingsPath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];
    
    NSDictionary *settings = @{
        @"opacity": @(self.opacity),
        @"is24HourFormat": @(self.is24HourFormat),
        @"showSeconds": @(self.showSeconds),
        @"isDarkTheme": @(self.isDarkTheme),
        @"isCompactMode": @(self.isCompactMode),
        @"fontSize": @(self.fontSize),
        @"showNetworkInfo": @(self.showNetworkInfo),
        @"showSystemInfo": @(self.showSystemInfo),
        @"showCalendarByDefault": @(self.showCalendarByDefault),
        @"refreshRate": @(self.refreshRate),
        @"backgroundOpacity": @(self.backgroundOpacity)
    };
    
    [settings writeToFile:settingsPath atomically:YES];
}

- (void)loadSettings {
    NSString *settingsPath = [NSString stringWithFormat:@"%@/Library/Application Support/Overlay/settings.plist",
                             NSHomeDirectory()];
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:settingsPath];
    
    if (settings) {
        self.opacity = [settings[@"opacity"] doubleValue] ?: 0.05;
        self.is24HourFormat = [settings[@"is24HourFormat"] boolValue];
        self.showSeconds = [settings[@"showSeconds"] boolValue];
        self.isDarkTheme = [settings[@"isDarkTheme"] boolValue];
        self.isCompactMode = [settings[@"isCompactMode"] boolValue];
        self.fontSize = [settings[@"fontSize"] integerValue] ?: 24;
        self.showNetworkInfo = [settings[@"showNetworkInfo"] boolValue];
        self.showSystemInfo = [settings[@"showSystemInfo"] boolValue];
        self.showCalendarByDefault = [settings[@"showCalendarByDefault"] boolValue];
        self.refreshRate = [settings[@"refreshRate"] integerValue] ?: 1;
        self.backgroundOpacity = [settings[@"backgroundOpacity"] doubleValue] ?: 0.05;
        [self setNeedsDisplay:YES];
    }
}

- (void)toggleCompactMode {
    self.isCompactMode = !self.isCompactMode;
    
    // Скрываем/показываем кнопки управления в зависимости от режима
    if (self.isCompactMode) {
        // В компактном режиме скрываем все кнопки кроме основных
        self.closeButton.hidden = NO;  // Кнопка закрытия всегда видна
        self.settingsButton.hidden = YES;  // Скрываем настройки в компактном режиме
    } else {
        // В полном режиме показываем все кнопки
        self.closeButton.hidden = NO;
        self.settingsButton.hidden = NO;
    }
    
    // Сохраняем настройку
    [self saveSettings];
    
    // Принудительно перерисовываем весь экран
    self.needsFullRedraw = YES;
    [self setNeedsDisplay:YES];
    
    NSLog(@"Compact mode toggled: %@", self.isCompactMode ? @"ON" : @"OFF");
}

- (void)setupDisplaySettings:(NSView *)view {
    CGFloat yPos = 420;
    CGFloat spacing = 40;
    
    // Заголовок секции
    NSTextField *sectionTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(20, yPos, 400, 25)];
    [sectionTitle setStringValue:@"Внешний вид"];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [sectionTitle setEditable:NO];
    [sectionTitle setSelectable:NO];
    [sectionTitle setFont:[NSFont boldSystemFontOfSize:16]];
    [view addSubview:sectionTitle];
    yPos -= spacing;
    
    // Компактный режим
    NSButton *compactModeButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, yPos, 200, 25)];
    [compactModeButton setButtonType:NSButtonTypeSwitch];
    [compactModeButton setTitle:@"Компактный режим"];
    [compactModeButton setState:self.isCompactMode ? NSControlStateValueOn : NSControlStateValueOff];
    [compactModeButton setTag:1001];
    [view addSubview:compactModeButton];
    yPos -= spacing;
    
    // Темная тема
    NSButton *darkThemeButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, yPos, 200, 25)];
    [darkThemeButton setButtonType:NSButtonTypeSwitch];
    [darkThemeButton setTitle:@"Темная тема"];
    [darkThemeButton setState:self.isDarkTheme ? NSControlStateValueOn : NSControlStateValueOff];
    [darkThemeButton setTag:1002];
    [view addSubview:darkThemeButton];
    yPos -= spacing;
    
    // Прозрачность
    NSTextField *opacityLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, yPos + 5, 150, 20)];
    [opacityLabel setStringValue:@"Прозрачность:"];
    [opacityLabel setBezeled:NO];
    [opacityLabel setDrawsBackground:NO];
    [opacityLabel setEditable:NO];
    [view addSubview:opacityLabel];
    
    NSSlider *opacitySlider = [[NSSlider alloc] initWithFrame:NSMakeRect(180, yPos, 200, 25)];
    [opacitySlider setMinValue:0.01];
    [opacitySlider setMaxValue:1.0];
    [opacitySlider setDoubleValue:self.opacity];
    [opacitySlider setTag:2001];
    [view addSubview:opacitySlider];
    
    NSTextField *opacityValue = [[NSTextField alloc] initWithFrame:NSMakeRect(390, yPos + 3, 50, 20)];
    [opacityValue setStringValue:[NSString stringWithFormat:@"%.0f%%", self.opacity * 100]];
    [opacityValue setBezeled:NO];
    [opacityValue setDrawsBackground:NO];
    [opacityValue setEditable:NO];
    [opacityValue setTag:3001];
    [view addSubview:opacityValue];
}

- (void)setupSystemSettings:(NSView *)view {
    CGFloat yPos = 420;
    CGFloat spacing = 40;
    
    NSTextField *sectionTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(20, yPos, 400, 25)];
    [sectionTitle setStringValue:@"Системная информация"];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [sectionTitle setEditable:NO];
    [sectionTitle setFont:[NSFont boldSystemFontOfSize:16]];
    [view addSubview:sectionTitle];
    yPos -= spacing;
    
    NSButton *networkInfoButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, yPos, 250, 25)];
    [networkInfoButton setButtonType:NSButtonTypeSwitch];
    [networkInfoButton setTitle:@"Показывать сетевую информацию"];
    [networkInfoButton setState:self.showNetworkInfo ? NSControlStateValueOn : NSControlStateValueOff];
    [networkInfoButton setTag:1004];
    [view addSubview:networkInfoButton];
    yPos -= spacing;
    
    NSButton *systemInfoButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, yPos, 250, 25)];
    [systemInfoButton setButtonType:NSButtonTypeSwitch];
    [systemInfoButton setTitle:@"Показывать системную информацию"];
    [systemInfoButton setState:self.showSystemInfo ? NSControlStateValueOn : NSControlStateValueOff];
    [systemInfoButton setTag:1005];
    [view addSubview:systemInfoButton];
}

- (void)setupTimeSettings:(NSView *)view {
    CGFloat yPos = 420;
    CGFloat spacing = 40;
    
    NSTextField *sectionTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(20, yPos, 400, 25)];
    [sectionTitle setStringValue:@"Настройки времени"];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [sectionTitle setEditable:NO];
    [sectionTitle setFont:[NSFont boldSystemFontOfSize:16]];
    [view addSubview:sectionTitle];
    yPos -= spacing;
    
    NSButton *timeFormatButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, yPos, 200, 25)];
    [timeFormatButton setButtonType:NSButtonTypeSwitch];
    [timeFormatButton setTitle:@"24-часовой формат"];
    [timeFormatButton setState:self.is24HourFormat ? NSControlStateValueOn : NSControlStateValueOff];
    [timeFormatButton setTag:1006];
    [view addSubview:timeFormatButton];
    yPos -= spacing;
    
    NSButton *showSecondsButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, yPos, 200, 25)];
    [showSecondsButton setButtonType:NSButtonTypeSwitch];
    [showSecondsButton setTitle:@"Показывать секунды"];
    [showSecondsButton setState:self.showSeconds ? NSControlStateValueOn : NSControlStateValueOff];
    [showSecondsButton setTag:1007];
    [view addSubview:showSecondsButton];
}

- (void)setupAdvancedSettings:(NSView *)view {
    CGFloat yPos = 420;
    CGFloat spacing = 40;
    
    NSTextField *sectionTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(20, yPos, 400, 25)];
    [sectionTitle setStringValue:@"Дополнительно"];
    [sectionTitle setBezeled:NO];
    [sectionTitle setDrawsBackground:NO];
    [sectionTitle setEditable:NO];
    [sectionTitle setFont:[NSFont boldSystemFontOfSize:16]];
    [view addSubview:sectionTitle];
    yPos -= spacing;
    
    NSButton *exportButton = [[NSButton alloc] initWithFrame:NSMakeRect(20, yPos, 120, 30)];
    [exportButton setTitle:@"📤 Экспорт"];
    [exportButton setTarget:self];
    [exportButton setAction:@selector(exportSettings)];
    [view addSubview:exportButton];
    
    NSButton *importButton = [[NSButton alloc] initWithFrame:NSMakeRect(150, yPos, 120, 30)];
    [importButton setTitle:@"📥 Импорт"];
    [importButton setTarget:self];
    [importButton setAction:@selector(importSettings)];
    [view addSubview:importButton];
    yPos -= spacing + 10;
    
    NSTextField *versionInfo = [[NSTextField alloc] initWithFrame:NSMakeRect(20, yPos, 400, 20)];
    [versionInfo setStringValue:@"Overlay v1.0.3 - © 2025 vos9.su"];
    [versionInfo setBezeled:NO];
    [versionInfo setDrawsBackground:NO];
    [versionInfo setEditable:NO];
    [versionInfo setFont:[NSFont systemFontOfSize:12]];
    [view addSubview:versionInfo];
}

- (void)closeSettingsWindow:(id)sender {
    [self.settingsWindow close];
}

- (void)applySettings {
    // Получаем все элементы управления и применяем их значения
    NSArray *allSubviews = [self getAllSubviewsFromWindow:self.settingsWindow];
    
    for (NSView *view in allSubviews) {
        if ([view isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)view;
            if ([button respondsToSelector:@selector(state)] && button.tag >= 1001 && button.tag <= 1007) {
                switch (button.tag) {
                    case 1001: // Компактный режим
                        if (self.isCompactMode != (button.state == NSControlStateValueOn)) {
                            [self toggleCompactMode];
                        }
                        break;
                    case 1002: // Темная тема
                        self.isDarkTheme = (button.state == NSControlStateValueOn);
                        break;
                    case 1004: // Сетевая информация
                        self.showNetworkInfo = (button.state == NSControlStateValueOn);
                        break;
                    case 1005: // Системная информация
                        self.showSystemInfo = (button.state == NSControlStateValueOn);
                        break;
                    case 1006: // 24-часовой формат
                        self.is24HourFormat = (button.state == NSControlStateValueOn);
                        break;
                    case 1007: // Показывать секунды
                        self.showSeconds = (button.state == NSControlStateValueOn);
                        break;
                }
            }
        } else if ([view isKindOfClass:[NSSlider class]]) {
            NSSlider *slider = (NSSlider *)view;
            switch (slider.tag) {
                case 2001: // Прозрачность
                    self.opacity = slider.doubleValue;
                    break;
            }
        }
    }
    
    [self saveSettings];
    [self setNeedsDisplay:YES];
    [self.settingsWindow close];
    
    NSLog(@"Settings applied and saved");
}

- (NSArray *)getAllSubviewsFromWindow:(NSWindow *)window {
    NSMutableArray *allSubviews = [NSMutableArray array];
    [self addSubviewsToArray:allSubviews fromView:window.contentView];
    return allSubviews;
}

- (void)addSubviewsToArray:(NSMutableArray *)array fromView:(NSView *)view {
    [array addObject:view];
    for (NSView *subview in view.subviews) {
        [self addSubviewsToArray:array fromView:subview];
    }
}

- (void)resetSettingsToDefaults {
    NSAlert *confirmAlert = [[NSAlert alloc] init];
    [confirmAlert setMessageText:@"Сбросить настройки"];
    [confirmAlert setInformativeText:@"Вы уверены, что хотите сбросить все настройки к значениям по умолчанию?"];
    [confirmAlert addButtonWithTitle:@"Сбросить"];
    [confirmAlert addButtonWithTitle:@"Отмена"];
    [confirmAlert setAlertStyle:NSAlertStyleWarning];
    
    NSInteger response = [confirmAlert runModal];
    if (response == NSAlertFirstButtonReturn) {
        // Сбрасываем к значениям по умолчанию
        self.isCompactMode = NO;
        self.isDarkTheme = YES;
        self.is24HourFormat = YES;
        self.showSeconds = YES;
        self.opacity = 0.05;
        self.fontSize = 24;
        self.showNetworkInfo = YES;
        self.showSystemInfo = YES;
        self.showCalendarByDefault = NO;
        self.refreshRate = 1;
        
        [self saveSettings];
        [self setNeedsDisplay:YES];
        [self.settingsWindow close];
        
        NSLog(@"Settings reset to defaults");
    }
}

- (void)exportSettings {
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    [savePanel setAllowedFileTypes:@[@"plist"]];
    [savePanel setNameFieldStringValue:@"overlay_settings.plist"];
    [savePanel setTitle:@"Экспорт настроек"];
    
    [savePanel beginWithCompletionHandler:^(NSInteger response) {
        if (response == NSModalResponseOK) {
            NSURL *url = [savePanel URL];
            NSDictionary *settings = [self getCurrentSettings];
            
            NSError *error;
            NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:settings
                                                                          format:NSPropertyListXMLFormat_v1_0
                                                                         options:0
                                                                           error:&error];
            
            if (plistData && !error) {
                [plistData writeToURL:url atomically:YES];
                NSLog(@"Settings exported to: %@", url.path);
            } else {
                NSLog(@"Failed to export settings: %@", error.localizedDescription);
            }
        }
    }];
}

- (void)importSettings {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setAllowedFileTypes:@[@"plist"]];
    [openPanel setTitle:@"Импорт настроек"];
    
    [openPanel beginWithCompletionHandler:^(NSInteger response) {
        if (response == NSModalResponseOK) {
            NSURL *url = [openPanel URL];
            NSDictionary *settings = [NSDictionary dictionaryWithContentsOfURL:url];
            
            if (settings) {
                [self applyImportedSettings:settings];
                [self saveSettings];
                [self setNeedsDisplay:YES];
                [self.settingsWindow close];
                NSLog(@"Settings imported from: %@", url.path);
            } else {
                NSLog(@"Failed to import settings from: %@", url.path);
            }
        }
    }];
}

- (NSDictionary *)getCurrentSettings {
    return @{
        @"opacity": @(self.opacity),
        @"is24HourFormat": @(self.is24HourFormat),
        @"showSeconds": @(self.showSeconds),
        @"isDarkTheme": @(self.isDarkTheme),
        @"isCompactMode": @(self.isCompactMode),
        @"fontSize": @(self.fontSize),
        @"showNetworkInfo": @(self.showNetworkInfo ?: YES),
        @"showSystemInfo": @(self.showSystemInfo ?: YES),
        @"showCalendarByDefault": @(self.showCalendarByDefault ?: NO),
        @"refreshRate": @(self.refreshRate ?: 1)
    };
}

- (void)applyImportedSettings:(NSDictionary *)settings {
    if (settings[@"opacity"]) self.opacity = [settings[@"opacity"] doubleValue];
    if (settings[@"is24HourFormat"]) self.is24HourFormat = [settings[@"is24HourFormat"] boolValue];
    if (settings[@"showSeconds"]) self.showSeconds = [settings[@"showSeconds"] boolValue];
    if (settings[@"isDarkTheme"]) self.isDarkTheme = [settings[@"isDarkTheme"] boolValue];
    if (settings[@"isCompactMode"]) self.isCompactMode = [settings[@"isCompactMode"] boolValue];
    if (settings[@"fontSize"]) self.fontSize = [settings[@"fontSize"] integerValue];
    if (settings[@"showNetworkInfo"]) self.showNetworkInfo = [settings[@"showNetworkInfo"] boolValue];
    if (settings[@"showSystemInfo"]) self.showSystemInfo = [settings[@"showSystemInfo"] boolValue];
    if (settings[@"showCalendarByDefault"]) self.showCalendarByDefault = [settings[@"showCalendarByDefault"] boolValue];
    if (settings[@"refreshRate"]) self.refreshRate = [settings[@"refreshRate"] integerValue];
}

@end