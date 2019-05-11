//
//  MXActivityHandler.m
//  Metrix
//

#import "MXActivityPackage.h"
#import "MXActivityHandler.h"
#import "MXPackageBuilder.h"
#import "MXPackageHandler.h"
#import "MXLogger.h"
#import "MXTimerCycle.h"
#import "MXTimerOnce.h"
#import "MXUtil.h"
#import "UIDevice+MXAdditions.h"
#import "MXMetrixFactory.h"
#import "MXAttributionHandler.h"
#import "NSString+MXAdditions.h"
#import "MXCustomEvent.h"
#import "MXUserDefaults.h"

typedef void (^activityHandlerBlockI)(MXActivityHandler *activityHandler);

static NSString *const kActivityStateFilename = @"MetrixIoActivityState";
static NSString *const kAttributionFilename = @"MetrixIoAttribution";
static NSString *const kSessionCallbackParametersFilename = @"MetrixSessionCallbackParameters";
static NSString *const kSessionPartnerParametersFilename = @"MetrixSessionPartnerParameters";
static NSString *const kMetrixPrefix = @"metrix_";
static const char *const kInternalQueueName = "io.metrix.ActivityQueue";
static NSString *const kForegroundTimerName = @"Foreground timer";
static NSString *const kBackgroundTimerName = @"Background timer";
static NSString *const kSessionStopCheckerTimerName = @"SessionStop checker timer";
static NSString *const kDelayStartTimerName = @"Delay Start timer";
static NSString *const StopPackageStoreFilename = @"StopPackageStoreFile";
static NSString *const StopPackageStoreObjectName = @"StopPackageStore";

static NSTimeInterval kForegroundTimerInterval;
static NSTimeInterval kForegroundTimerStart;
static NSTimeInterval kBackgroundTimerInterval;
static double kSessionInterval;
static double kSubSessionInterval;

static const double kStopSessionTimerInterval = 10;
// number of tries
static const int kTryIadV3 = 2;
static const uint64_t kDelayRetryIad = 2 * NSEC_PER_SEC; // 1 second

@implementation MXInternalState

- (id)init {
    self = [super init];
    if (self == nil) return nil;

    return self;
}

- (BOOL)isEnabled {
    return self.enabled;
}

- (BOOL)isDisabled {
    return !self.enabled;
}

- (BOOL)isOffline {
    return self.offline;
}

- (BOOL)isOnline {
    return !self.offline;
}

- (BOOL)isInBackground {
    return self.background;
}

- (BOOL)isInForeground {
    return !self.background;
}

- (BOOL)isInDelayedStart {
    return self.delayStart;
}

- (BOOL)isNotInDelayedStart {
    return !self.delayStart;
}

- (BOOL)itHasToUpdatePackages {
    return self.updatePackages;
}

- (BOOL)isFirstLaunch {
    return self.firstLaunch;
}

- (BOOL)hasSessionResponseNotBeenProcessed {
    return !self.sessionResponseProcessed;
}

@end

@implementation MXSavedPreLaunch

- (id)init {
    self = [super init];
    if (self == nil) return nil;

    // online by default
    self.offline = NO;
    return self;
}

@end

#pragma mark -

@interface MXActivityHandler ()

@property(nonatomic, strong) dispatch_queue_t internalQueue;
@property(nonatomic, strong) id <MXPackageHandler> packageHandler;
@property(nonatomic, strong) id <MXAttributionHandler> attributionHandler;
@property(nonatomic, strong) MXActivityState *activityState;
@property(nonatomic, strong) MXTimerCycle *foregroundTimer;
@property(nonatomic, strong) MXTimerOnce *backgroundTimer;
@property(nonatomic, strong) MXTimerOnce *sessionStopCheckerTimer;
@property(nonatomic, strong) MXInternalState *internalState;
@property(nonatomic, strong) MXDeviceInfo *deviceInfo;
@property(nonatomic, strong) MXTimerOnce *delayStartTimer;
@property(nonatomic, strong) MXSessionParameters *sessionParameters;
// weak for object that Activity Handler does not "own"
@property(nonatomic, weak) id <MXLogger> logger;
@property(nonatomic, weak) NSObject <MetrixDelegate> *MetrixDelegate;
// copy for objects shared with the user
@property(nonatomic, copy) MXConfig *metrixConfig;
@property(nonatomic, copy) NSData *deviceTokenData;
@property(nonatomic, copy) NSString *basePath;

@end

// copy from ADClientError
typedef NS_ENUM(NSInteger, MxADClientError) {
    MxADClientErrorUnknown = 0,
    MxADClientErrorLimitAdTracking = 1,
};

#pragma mark -

@implementation MXActivityHandler

@synthesize attribution = _attribution;

+ (id <MXActivityHandler>)handlerWithConfig:(MXConfig *)metrixConfig
                             savedPreLaunch:(MXSavedPreLaunch *)savedPreLaunch {
    return [[MXActivityHandler alloc] initWithConfig:metrixConfig
                                      savedPreLaunch:savedPreLaunch];
}

