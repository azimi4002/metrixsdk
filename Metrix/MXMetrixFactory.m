//
//  MXMetrixFactory.m
//  Metrix
//

#import "MXMetrixFactory.h"

static id<MXPackageHandler> internalPackageHandler = nil;
static id<MXRequestHandler> internalRequestHandler = nil;
static id<MXActivityHandler> internalActivityHandler = nil;
static id<MXLogger> internalLogger = nil;
static id<MXAttributionHandler> internalAttributionHandler = nil;

static double internalSessionInterval    = -1;
static double intervalSubsessionInterval = -1;
static NSTimeInterval internalTimerInterval = -1;
static NSTimeInterval intervalTimerStart = -1;
static MXBackoffStrategy * packageHandlerBackoffStrategy = nil;
static BOOL internalTesting = NO;
static NSTimeInterval internalMaxDelayStart = -1;
static BOOL internaliAdFrameworkEnabled = YES;

static NSString * const kBaseUrl = @"https://analytics.metrix.ir/v2";
static NSString * internalBaseUrl = @"https://analytics.metrix.ir/v2";

@implementation MXMetrixFactory

+ (id<MXPackageHandler>)packageHandlerForActivityHandler:(id<MXActivityHandler>)activityHandler
                                            startsSending:(BOOL)startsSending {
    if (internalPackageHandler == nil) {
        return [MXPackageHandler handlerWithActivityHandler:activityHandler startsSending:startsSending];
    }

    return [internalPackageHandler initWithActivityHandler:activityHandler startsSending:startsSending];
}

+ (id<MXRequestHandler>)requestHandlerForPackageHandler:(id<MXPackageHandler>)packageHandler
                                      andActivityHandler:(id<MXActivityHandler>)activityHandler {
    if (internalRequestHandler == nil) {
        return [MXRequestHandler handlerWithPackageHandler:packageHandler
                                         andActivityHandler:activityHandler];
    }
    return [internalRequestHandler initWithPackageHandler:packageHandler
                                       andActivityHandler:activityHandler];
}

+ (id<MXActivityHandler>)activityHandlerWithConfig:(MXConfig *)metrixConfig
                     savedPreLaunch:(MXSavedPreLaunch *)savedPreLaunch
{
    if (internalActivityHandler == nil) {
        return [MXActivityHandler handlerWithConfig:metrixConfig
                                      savedPreLaunch:savedPreLaunch
                ];
    }
    return [internalActivityHandler initWithConfig:metrixConfig
                                    savedPreLaunch:savedPreLaunch];
}

+ (id<MXLogger>)logger {
    if (internalLogger == nil) {
        //  same instance of logger
        internalLogger = [[MXLogger alloc] init];
    }
    return internalLogger;
}

+ (double)sessionInterval {
    if (internalSessionInterval < 0) {
        return 30 * 60;           // 30 minutes
    }
    return internalSessionInterval;
}

+ (double)subsessionInterval {
    if (intervalSubsessionInterval == -1) {
        return 5;                 // in seconds
    }
    return intervalSubsessionInterval;
}

+ (NSTimeInterval)timerInterval {
    if (internalTimerInterval < 0) {
        return 60;                // 1 minute
    }
    return internalTimerInterval;
}

+ (NSTimeInterval)timerStart {
    if (intervalTimerStart < 0) {
        return 60;                 // 1 minute
    }
    return intervalTimerStart;
}

+ (MXBackoffStrategy *)packageHandlerBackoffStrategy {
    if (packageHandlerBackoffStrategy == nil) {
        return [MXBackoffStrategy backoffStrategyWithType:MXLongWait];
    }
    return packageHandlerBackoffStrategy;
}

+ (id<MXAttributionHandler>)attributionHandlerForActivityHandler:(id<MXActivityHandler>)activityHandler
                                                    startsSending:(BOOL)startsSending
{
    if (internalAttributionHandler == nil) {
        return [MXAttributionHandler handlerWithActivityHandler:activityHandler
                                                   startsSending:startsSending];
    }

    return [internalAttributionHandler initWithActivityHandler:activityHandler
                                                 startsSending:startsSending];
}

+ (BOOL)testing {
    return internalTesting;
}

+ (BOOL)iAdFrameworkEnabled {
    return internaliAdFrameworkEnabled;
}

+ (NSTimeInterval)maxDelayStart {
    if (internalMaxDelayStart < 0) {
        return 10.0;               // 10 seconds
    }
    return internalMaxDelayStart;
}

+ (NSString *)baseUrl {
    return internalBaseUrl;
}

+ (void)setPackageHandler:(id<MXPackageHandler>)packageHandler {
    internalPackageHandler = packageHandler;
}

+ (void)setRequestHandler:(id<MXRequestHandler>)requestHandler {
    internalRequestHandler = requestHandler;
}

+ (void)setActivityHandler:(id<MXActivityHandler>)activityHandler {
    internalActivityHandler = activityHandler;
}

+ (void)setLogger:(id<MXLogger>)logger {
    internalLogger = logger;
}

+ (void)setSessionInterval:(double)sessionInterval {
    internalSessionInterval = sessionInterval;
}

+ (void)setSubsessionInterval:(double)subsessionInterval {
    intervalSubsessionInterval = subsessionInterval;
}

+ (void)setTimerInterval:(NSTimeInterval)timerInterval {
    internalTimerInterval = timerInterval;
}

+ (void)setTimerStart:(NSTimeInterval)timerStart {
    intervalTimerStart = timerStart;
}

+ (void)setAttributionHandler:(id<MXAttributionHandler>)attributionHandler {
    internalAttributionHandler = attributionHandler;
}


+ (void)setPackageHandlerBackoffStrategy:(MXBackoffStrategy *)backoffStrategy {
    packageHandlerBackoffStrategy = backoffStrategy;
}

+ (void)setTesting:(BOOL)testing {
    internalTesting = testing;
}

+ (void)setiAdFrameworkEnabled:(BOOL)iAdFrameworkEnabled {
    internaliAdFrameworkEnabled = iAdFrameworkEnabled;
}

+ (void)setMaxDelayStart:(NSTimeInterval)maxDelayStart {
    internalMaxDelayStart = maxDelayStart;
}

+ (void)setBaseUrl:(NSString *)baseUrl {
    internalBaseUrl = baseUrl;
}

+ (void)teardown:(BOOL)deleteState {
    if (deleteState) {
        [MXActivityHandler deleteState];
        [MXPackageHandler deleteState];
    }
    internalPackageHandler = nil;
    internalRequestHandler = nil;
    internalActivityHandler = nil;
    internalLogger = nil;
    internalAttributionHandler = nil;

    internalSessionInterval    = -1;
    intervalSubsessionInterval = -1;
    internalTimerInterval = -1;
    intervalTimerStart = -1;
    packageHandlerBackoffStrategy = nil;
    internalTesting = NO;
    internalMaxDelayStart = -1;
    internalBaseUrl = kBaseUrl;
    internaliAdFrameworkEnabled = YES;
}
@end
