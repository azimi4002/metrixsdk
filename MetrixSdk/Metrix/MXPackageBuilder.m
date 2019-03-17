//
//  MXPackageBuilder.m
//  Metrix SDK
//

#import "MXUtil.h"
#import "MXAttribution.h"
#import "MXMetrixFactory.h"
#import "MXPackageBuilder.h"
#import "MXActivityPackage.h"
#import "NSData+MXAdditions.h"
#import "UIDevice+MXAdditions.h"
#import "MXCustomEvent.h"

@interface MXPackageBuilder()

@property (nonatomic, assign) double createdAt;

@property (nonatomic, weak) MXConfig *metrixConfig;

@property (nonatomic, weak) MXDeviceInfo *deviceInfo;

@property (nonatomic, copy) MXActivityState *activityState;

//@property (nonatomic, weak) MXSessionParameters *sessionParameters;

@end

@implementation MXPackageBuilder

#pragma mark - Object lifecycle methods

- (id)initWithDeviceInfo:(MXDeviceInfo *)deviceInfo
           activityState:(MXActivityState *)activityState
                  config:(MXConfig *)metrixConfig
               createdAt:(double)createdAt {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    self.createdAt = createdAt;
    self.deviceInfo = deviceInfo;
    self.metrixConfig = metrixConfig;
    self.activityState = activityState;

    return self;
}

- (id)initWithDeviceInfo:(MXDeviceInfo *)deviceInfo
           activityState:(MXActivityState *)activityState
                  config:(MXConfig *)metrixConfig
       sessionParameters:(MXSessionParameters *)sessionParameters
               createdAt:(double)createdAt {
    self = [super init];
    if (self == nil) {
        return nil;
    }

    self.createdAt = createdAt;
    self.deviceInfo = deviceInfo;
    self.metrixConfig = metrixConfig;
    self.activityState = activityState;
//    self.sessionParameters = sessionParameters;

    return self;
}

#pragma mark - Public methods

- (MXActivityPackage *)buildSessionStartPackage:(BOOL)isInDelay {
    NSMutableDictionary *parameters = [self getSessionStartParameters:isInDelay];
    MXActivityPackage *sessionPackage = [self defaultActivityPackage];
    sessionPackage.path = [self needInitRequest]? BASE_PATH_INIT: BASE_PATH_EVENTS;
    sessionPackage.activityKind = MXActivityKindSessionStart;
    sessionPackage.suffix = @"";
    sessionPackage.parameters = parameters;
    return sessionPackage;
}

- (MXActivityPackage *)buildSessionStopPackage {
    NSMutableDictionary *parameters = [self getSessionStopParameters];
    MXActivityPackage *sessionStopPackage = [self defaultActivityPackage];
    sessionStopPackage.path = BASE_PATH_EVENTS;
    sessionStopPackage.activityKind = MXActivityKindSessionStop;
    sessionStopPackage.suffix = @"";
    sessionStopPackage.parameters = parameters;
    return sessionStopPackage;
}

- (MXActivityPackage *)buildCustomEventPackage:(MXCustomEvent *)event
                                isInDelay:(BOOL)isInDelay {
    NSMutableDictionary *parameters = [self getCustomEventParameters:isInDelay forEventPackage:event];
    MXActivityPackage *eventPackage = [self defaultActivityPackage];
    eventPackage.path = @"/events";
    eventPackage.activityKind = MXActivityKindCustomEvent;
//    eventPackage.suffix = [self eventSuffix:event];
    eventPackage.parameters = parameters;

//    if (isInDelay) {
//        eventPackage.callbackParameters = event.callbackParameters;
//        eventPackage.partnerParameters = event.partnerParameters;
//    }

    return eventPackage;
}

+ (void)parameters:(NSMutableDictionary *)parameters setDictionary:(NSDictionary *)dictionary forKey:(NSString *)key {
    if (dictionary == nil) {
        return;
    }
    if (dictionary.count == 0) {
        return;
    }
    [parameters setObject:dictionary forKey:key];
}

+ (void)parameters:(NSMutableDictionary *)parameters setArray:(NSArray *)array forKey:(NSString *)key {
    if (array == nil) {
        return;
    }
    if (array.count == 0) {
        return;
    }
    [parameters setObject:array forKey:key];
}

//+ (void)parameters:(NSMutableDictionary *)parameters setDictionary:(NSDictionary *)dictionary forKey:(NSString *)key {
//    if (dictionary == nil) {
//        return;
//    }
//    if (dictionary.count == 0) {
//        return;
//    }
//
//    NSDictionary *convertedDictionary = [MXUtil convertDictionaryValues:dictionary];
//    [MXPackageBuilder parameters:parameters setDictionaryJson:convertedDictionary forKey:key];
//}