- (id)initWithConfig:(MXConfig *)metrixConfig
      savedPreLaunch:(MXSavedPreLaunch *)savedPreLaunch {
    self = [super init];
    if (self == nil) return nil;

    if (metrixConfig == nil) {
        [MXMetrixFactory.logger error:@"metrixConfig missing"];
        return nil;
    }

    if (![metrixConfig isValid]) {
        [MXMetrixFactory.logger error:@"metrixConfig not initialized correctly"];
        return nil;
    }

    self.metrixConfig = metrixConfig;
    self.MetrixDelegate = metrixConfig.delegate;

    // init logger to be available everywhere
    self.logger = MXMetrixFactory.logger;

    [self.logger lockLogLevel];

    // inject app token be available in activity state
    [MXActivityState saveAppToken:metrixConfig.appId];

    // read files to have sync values available
    [self readAttribution];
    [self readActivityState];

    self.internalState = [[MXInternalState alloc] init];

    if (savedPreLaunch.enabled != nil) {
        if (savedPreLaunch.preLaunchActionsArray == nil) {
            savedPreLaunch.preLaunchActionsArray = [[NSMutableArray alloc] init];
        }

        BOOL newEnabled = [savedPreLaunch.enabled boolValue];
        [savedPreLaunch.preLaunchActionsArray addObject:^(MXActivityHandler *activityHandler) {
            [activityHandler setEnabledI:activityHandler enabled:newEnabled];
        }];
    }

    // check if SDK is enabled/disabled
    self.internalState.enabled = savedPreLaunch.enabled != nil ? [savedPreLaunch.enabled boolValue] : YES;
    // reads offline mode from pre launch
    self.internalState.offline = savedPreLaunch.offline;
    // in the background by default
    self.internalState.background = YES;
    // delay start not configured by default
    self.internalState.delayStart = NO;
    // does not need to update packages by default
    if (self.activityState == nil) {
        self.internalState.updatePackages = NO;
    } else {
        self.internalState.updatePackages = self.activityState.updatePackages;
    }
    if (self.activityState == nil) {
        self.internalState.firstLaunch = YES;
    } else {
        self.internalState.firstLaunch = NO;
    }
    // does not have the session response by default
    self.internalState.sessionResponseProcessed = NO;

    if (savedPreLaunch.basePath != nil) {
        self.basePath = savedPreLaunch.basePath;
    }

    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI initI:selfI
               preLaunchActionsArray:savedPreLaunch.preLaunchActionsArray];
                    }];

    /* Not needed, done already in initI:preLaunchActionsArray: method.
    // self.deviceTokenData = savedPreLaunch.deviceTokenData;
    if (self.activityState != nil) {
        [self setDeviceToken:[MXUserDefaults getPushToken]];
    }
    */

    [self addNotificationObserver];

    return self;
}

- (void)applicationDidBecomeActive {
    self.internalState.background = NO;

    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI delayStartI:selfI];

                        [selfI stopBackgroundTimerI:selfI];

                        [selfI startForegroundTimerI:selfI];

                        [selfI.logger verbose:@"Subsession start"];

                        [selfI startI:selfI];
                    }];
}

- (void)applicationWillResignActive {
    self.internalState.background = YES;

    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI stopForegroundTimerI:selfI];

                        [selfI startBackgroundTimerI:selfI];

                        [selfI.logger verbose:@"Subsession end"];

                        [selfI endI:selfI];
                    }];
}

- (void)trackCustomEvent:(MXCustomEvent *)event {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        // track event called before app started
                        if (selfI.activityState == nil) {
                            [selfI startI:selfI];
                        }
                        [selfI customEventI:selfI event:event];
                    }];
}

- (void)trackScreen:(NSString *)screenName {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        // track screen called before app started
                        if (selfI.activityState == nil) {
                            [selfI startI:selfI];
                        }
                        [selfI screenI:selfI name:screenName];
                    }];
}


- (void)finishedTracking:(MXResponseData *)responseData {
    // redirect session responses to attribution handler to check for attribution information
    if ([responseData isKindOfClass:[MXSessionStartResponseData class]]) {
        [self.attributionHandler checkSessionResponse:(MXSessionStartResponseData *) responseData];
        return;
    }
    // check if it's an event response
    if ([responseData isKindOfClass:[MXCustomEventResponseData class]]) {
        [self launchCustomEventResponseTasks:(MXCustomEventResponseData *) responseData];
        return;
    }
}

- (void)launchCustomEventResponseTasks:(MXCustomEventResponseData *)eventResponseData {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI launchCustomEventResponseTasksI:selfI eventResponseData:eventResponseData];
                    }];
}

- (void)launchSessionStartResponseTasks:(MXSessionStartResponseData *)sessionResponseData {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI launchSessionResponseTasksI:selfI sessionResponseData:sessionResponseData];
                    }];
}

- (void)setEnabled:(BOOL)enabled {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI setEnabledI:selfI enabled:enabled];
                    }];
}

- (void)setOfflineMode:(BOOL)offline {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI setOfflineModeI:selfI offline:offline];
                    }];
}

- (BOOL)isEnabled {
    return [self isEnabledI:self];
}

- (NSString *)mxid {
    if (self.activityState == nil) {
        return nil;
    }
    return self.activityState.userId;
}

- (void)foregroundTimerFired {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI foregroundTimerFiredI:selfI];
                    }];
}

