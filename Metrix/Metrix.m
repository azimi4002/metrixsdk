//
//  Metrix.m
//  Metrix
//

#import "Metrix.h"
#import "MXUtil.h"
#import "MXLogger.h"
#import "MXMetrixFactory.h"
#import "MXCustomEvent.h"

#if !__has_feature(objc_arc)
#error Metrix requires ARC
// See README for details: https://github.com/metrixorg/ios_sdk/blob/master/README.md
#endif

NSString * const MXEnvironmentSandbox      = @"sandbox";
NSString * const MXEnvironmentProduction   = @"production";

@implementation MetrixTestOptions
@end

@interface Metrix()

@property (nonatomic, weak) id<MXLogger> logger;

@property (nonatomic, strong) id<MXActivityHandler> activityHandler;

@property (nonatomic, strong) MXSavedPreLaunch *savedPreLaunch;

@end

@implementation Metrix

#pragma mark - Object lifecycle methods

static Metrix *defaultInstance = nil;
static dispatch_once_t onceToken = 0;

+ (id)getInstance {
    dispatch_once(&onceToken, ^{
        defaultInstance = [[self alloc] init];
    });

    return defaultInstance;
}

- (id)init {
    self = [super init];

    if (self == nil) {
        return nil;
    }

    self.activityHandler = nil;
    self.logger = [MXMetrixFactory logger];
    self.savedPreLaunch = [[MXSavedPreLaunch alloc] init];

    return self;
}

#pragma mark - Public static methods

+ (void)appDidLaunch:(MXConfig *)metrixConfig {
    [[Metrix getInstance] appDidLaunch:metrixConfig];
}

+ (void)trackCustomEvent:(nullable MXCustomEvent *)event {
    [[Metrix getInstance] trackCustomEvent:event];
}

+ (void)trackScreen:(NSString *)screenName {
    [[Metrix getInstance] trackScreen:screenName];
}

+ (void)setEnabled:(BOOL)enabled {
    Metrix *instance = [Metrix getInstance];
    [instance setEnabled:enabled];
}

+ (BOOL)isEnabled {
    return [[Metrix getInstance] isEnabled];
}

+ (void)setOfflineMode:(BOOL)enabled {
    [[Metrix getInstance] setOfflineMode:enabled];
}

+ (NSString *)idfa {
    return [[Metrix getInstance] idfa];
}

+ (NSString *)sdkVersion {
    return [[Metrix getInstance] sdkVersion];
}

+ (void)sendFirstPackages {
    [[Metrix getInstance] sendFirstPackages];
}

+ (NSString *)mxid {
    return [[Metrix getInstance] mxid];
}

+ (void)setTestOptions:(MetrixTestOptions *)testOptions {
    if (testOptions.teardown) {
        if (defaultInstance != nil) {
            [defaultInstance teardown];
        }
        defaultInstance = nil;
        onceToken = 0;
        [MXMetrixFactory teardown:testOptions.deleteState];
    }
    [[Metrix getInstance] setTestOptions:(MetrixTestOptions *)testOptions];
}

#pragma mark - Public instance methods

- (void)appDidLaunch:(MXConfig *)metrixConfig {
    if (self.activityHandler != nil) {
        [self.logger error:@"Metrix already initialized"];
        return;
    }

    self.activityHandler = [MXMetrixFactory activityHandlerWithConfig:metrixConfig
                                                        savedPreLaunch:self.savedPreLaunch];
}

- (void)trackCustomEvent:(MXCustomEvent *)event {
    if (![self checkActivityHandler]) {
        return;
    }

    [self.activityHandler trackCustomEvent:event];
}

- (void)trackScreen:(NSString *)screenName {
    if (![self checkActivityHandler]) {
        return;
    }

    [self.activityHandler trackScreen:screenName];
}


- (void)trackSubsessionStart {
    if (![self checkActivityHandler]) {
        return;
    }

    [self.activityHandler applicationDidBecomeActive];
}

- (void)trackSubsessionEnd {
    if (![self checkActivityHandler]) {
        return;
    }

    [self.activityHandler applicationWillResignActive];
}

- (void)setEnabled:(BOOL)enabled {
    self.savedPreLaunch.enabled = [NSNumber numberWithBool:enabled];

    if ([self checkActivityHandler:enabled
                       trueMessage:@"enabled mode"
                      falseMessage:@"disabled mode"]) {
        [self.activityHandler setEnabled:enabled];
    }
}

