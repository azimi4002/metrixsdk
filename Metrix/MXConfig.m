//
//  MetrixConfig.m
//  metrix
//

#import "MXConfig.h"
#import "MXMetrixFactory.h"
#import "MXLogger.h"
#import "MXUtil.h"
#import "Metrix.h"

@interface MXConfig()

@property (nonatomic, weak) id<MXLogger> logger;

@end

@implementation MXConfig

+ (MXConfig *)configWithAppId:(nonnull NSString *)appId
                   environment:(nonnull NSString *)environment {
    return [[MXConfig alloc] initWithAppId:appId environment:environment];
}

+ (MXConfig *)configWithAppId:(NSString *)appId
                  environment:(NSString *)environment
        allowSuppressLogLevel:(BOOL)allowSuppressLogLevel
{
    return [[MXConfig alloc] initWithAppId:appId environment:environment allowSuppressLogLevel:allowSuppressLogLevel];
}

- (id)initWithAppId:(nonnull NSString *)appId
        environment:(nonnull NSString *)environment
{
    return [self initWithAppId:appId
                   environment:environment
         allowSuppressLogLevel:NO];
}

- (id)  initWithAppId:(nonnull NSString *)appId
          environment:(nonnull NSString *)environment
allowSuppressLogLevel:(BOOL)allowSuppressLogLevel
{
    self = [super init];
    if (self == nil) return nil;

    self.logger = MXMetrixFactory.logger;
    // default values
    if (allowSuppressLogLevel && [MXEnvironmentProduction isEqualToString:environment]) {
        [self setLogLevel:MXLogLevelSuppress environment:environment];
    } else {
        [self setLogLevel:MXLogLevelInfo environment:environment];
    }

    if (![self checkEnvironment:environment]) return self;
//    if (![self checkAppToken:appId]) return self;

    _appId = appId;
    _environment = environment;
    // default values
    self.eventBufferingEnabled = NO;
    self.isScreenFlowAutoFill = YES;
    self.sendInBackground = YES;

    return self;
}

- (void)setLogLevel:(MXLogLevel)logLevel {
    [self setLogLevel:logLevel environment:self.environment];
}

- (void)setLogLevel:(MXLogLevel)logLevel
        environment:(NSString *)environment
{
    [self.logger setLogLevel:logLevel
     isProductionEnvironment:[MXEnvironmentProduction isEqualToString:environment]];
}

- (void)setDelegate:(NSObject<MetrixDelegate> *)delegate {
    BOOL hasResponseDelegate = NO;
    BOOL implementsDeeplinkCallback = NO;

    if ([MXUtil isNull:delegate]) {
        [self.logger warn:@"Delegate is nil"];
        _delegate = nil;
        return;
    }

    if ([delegate respondsToSelector:@selector(metrixEventTrackingSucceeded:)]) {
        [self.logger debug:@"Delegate implements metrixEventTrackingSucceeded:"];

        hasResponseDelegate = YES;
    }

    if ([delegate respondsToSelector:@selector(metrixEventTrackingFailed:)]) {
        [self.logger debug:@"Delegate implements metrixEventTrackingFailed:"];

        hasResponseDelegate = YES;
    }

    if ([delegate respondsToSelector:@selector(metrixSessionTrackingSucceeded:)]) {
        [self.logger debug:@"Delegate implements metrixSessionTrackingSucceeded:"];

        hasResponseDelegate = YES;
    }

    if ([delegate respondsToSelector:@selector(metrixSessionTrackingFailed:)]) {
        [self.logger debug:@"Delegate implements metrixSessionTrackingFailed:"];

        hasResponseDelegate = YES;
    }

    if ([delegate respondsToSelector:@selector(metrixDeeplinkResponse:)]) {
        [self.logger debug:@"Delegate implements metrixDeeplinkResponse:"];

        // does not enable hasDelegate flag
        implementsDeeplinkCallback = YES;
    }

    if (!(hasResponseDelegate || implementsDeeplinkCallback)) {
        [self.logger error:@"Delegate does not implement any optional method"];
        _delegate = nil;
        return;
    }

    _delegate = delegate;
}

- (BOOL)checkEnvironment:(NSString *)environment
{
    if ([MXUtil isNull:environment]) {
        [self.logger error:@"Missing environment"];
        return NO;
    }
    if ([environment isEqualToString:MXEnvironmentSandbox]) {
        [self.logger warnInProduction:@"SANDBOX: Metrix is running in Sandbox mode. Use this setting for testing. Don't forget to set the environment to `production` before publishing"];
        return YES;
    } else if ([environment isEqualToString:MXEnvironmentProduction]) {
        [self.logger warnInProduction:@"PRODUCTION: Metrix is running in Production mode. Use this setting only for the build that you want to publish. Set the environment to `sandbox` if you want to test your app!"];
        return YES;
    }
    [self.logger error:@"Unknown environment '%@'", environment];
    return NO;
}

//- (BOOL)checkAppToken:(NSString *)appId {
//    if ([MXUtil isNull:appId]) {
//        [self.logger error:@"Missing App Token"];
//        return NO;
//    }
//    if (appId.length != 12) {
//        [self.logger error:@"Malformed App Token '%@'", appId];
//        return NO;
//    }
//    return YES;
//}

- (BOOL)isValid {
    return self.appId != nil;
}

- (void)setAppSecret:(NSUInteger)secretId
               info1:(NSUInteger)info1
               info2:(NSUInteger)info2
               info3:(NSUInteger)info3
               info4:(NSUInteger)info4 {
    _secretId = [NSString stringWithFormat:@"%lu", (unsigned long)secretId];
    _appSecret = [NSString stringWithFormat:@"%lu%lu%lu%lu",
                   (unsigned long)info1,
                   (unsigned long)info2,
                   (unsigned long)info3,
                   (unsigned long)info4];
}

-(id)copyWithZone:(NSZone *)zone
{
    MXConfig* copy = [[[self class] allocWithZone:zone] init];
    if (copy) {
        copy->_appId = [self.appId copyWithZone:zone];
        copy->_environment = [self.environment copyWithZone:zone];
        copy.logLevel = self.logLevel;
        copy.sdkPrefix = [self.sdkPrefix copyWithZone:zone];
        copy.trackerToken = [self.trackerToken copyWithZone:zone];
        copy.eventBufferingEnabled = self.eventBufferingEnabled;
        copy.sendInBackground = self.sendInBackground;
        copy.delayStart = self.delayStart;
        copy.userAgent = [self.userAgent copyWithZone:zone];
        copy.isDeviceKnown = self.isDeviceKnown;
        copy.isScreenFlowAutoFill = self.isScreenFlowAutoFill;
        copy->_secretId = [self.secretId copyWithZone:zone];
        copy->_appSecret = [self.appSecret copyWithZone:zone];
        // metrix delegate not copied
    }

    return copy;
}

@end