- (void)backgroundTimerFired {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI backgroundTimerFiredI:selfI];
                    }];
}

- (void)sendFirstPackages {
    [MXUtil launchInQueue:self.internalQueue
               selfInject:self
                    block:^(MXActivityHandler *selfI) {
                        [selfI sendFirstPackagesI:selfI];
                    }];
}

- (NSString *)getBasePath {
    return _basePath;
}

- (void)teardown {
    [MXMetrixFactory.logger verbose:@"MXActivityHandler teardown"];
    [self removeNotificationObserver];
    if (self.backgroundTimer != nil) {
        [self.backgroundTimer cancel];
    }
    if (self.foregroundTimer != nil) {
        [self.foregroundTimer cancel];
    }
    if (self.delayStartTimer != nil) {
        [self.delayStartTimer cancel];
    }
    if (self.attributionHandler != nil) {
        [self.attributionHandler teardown];
    }
    if (self.packageHandler != nil) {
        [self.packageHandler teardown];
    }
    [self teardownActivityStateS];
    [self teardownAttributionS];

    [MXUtil teardown];

    self.internalQueue = nil;
    self.packageHandler = nil;
    self.attributionHandler = nil;
    self.foregroundTimer = nil;
    self.backgroundTimer = nil;
    self.MetrixDelegate = nil;
    self.metrixConfig = nil;
    self.internalState = nil;
    self.deviceInfo = nil;
    self.delayStartTimer = nil;
    self.logger = nil;
}

+ (void)deleteState {
    [MXActivityHandler deleteActivityState];
    [MXActivityHandler deleteAttribution];
    [MXActivityHandler deleteSessionCallbackParameter];
    [MXActivityHandler deleteSessionPartnerParameter];

    [MXUserDefaults clearMetrixStuff];
}

+ (void)deleteActivityState {
    [MXUtil deleteFileWithName:kActivityStateFilename];
}

+ (void)deleteAttribution {
    [MXUtil deleteFileWithName:kAttributionFilename];
}

+ (void)deleteSessionCallbackParameter {
    [MXUtil deleteFileWithName:kSessionCallbackParametersFilename];
}

+ (void)deleteSessionPartnerParameter {
    [MXUtil deleteFileWithName:kSessionPartnerParametersFilename];
}

#pragma mark - internal

- (void)        initI:(MXActivityHandler *)selfI
preLaunchActionsArray:(NSArray *)preLaunchActionsArray {
    // get session values
    kSessionInterval = MXMetrixFactory.sessionInterval;
    kSubSessionInterval = MXMetrixFactory.subsessionInterval;
    // get timer values
    kForegroundTimerStart = MXMetrixFactory.timerStart;
    kForegroundTimerInterval = MXMetrixFactory.timerInterval;
    kBackgroundTimerInterval = MXMetrixFactory.timerInterval;

    selfI.deviceInfo = [MXDeviceInfo deviceInfoWithSdkPrefix:selfI.metrixConfig.sdkPrefix];

    // read files that are accessed only in Internal sections
    selfI.sessionParameters = [[MXSessionParameters alloc] init];

    if (selfI.metrixConfig.eventBufferingEnabled) {
        [selfI.logger info:@"Event buffering is enabled"];
    }

    if (selfI.metrixConfig.trackerToken != nil) {
        [selfI.logger info:@"Tracker token: '%@'", selfI.metrixConfig.trackerToken];
    }

    selfI.foregroundTimer = [MXTimerCycle timerWithBlock:^{
                [selfI foregroundTimerFired];
            }
                                                   queue:selfI.internalQueue
                                               startTime:kForegroundTimerStart
                                            intervalTime:kForegroundTimerInterval
                                                    name:kForegroundTimerName
    ];

    if (selfI.metrixConfig.sendInBackground) {
        [selfI.logger info:@"Send in background configured"];
        selfI.backgroundTimer = [MXTimerOnce timerWithBlock:^{
                    [selfI backgroundTimerFired];
                }
                                                      queue:selfI.internalQueue
                                                       name:kBackgroundTimerName];
    }

    if (selfI.activityState == nil &&
            selfI.metrixConfig.delayStart > 0) {
        [selfI.logger info:@"Delay start configured"];
        selfI.internalState.delayStart = YES;
        selfI.delayStartTimer = [MXTimerOnce timerWithBlock:^{
                    [selfI sendFirstPackages];
                }
                                                      queue:selfI.internalQueue
                                                       name:kDelayStartTimerName];
    }

    [MXUtil updateUrlSessionConfiguration:selfI.metrixConfig];

    selfI.packageHandler = [MXMetrixFactory packageHandlerForActivityHandler:selfI
                                                               startsSending:[selfI toSendI:selfI
                                                                        sdkClickHandlerOnly:NO]];

    // update session parameters in package queue
    if ([selfI itHasToUpdatePackagesI:selfI]) {
        [selfI updatePackagesI:selfI];
    }

    selfI.attributionHandler = [MXMetrixFactory attributionHandlerForActivityHandler:selfI
                                                                       startsSending:[selfI toSendI:selfI
                                                                                sdkClickHandlerOnly:NO]];

    [[UIDevice currentDevice] mxSetIad:selfI triesV3Left:kTryIadV3];

    [selfI preLaunchActionsI:selfI preLaunchActionsArray:preLaunchActionsArray];

    [MXUtil launchInMainThreadWithInactive:^(BOOL isInactive) {
        [MXUtil launchInQueue:self.internalQueue selfInject:self block:^(MXActivityHandler *selfI) {
            if (!isInactive) {
                [selfI.logger debug:@"Start sdk, since the app is already in the foreground"];
                selfI.internalState.background = NO;
                [selfI startI:selfI];
            } else {
                [selfI.logger debug:@"Wait for the app to go to the foreground to start the sdk"];
            }
        }];
    }];
}