- (BOOL)isEnabled {
    if (![self checkActivityHandler]) {
        return [self isInstanceEnabled];
    }

    return [self.activityHandler isEnabled];
}

- (void)setOfflineMode:(BOOL)enabled {
    if (![self checkActivityHandler:enabled
                        trueMessage:@"offline mode"
                       falseMessage:@"online mode"]) {
        self.savedPreLaunch.offline = enabled;
    } else {
        [self.activityHandler setOfflineMode:enabled];
    }
}

- (NSString *)idfa {
    return [MXUtil idfa];
}

- (NSURL *)convertUniversalLink:(NSURL *)url scheme:(NSString *)scheme {
    return [MXUtil convertUniversalLink:url scheme:scheme];
}

- (void)sendFirstPackages {
    if (![self checkActivityHandler]) {
        return;
    }

    [self.activityHandler sendFirstPackages];
}

- (NSString *)mxid {
    if (![self checkActivityHandler]) {
        return nil;
    }

    return [self.activityHandler mxid];
}

- (NSString *)sdkVersion {
    return [MXUtil sdkVersion];
}

- (void)teardown {
    if (self.activityHandler == nil) {
        [self.logger error:@"Metrix already down or not initialized"];
        return;
    }

    [self.activityHandler teardown];
    self.activityHandler = nil;
}

- (void)setTestOptions:(MetrixTestOptions *)testOptions {
    if (testOptions.basePath != nil) {
        self.savedPreLaunch.basePath = testOptions.basePath;
    }
    if (testOptions.baseUrl != nil) {
        [MXMetrixFactory setBaseUrl:testOptions.baseUrl];
    }
    if (testOptions.timerIntervalInMilliseconds != nil) {
        NSTimeInterval timerIntervalInSeconds = [testOptions.timerIntervalInMilliseconds intValue] / 1000.0;
        [MXMetrixFactory setTimerInterval:timerIntervalInSeconds];
    }
    if (testOptions.timerStartInMilliseconds != nil) {
        NSTimeInterval timerStartInSeconds = [testOptions.timerStartInMilliseconds intValue] / 1000.0;
        [MXMetrixFactory setTimerStart:timerStartInSeconds];
    }
    if (testOptions.sessionIntervalInMilliseconds != nil) {
        NSTimeInterval sessionIntervalInSeconds = [testOptions.sessionIntervalInMilliseconds intValue] / 1000.0;
        [MXMetrixFactory setSessionInterval:sessionIntervalInSeconds];
    }
    if (testOptions.subsessionIntervalInMilliseconds != nil) {
        NSTimeInterval subsessionIntervalInSeconds = [testOptions.subsessionIntervalInMilliseconds intValue] / 1000.0;
        [MXMetrixFactory setSubsessionInterval:subsessionIntervalInSeconds];
    }
    if (testOptions.noBackoffWait) {
        [MXMetrixFactory setPackageHandlerBackoffStrategy:[MXBackoffStrategy backoffStrategyWithType:MXNoWait]];
    }
    
    [MXMetrixFactory setiAdFrameworkEnabled:testOptions.iAdFrameworkEnabled];
}

#pragma mark - Private & helper methods

- (BOOL)checkActivityHandler {
    return [self checkActivityHandler:nil];
}

- (BOOL)checkActivityHandler:(BOOL)status
                 trueMessage:(NSString *)trueMessage
                falseMessage:(NSString *)falseMessage {
    if (status) {
        return [self checkActivityHandler:trueMessage];
    } else {
        return [self checkActivityHandler:falseMessage];
    }
}

- (BOOL)checkActivityHandler:(NSString *)savedForLaunchWarningSuffixMessage {
    if (self.activityHandler == nil) {
        if (savedForLaunchWarningSuffixMessage != nil) {
            [self.logger warn:@"Metrix not initialized, but %@ saved for launch", savedForLaunchWarningSuffixMessage];
        } else {
            [self.logger error:@"Please initialize Metrix by calling 'appDidLaunch' before"];
        }

        return NO;
    } else {
        return YES;
    }
}

- (BOOL)isInstanceEnabled {
    return self.savedPreLaunch.enabled == nil || self.savedPreLaunch.enabled;
}

@end