+ (void)parameters:(NSMutableDictionary *)parameters setString:(NSString *)value forKey:(NSString *)key {
    if (value == nil || [value isEqualToString:@""]) {
        return;
    }
    [parameters setObject:value forKey:key];
}

#pragma mark - Private & helper methods

- (NSMutableDictionary *)getSessionStartParameters:(BOOL)isInDelay {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];

    [MXPackageBuilder parameters:parameters setString:[MXUtil formatSeconds1970:self.createdAt] forKey:@"event_time"];
    [MXPackageBuilder parameters:parameters setString:[MXActivityKindUtil activityKindToString:MXActivityKindSessionStart] forKey:@"event_type"];
    [MXPackageBuilder parameters:parameters setString:[MXUtil sdkVersion] forKey:@"sdk_version"];
    [MXPackageBuilder parameters:parameters setString:@"0.0.0.0" forKey:@"ip"];
    [MXPackageBuilder parameters:parameters setDictionary:@{@"id":self.metrixConfig.appId,
            @"package":self.deviceInfo.bundeIdentifier, @"version":self.deviceInfo.bundleVersion} forKey:@"app_info"];

    [MXPackageBuilder parameters:parameters setDictionary:
            @{@"install_complete_timestamp":@([MXUtil getInstallTimestamp]),
            @"update_timestamp":@([MXUtil getUpdateTimestamp])} forKey:@"install_info"];

    if(self.metrixConfig.trackerToken){
        [MXPackageBuilder parameters:parameters setDictionary:@{@"tracker_token":self.metrixConfig.trackerToken} forKey:@"attributes"];
    }

     NSDictionary *os = @{@"name":self.deviceInfo.osName, @"version": @([self.deviceInfo.systemVersion doubleValue]),
            @"version_name":self.deviceInfo.osBuild};
    NSDictionary *screen = @{@"width":@(self.deviceInfo.screenWidth), @"height":@(self.deviceInfo.screenHeight)};
    [MXPackageBuilder parameters:parameters setDictionary:@{@"idfa": [MXUtil idfa], @"cpu_abi":self.deviceInfo.cpuSubtype,
            @"brand":@"apple", @"manufacturer":@"apple", @"model":self.deviceInfo.deviceName, @"product":self.deviceInfo.deviceType,
            @"language":self.deviceInfo.languageCode, @"os":os ,@"screen":screen} forKey:@"device_info"];

    NSMutableDictionary *connectionInfo = [[NSMutableDictionary alloc] init];
    if([MXUtil readMCC])connectionInfo[@"mcc"] = [MXUtil readMCC];
    if([MXUtil readMNC])connectionInfo[@"mnc"] = [MXUtil readMNC];
    if([MXUtil readCurrentRadioAccessTechnology])connectionInfo[@"network_type"] = [MXUtil readCurrentRadioAccessTechnology];
    if([MXUtil readReachabilityFlags])connectionInfo[@"connection_type"] = [MXUtil readReachabilityFlags];
    [MXPackageBuilder parameters:parameters setDictionary:connectionInfo forKey:@"connection_info"];

    if (self.activityState != nil) {
        [MXPackageBuilder parameters:parameters setString:self.activityState.sessionId forKey:@"session_id"];
        [MXPackageBuilder parameters:parameters setInt:self.activityState.sessionCount forKey:@"session_num"];
        [MXPackageBuilder parameters:parameters setString:self.activityState.userId forKey:@"user_id"];

    }

    return parameters;
}

- (NSMutableDictionary *)getSessionStopParameters {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];

    [MXPackageBuilder parameters:parameters setString:[MXUtil formatSeconds1970:self.createdAt] forKey:@"event_time"];
    [MXPackageBuilder parameters:parameters setString:self.activityState.sessionId forKey:@"session_id"];
    [MXPackageBuilder parameters:parameters setString:self.activityState.userId forKey:@"user_id"];
    [MXPackageBuilder parameters:parameters setString:[MXActivityKindUtil activityKindToString:MXActivityKindSessionStop] forKey:@"event_type"];
    [MXPackageBuilder parameters:parameters setString:self.metrixConfig.appId forKey:@"app_id"];

    if (self.activityState != nil) {
        [MXPackageBuilder parameters:parameters setNumber:@((long)self.activityState.lastInterval*1000) forKey:@"duration_millis"];
        [MXPackageBuilder parameters:parameters setArray:[self.activityState getCompleteScreenFlow] forKey:@"screen_flows"];
    }

    return parameters;
}