- (void)startI:(MXActivityHandler *)selfI {
    // it shouldn't start if it was disabled after a first session
    if (selfI.activityState != nil
            && !selfI.activityState.enabled) {
        return;
    }

    [selfI updateHandlersStatusAndSendI:selfI];

    [selfI processSessionStartI:selfI];

}

- (void)processSessionStartI:(MXActivityHandler *)selfI {
    [selfI cancelSessionStopTimers:selfI];
    [selfI checkToSessionStopIfNeededI:selfI];

    double now = [NSDate.date timeIntervalSince1970];

    // very first session
    if (selfI.activityState == nil) {
        selfI.activityState = [[MXActivityState alloc] init];

        // selfI.activityState.deviceToken = [MXUtil convertDeviceToken:selfI.deviceTokenData];
        NSData *deviceToken = [MXUserDefaults getPushTokenData];
        NSString *deviceTokenString = [MXUtil convertDeviceToken:deviceToken];
        NSString *pushToken = [MXUserDefaults getPushTokenString];
        selfI.activityState.deviceToken = deviceTokenString != nil ? deviceTokenString : pushToken;

        // track the first session package only if it's enabled
        if ([selfI.internalState isEnabled]) {
            selfI.activityState.sessionCount = 1; // this is the first session
            [selfI transferSessionPackageI:selfI now:now];
        }

        [selfI.activityState resetSessionAttributes:now];
        selfI.activityState.enabled = [selfI.internalState isEnabled];
        selfI.activityState.updatePackages = [selfI.internalState itHasToUpdatePackages];

        [selfI writeActivityStateI:selfI];
        [MXUserDefaults removePushToken];

        return;
    }

    double lastInterval = now - selfI.activityState.lastActivity;
    if (lastInterval < 0) {
        [selfI.logger error:@"Time travel!"];
        selfI.activityState.lastActivity = now;
        [selfI writeActivityStateI:selfI];
        return;
    }

    if (!selfI.activityState.isSessionActive) {
        [self trackNewSessionI:now withActivityHandler:selfI];
        return;
    }

    // new session
    if (lastInterval > kSessionInterval) {
        [selfI endI:selfI];
        [self trackNewSessionI:now withActivityHandler:selfI];
        return;
    }

    // new subsession
    if (lastInterval > kSubSessionInterval) {
        selfI.activityState.subsessionCount++;
        selfI.activityState.sessionLength += lastInterval;
        selfI.activityState.lastActivity = now;
        [selfI.logger verbose:@"Started subsession %d of session %d",
                              selfI.activityState.subsessionCount,
                              selfI.activityState.sessionCount];
        [selfI writeActivityStateI:selfI];
        return;
    }

    [selfI.logger verbose:@"Time span since last activity too short for a new subsession"];
}

- (void)trackNewSessionI:(double)now withActivityHandler:(MXActivityHandler *)selfI {
    [selfI.activityState refreshSessionId];
    double lastInterval = now - selfI.activityState.lastActivity;
    selfI.activityState.sessionCount++;
    selfI.activityState.lastInterval = lastInterval;
    [selfI transferSessionPackageI:selfI now:now];
    [selfI.activityState resetSessionAttributes:now];
    [selfI writeActivityStateI:selfI];
}

- (void)transferSessionPackageI:(MXActivityHandler *)selfI
                            now:(double)now {
    MXPackageBuilder *sessionBuilder = [[MXPackageBuilder alloc]
            initWithDeviceInfo:selfI.deviceInfo
                 activityState:selfI.activityState
                        config:selfI.metrixConfig
             sessionParameters:selfI.sessionParameters
                     createdAt:now];
    MXActivityPackage *sessionPackage = [sessionBuilder buildSessionStartPackage:[selfI.internalState isInDelayedStart]];
    [selfI.packageHandler addPackage:sessionPackage];
    [selfI.packageHandler sendFirstPackage];
}


- (void)endI:(MXActivityHandler *)selfI {
    // pause sending if it's not allowed to send
    if (![selfI toSendI:selfI]) {
        [selfI pauseSendingI:selfI];
    }

    double now = [NSDate.date timeIntervalSince1970];

    if ([selfI updateActivityStateI:selfI now:now]) {
        [selfI writeActivityStateI:selfI];
    }

    // create and populate event package
    MXPackageBuilder *eventBuilder = [[MXPackageBuilder alloc]
            initWithDeviceInfo:selfI.deviceInfo
                 activityState:selfI.activityState
                        config:selfI.metrixConfig
                     createdAt:now];

    MXActivityPackage *stopPackage = [eventBuilder buildSessionStopPackage];

    [MXUtil writeObject:stopPackage fileName:StopPackageStoreFilename objectName:StopPackageStoreObjectName];

    if(selfI.sessionStopCheckerTimer == nil){
        selfI.sessionStopCheckerTimer = [MXTimerOnce timerWithBlock:^{
                    [selfI checkToSessionStopIfNeededI:selfI];
                }
                                                      queue:selfI.internalQueue
                                                       name:kSessionStopCheckerTimerName];
    }
    [selfI.sessionStopCheckerTimer startIn:kStopSessionTimerInterval];
}

- (void)checkToSessionStopIfNeededI:(MXActivityHandler *)selfI {
    @synchronized ([MXActivityHandler class]) {
        double now = [NSDate.date timeIntervalSince1970];

        MXActivityPackage *stopPackage = [MXUtil readObject:StopPackageStoreFilename
                                                 objectName:StopPackageStoreObjectName class:[MXActivityPackage class]];
        if(!stopPackage)return;
        double eventTimestamp = [stopPackage.parameters[@"event_time_stamp"] doubleValue];
        if(eventTimestamp + kStopSessionTimerInterval > now){
            [MXUtil writeObject:nil fileName:StopPackageStoreFilename objectName:StopPackageStoreObjectName];
            return;
        }
        selfI.activityState.isSessionActive = NO;
        [selfI.packageHandler addPackage:stopPackage];

        [MXUtil writeObject:nil fileName:StopPackageStoreFilename objectName:StopPackageStoreObjectName];

        if (selfI.metrixConfig.eventBufferingEnabled) {
            [selfI.logger info:@"Buffered event %@", stopPackage.suffix];
        } else {
            [selfI.packageHandler sendFirstPackage];
        }

        // if it is in the background and it can send, start the background timer
        if (selfI.metrixConfig.sendInBackground && [selfI.internalState isInBackground]) {
            [selfI startBackgroundTimerI:selfI];
        }
    }
}

- (void)cancelSessionStopTimers:(MXActivityHandler *)selfI{
    if(selfI.sessionStopCheckerTimer != nil){
        [selfI.sessionStopCheckerTimer cancel];
    }
}


- (void)customEventI:(MXActivityHandler *)selfI
               event:(MXCustomEvent *)event {
    if (![selfI isEnabledI:selfI]) return;
    if (![selfI checkCustomEventI:selfI event:event]) return;
//    if (![selfI checkTransactionIdI:selfI transactionId:event.transactionId]) return;
//    if (selfI.activityState.isGdprForgotten) { return; }

    double now = [NSDate.date timeIntervalSince1970];

    selfI.activityState.eventCount++;
    [selfI updateActivityStateI:selfI now:now];

    // create and populate event package
    MXPackageBuilder *eventBuilder = [[MXPackageBuilder alloc]
            initWithDeviceInfo:selfI.deviceInfo
                 activityState:selfI.activityState
                        config:selfI.metrixConfig
                     createdAt:now];
    MXActivityPackage *eventPackage = [eventBuilder buildCustomEventPackage:event
                                                                  isInDelay:[selfI.internalState isInDelayedStart]];
    [selfI.packageHandler addPackage:eventPackage];

    if (selfI.metrixConfig.eventBufferingEnabled) {
        [selfI.logger info:@"Buffered event %@", eventPackage.suffix];
    } else {
        [selfI.packageHandler sendFirstPackage];
    }

    // if it is in the background and it can send, start the background timer
    if (selfI.metrixConfig.sendInBackground && [selfI.internalState isInBackground]) {
        [selfI startBackgroundTimerI:selfI];
    }

    [selfI writeActivityStateI:selfI];
}

- (void)screenI:(MXActivityHandler *)selfI
           name:(NSString *)screenName {
    if (![selfI isEnabledI:selfI]) return;
    if (![selfI checkScreen:selfI name:screenName]) return;

    double now = [NSDate.date timeIntervalSince1970];

    [selfI updateActivityStateI:selfI now:now];

    [selfI.activityState addScreen:screenName];

    [selfI writeActivityStateI:selfI];
}

- (void)launchCustomEventResponseTasksI:(MXActivityHandler *)selfI
                      eventResponseData:(MXCustomEventResponseData *)eventResponseData {
}

- (void)launchSessionResponseTasksI:(MXActivityHandler *)selfI
                sessionResponseData:(MXSessionStartResponseData *)sessionResponseData {
    if (!selfI.activityState.userId) {
        selfI.activityState.userId = sessionResponseData.userId;
    }

    selfI.activityState.attributes = sessionResponseData.attributes;

    // mark install as tracked on success
    if (sessionResponseData.success) {
        [MXUserDefaults setInstallTracked];
    }


    selfI.internalState.sessionResponseProcessed = YES;

    MXSessionParameters *sp = [[MXSessionParameters alloc] init];
    sp.userId = sessionResponseData.userId;
    sp.attributes = [sessionResponseData.attributes mutableCopy];
    [selfI.packageHandler updatePackages:sp];
}