- (NSMutableDictionary *)getCustomEventParameters:(BOOL)isInDelay forEventPackage:(MXCustomEvent *)event {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];

    [MXPackageBuilder parameters:parameters setString:[MXUtil formatSeconds1970:self.createdAt] forKey:@"event_time"];
    [MXPackageBuilder parameters:parameters setString:self.activityState.sessionId forKey:@"session_id"];
    [MXPackageBuilder parameters:parameters setString:self.activityState.userId forKey:@"user_id"];
    [MXPackageBuilder parameters:parameters setString:[MXActivityKindUtil activityKindToString:MXActivityKindCustomEvent] forKey:@"event_type"];
    [MXPackageBuilder parameters:parameters setString:self.metrixConfig.appId forKey:@"app_id"];
    if(event.slug){
        [MXPackageBuilder parameters:parameters setString:event.slug forKey:@"slug"];
    }
    [MXPackageBuilder parameters:parameters setDictionary:event.attributes forKey:@"attributes"];
    [MXPackageBuilder parameters:parameters setDictionary:event.metrics forKey:@"metrics"];

    return parameters;
}


- (MXActivityPackage *)defaultActivityPackage {
    MXActivityPackage *activityPackage = [[MXActivityPackage alloc] init];
    activityPackage.clientSdk = self.deviceInfo.clientSdk;
    return activityPackage;
}

- (NSString *)eventSuffix:(MXEvent *)event {
    if (event.revenue == nil) {
        return [NSString stringWithFormat:@"'%@'", event.eventToken];
    } else {
        return [NSString stringWithFormat:@"(%.5f %@, '%@')", [event.revenue doubleValue], event.currency, event.eventToken];
    }
}

+ (void)parameters:(NSMutableDictionary *)parameters setInt:(int)value forKey:(NSString *)key {
    if (value < 0) {
        return;
    }
//    NSString *valueString = [NSString stringWithFormat:@"%d", value];
    [parameters setValue:@(value) forKey:key];
//    [MXPackageBuilder parameters:parameters setString:valueString forKey:key];
}

+ (void)parameters:(NSMutableDictionary *)parameters setDate1970:(double)value forKey:(NSString *)key {
    if (value < 0) {
        return;
    }
    NSString *dateString = [MXUtil formatSeconds1970:value];
    [MXPackageBuilder parameters:parameters setString:dateString forKey:key];
}

+ (void)parameters:(NSMutableDictionary *)parameters setDate:(NSDate *)value forKey:(NSString *)key {
    if (value == nil) {
        return;
    }
    NSString *dateString = [MXUtil formatDate:value];
    [MXPackageBuilder parameters:parameters setString:dateString forKey:key];
}

+ (void)parameters:(NSMutableDictionary *)parameters setDuration:(double)value forKey:(NSString *)key {
    if (value < 0) {
        return;
    }
    int intValue = round(value);
    [MXPackageBuilder parameters:parameters setInt:intValue forKey:key];
}

+ (void)parameters:(NSMutableDictionary *)parameters setDictionaryJson:(NSDictionary *)dictionary forKey:(NSString *)key {
    if (dictionary == nil) {
        return;
    }
    if (dictionary.count == 0) {
        return;
    }
    if (![NSJSONSerialization isValidJSONObject:dictionary]) {
        return;
    }

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    NSString *dictionaryString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [MXPackageBuilder parameters:parameters setString:dictionaryString forKey:key];
}

+ (void)parameters:(NSMutableDictionary *)parameters setBool:(BOOL)value forKey:(NSString *)key {
    int valueInt = [[NSNumber numberWithBool:value] intValue];
    [MXPackageBuilder parameters:parameters setInt:valueInt forKey:key];
}

+ (void)parameters:(NSMutableDictionary *)parameters setNumber:(NSNumber *)value forKey:(NSString *)key {
    if (value == nil) {
        return;
    }
    NSString *numberString = [NSString stringWithFormat:@"%.5f", [value doubleValue]];
    [MXPackageBuilder parameters:parameters setString:numberString forKey:key];
}

+ (void)parameters:(NSMutableDictionary *)parameters setNumberInt:(NSNumber *)value forKey:(NSString *)key {
    if (value == nil) {
        return;
    }
    [MXPackageBuilder parameters:parameters setInt:[value intValue] forKey:key];
}

- (BOOL)needInitRequest{
    return !self.activityState || !self.activityState.userId || [self.activityState.userId length] <= 0;
}

@end