- (void)setEnabledI:(MXActivityHandler *)selfI enabled:(BOOL)enabled {
    // compare with the saved or internal state
    if (![selfI hasChangedStateI:selfI
                   previousState:[selfI isEnabled]
                       nextState:enabled
                     trueMessage:@"Metrix already enabled"
                    falseMessage:@"Metrix already disabled"]) {
        return;
    }

    // save new enabled state in internal state
    selfI.internalState.enabled = enabled;

    if (selfI.activityState == nil) {
        [selfI checkStatusI:selfI
               pausingState:!enabled
             pausingMessage:@"Handlers will start as paused due to the SDK being disabled"
       remainsPausedMessage:@"Handlers will still start as paused"
           unPausingMessage:@"Handlers will start as active due to the SDK being enabled"];
        return;
    }

    // Save new enabled state in activity state.
    selfI.activityState.enabled = enabled;
    [selfI writeActivityStateI:selfI];

    // Check if upon enabling install has been tracked.
    if (enabled) {
        if (![MXUserDefaults getInstallTracked]) {
            double now = [NSDate.date timeIntervalSince1970];
            [self trackNewSessionI:now withActivityHandler:selfI];
        }
    }

    [selfI checkStatusI:selfI
           pausingState:!enabled
         pausingMessage:@"Pausing handlers due to SDK being disabled"
   remainsPausedMessage:@"Handlers remain paused"
       unPausingMessage:@"Resuming handlers due to SDK being enabled"];
}

- (void)setOfflineModeI:(MXActivityHandler *)selfI
                offline:(BOOL)offline {
    // compare with the internal state
    if (![selfI hasChangedStateI:selfI
                   previousState:[selfI.internalState isOffline]
                       nextState:offline
                     trueMessage:@"Metrix already in offline mode"
                    falseMessage:@"Metrix already in online mode"]) {
        return;
    }

    // save new offline state in internal state
    selfI.internalState.offline = offline;

    if (selfI.activityState == nil) {
        [selfI checkStatusI:selfI
               pausingState:offline
             pausingMessage:@"Handlers will start paused due to SDK being offline"
       remainsPausedMessage:@"Handlers will still start as paused"
           unPausingMessage:@"Handlers will start as active due to SDK being online"];
        return;
    }

    [selfI checkStatusI:selfI
           pausingState:offline
         pausingMessage:@"Pausing handlers to put SDK offline mode"
   remainsPausedMessage:@"Handlers remain paused"
       unPausingMessage:@"Resuming handlers to put SDK in online mode"];
}

- (BOOL)hasChangedStateI:(MXActivityHandler *)selfI
           previousState:(BOOL)previousState
               nextState:(BOOL)nextState
             trueMessage:(NSString *)trueMessage
            falseMessage:(NSString *)falseMessage {
    if (previousState != nextState) {
        return YES;
    }

    if (previousState) {
        [selfI.logger debug:trueMessage];
    } else {
        [selfI.logger debug:falseMessage];
    }

    return NO;
}

- (void)checkStatusI:(MXActivityHandler *)selfI
        pausingState:(BOOL)pausingState
      pausingMessage:(NSString *)pausingMessage
remainsPausedMessage:(NSString *)remainsPausedMessage
    unPausingMessage:(NSString *)unPausingMessage {
    // it is changing from an active state to a pause state
    if (pausingState) {
        [selfI.logger info:pausingMessage];
    }
        // check if it's remaining in a pause state
    else if ([selfI pausedI:selfI sdkClickHandlerOnly:NO]) {
        // including the sdk click handler
        if ([selfI pausedI:selfI sdkClickHandlerOnly:YES]) {
            [selfI.logger info:remainsPausedMessage];
        } else {
            // or except it
            [selfI.logger info:[remainsPausedMessage stringByAppendingString:@", except the Sdk Click Handler"]];
        }
    } else {
        // it is changing from a pause state to an active state
        [selfI.logger info:unPausingMessage];
    }

    [selfI updateHandlersStatusAndSendI:selfI];
}

#pragma mark - private

- (BOOL)isEnabledI:(MXActivityHandler *)selfI {
    if (selfI.activityState != nil) {
        return selfI.activityState.enabled;
    } else {
        return [selfI.internalState isEnabled];
    }
}


- (BOOL)itHasToUpdatePackagesI:(MXActivityHandler *)selfI {
    if (selfI.activityState != nil) {
        return selfI.activityState.updatePackages;
    } else {
        return [selfI.internalState itHasToUpdatePackages];
    }
}

// returns whether or not the activity state should be written
- (BOOL)updateActivityStateI:(MXActivityHandler *)selfI
                         now:(double)now {
    if (![selfI checkActivityStateI:selfI]) return NO;

    double lastInterval = now - selfI.activityState.lastActivity;

    // ignore late updates
    if (lastInterval > kSessionInterval) return NO;

    selfI.activityState.lastActivity = now;

    if (lastInterval < 0) {
        [selfI.logger error:@"Time travel!"];
        return YES;
    } else {
        selfI.activityState.sessionLength += lastInterval;
        selfI.activityState.timeSpent += lastInterval;
    }

    return YES;
}

- (void)writeActivityStateI:(MXActivityHandler *)selfI {
    @synchronized ([MXActivityState class]) {
        if (selfI.activityState == nil) {
            return;
        }
        [MXUtil writeObject:selfI.activityState fileName:kActivityStateFilename objectName:@"Activity state"];
    }
}

- (void)teardownActivityStateS {
    @synchronized ([MXActivityState class]) {
        if (self.activityState == nil) {
            return;
        }
        self.activityState = nil;
    }
}

- (void)writeAttributionI:(MXActivityHandler *)selfI {
    @synchronized ([MXAttribution class]) {
        if (selfI.attribution == nil) {
            return;
        }
        [MXUtil writeObject:selfI.attribution fileName:kAttributionFilename objectName:@"Attribution"];
    }
}

- (void)teardownAttributionS {
    @synchronized ([MXAttribution class]) {
        if (self.attribution == nil) {
            return;
        }
        self.attribution = nil;
    }
}

- (void)readActivityState {
    [NSKeyedUnarchiver setClass:[MXActivityState class] forClassName:@"AIActivityState"];
    self.activityState = [MXUtil readObject:kActivityStateFilename
                                 objectName:@"Activity state"
                                      class:[MXActivityState class]];
}

- (void)readAttribution {
    self.attribution = [MXUtil readObject:kAttributionFilename
                               objectName:@"Attribution"
                                    class:[MXAttribution class]];
}

# pragma mark - handlers status

- (void)updateHandlersStatusAndSendI:(MXActivityHandler *)selfI {
    // check if it should stop sending
    if (![selfI toSendI:selfI]) {
        [selfI pauseSendingI:selfI];
        return;
    }

    [selfI resumeSendingI:selfI];

    // try to send if it's the first launch and it hasn't received the session response
    //  even if event buffering is enabled
    if ([selfI.internalState isFirstLaunch] &&
            [selfI.internalState hasSessionResponseNotBeenProcessed]) {
        [selfI.packageHandler sendFirstPackage];
    }

    // try to send
    if (!selfI.metrixConfig.eventBufferingEnabled) {
        [selfI.packageHandler sendFirstPackage];
    }
}

- (void)pauseSendingI:(MXActivityHandler *)selfI {
    [selfI.attributionHandler pauseSending];
    [selfI.packageHandler pauseSending];
}

- (void)resumeSendingI:(MXActivityHandler *)selfI {
    [selfI.attributionHandler resumeSending];
    [selfI.packageHandler resumeSending];
}

- (BOOL)pausedI:(MXActivityHandler *)selfI {
    return [selfI pausedI:selfI sdkClickHandlerOnly:NO];
}

- (BOOL)    pausedI:(MXActivityHandler *)selfI
sdkClickHandlerOnly:(BOOL)sdkClickHandlerOnly {
    if (sdkClickHandlerOnly) {
        // sdk click handler is paused if either:
        return [selfI.internalState isOffline] ||    // it's offline
                ![selfI isEnabledI:selfI];                  // is disabled
    }
    // other handlers are paused if either:
    return [selfI.internalState isOffline] ||        // it's offline
            ![selfI isEnabledI:selfI] ||             // is disabled
            [selfI.internalState isInDelayedStart];      // is in delayed start
}

- (BOOL)toSendI:(MXActivityHandler *)selfI {
    return [selfI toSendI:selfI sdkClickHandlerOnly:NO];
}

- (BOOL)    toSendI:(MXActivityHandler *)selfI
sdkClickHandlerOnly:(BOOL)sdkClickHandlerOnly {
    // don't send when it's paused
    if ([selfI pausedI:selfI sdkClickHandlerOnly:sdkClickHandlerOnly]) {
        return NO;
    }

    // has the option to send in the background -> is to send
    if (selfI.metrixConfig.sendInBackground) {
        return YES;
    }

    // doesn't have the option -> depends on being on the background/foreground
    return [selfI.internalState isInForeground];
}

- (void)setAskingAttributionI:(MXActivityHandler *)selfI
            askingAttribution:(BOOL)askingAttribution {
    selfI.activityState.askingAttribution = askingAttribution;
    [selfI writeActivityStateI:selfI];
}

# pragma mark - timer

- (void)startForegroundTimerI:(MXActivityHandler *)selfI {
    // don't start the timer when it's disabled
    if (![selfI isEnabledI:selfI]) {
        return;
    }

    [selfI.foregroundTimer resume];
}

- (void)stopForegroundTimerI:(MXActivityHandler *)selfI {
    [selfI.foregroundTimer suspend];
}

- (void)foregroundTimerFiredI:(MXActivityHandler *)selfI {
    // stop the timer cycle when it's disabled
    if (![selfI isEnabledI:selfI]) {
        [selfI stopForegroundTimerI:selfI];
        return;
    }

    if ([selfI toSendI:selfI]) {
        [selfI.packageHandler sendFirstPackage];
    }

    double now = [NSDate.date timeIntervalSince1970];
    if ([selfI updateActivityStateI:selfI now:now]) {
        [selfI writeActivityStateI:selfI];
    }
}

- (void)startBackgroundTimerI:(MXActivityHandler *)selfI {
    if (selfI.backgroundTimer == nil) {
        return;
    }

    // check if it can send in the background
    if (![selfI toSendI:selfI]) {
        return;
    }

    // background timer already started
    if ([selfI.backgroundTimer fireIn] > 0) {
        return;
    }

    [selfI.backgroundTimer startIn:kBackgroundTimerInterval];
}

- (void)stopBackgroundTimerI:(MXActivityHandler *)selfI {
    if (selfI.backgroundTimer == nil) {
        return;
    }

    [selfI.backgroundTimer cancel];
}

- (void)backgroundTimerFiredI:(MXActivityHandler *)selfI {
    if ([selfI toSendI:selfI]) {
        [selfI.packageHandler sendFirstPackage];
    }
}

#pragma mark - delay

- (void)delayStartI:(MXActivityHandler *)selfI {
    // it's not configured to start delayed or already finished
    if ([selfI.internalState isNotInDelayedStart]) {
        return;
    }

    // the delay has already started
    if ([selfI itHasToUpdatePackagesI:selfI]) {
        return;
    }

    // check against max start delay
    double delayStart = selfI.metrixConfig.delayStart;
    double maxDelayStart = [MXMetrixFactory maxDelayStart];

    if (delayStart > maxDelayStart) {
        NSString *delayStartFormatted = [MXUtil secondsNumberFormat:delayStart];
        NSString *maxDelayStartFormatted = [MXUtil secondsNumberFormat:maxDelayStart];

        [selfI.logger warn:@"Delay start of %@ seconds bigger than max allowed value of %@ seconds", delayStartFormatted, maxDelayStartFormatted];
        delayStart = maxDelayStart;
    }

    NSString *delayStartFormatted = [MXUtil secondsNumberFormat:delayStart];
    [selfI.logger info:@"Waiting %@ seconds before starting first session", delayStartFormatted];

    [selfI.delayStartTimer startIn:delayStart];

    selfI.internalState.updatePackages = YES;

    if (selfI.activityState != nil) {
        selfI.activityState.updatePackages = YES;
        [selfI writeActivityStateI:selfI];
    }
}

- (void)sendFirstPackagesI:(MXActivityHandler *)selfI {
    if ([selfI.internalState isNotInDelayedStart]) {
        [selfI.logger info:@"Start delay expired or never configured"];
        return;
    }
    // update packages in queue
    [selfI updatePackagesI:selfI];
    // no longer is in delay start
    selfI.internalState.delayStart = NO;
    // cancel possible still running timer if it was called by user
    [selfI.delayStartTimer cancel];
    // and release timer
    selfI.delayStartTimer = nil;
    // update the status and try to send first package
    [selfI updateHandlersStatusAndSendI:selfI];
}

- (void)updatePackagesI:(MXActivityHandler *)selfI {
    // update activity packages
    [selfI.packageHandler updatePackages:selfI.sessionParameters];
    // no longer needs to update packages
    selfI.internalState.updatePackages = NO;
    if (selfI.activityState != nil) {
        selfI.activityState.updatePackages = NO;
        [selfI writeActivityStateI:selfI];
    }
}

#pragma mark - session parameters

- (void)preLaunchActionsI:(MXActivityHandler *)selfI
    preLaunchActionsArray:(NSArray *)preLaunchActionsArray {
    if (preLaunchActionsArray == nil) {
        return;
    }
    for (activityHandlerBlockI activityHandlerActionI in preLaunchActionsArray) {
        activityHandlerActionI(selfI);
    }
}

#pragma mark - notifications

- (void)addNotificationObserver {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;

    [center removeObserver:self];
    [center addObserver:self
               selector:@selector(applicationDidBecomeActive)
                   name:UIApplicationDidBecomeActiveNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(applicationWillResignActive)
                   name:UIApplicationWillResignActiveNotification
                 object:nil];

    [center addObserver:self
               selector:@selector(removeNotificationObserver)
                   name:UIApplicationWillTerminateNotification
                 object:nil];
}

- (void)removeNotificationObserver {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

#pragma mark - checks

- (BOOL)checkCustomEventI:(MXActivityHandler *)selfI
                    event:(MXCustomEvent *)event {
    if (event == nil) {
        [selfI.logger error:@"Event missing"];
        return NO;
    }

    if (![event isValid]) {
        [selfI.logger error:@"Event not initialized correctly"];
        return NO;
    }

    return YES;
}

- (BOOL)checkScreen:(MXActivityHandler *)selfI
               name:(NSString *)screenName {
    if (screenName == nil) {
        [selfI.logger error:@"screen name missing"];
        return NO;
    }
    if (selfI.activityState == nil) {
        [selfI.logger error:@"screen name missing"];
        return NO;
    }

    return YES;
}

- (BOOL)checkEventI:(MXActivityHandler *)selfI
              event:(MXEvent *)event {
    if (event == nil) {
        [selfI.logger error:@"Event missing"];
        return NO;
    }

    if (![event isValid]) {
        [selfI.logger error:@"Event not initialized correctly"];
        return NO;
    }

    return YES;
}

- (BOOL)checkActivityStateI:(MXActivityHandler *)selfI {
    if (selfI.activityState == nil) {
        [selfI.logger error:@"Missing activity state"];
        return NO;
    }
    return YES;
}
@end
