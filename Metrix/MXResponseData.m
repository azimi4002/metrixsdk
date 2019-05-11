//
//  MXResponseData.m
//  metrix
//

#import "MXResponseData.h"
#import "MXActivityKind.h"

@implementation MXResponseData

- (id)init {
    self = [super init];
    
    if (self == nil) {
        return nil;
    }
    
    return self;
}

+ (MXResponseData *)responseData {
    return [[MXResponseData alloc] init];
}

+ (id)buildResponseData:(MXActivityPackage *)activityPackage {
    MXActivityKind activityKind;
    
    if (activityPackage == nil) {
        activityKind = MXActivityKindUnknown;
    } else {
        activityKind = activityPackage.activityKind;
    }

    MXResponseData *responseData = nil;

    switch (activityKind) {
        case MXActivityKindSessionStart:
            responseData = [[MXSessionStartResponseData alloc] init];
            break;
        case MXActivityKindCustomEvent:
            responseData = [[MXCustomEventResponseData alloc] init];
            break;
        case MXActivityKindSessionStop:
            responseData = [[MXSessionStopResponseData alloc] init];
            break;
        default:
            responseData = [[MXResponseData alloc] init];
            break;
    }

    responseData.activityKind = activityKind;

    return responseData;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"message:%@ success:%d willRetry:%d attribution:%@ trackingState:%d, json:%@",
            self.message, self.success, self.willRetry, self.attribution, self.trackingState, self.jsonResponse];
}

#pragma mark - NSCopying

- (id)copyWithZone:(NSZone *)zone {
    MXResponseData* copy = [[[self class] allocWithZone:zone] init];

    if (copy) {
        copy.message = [self.message copyWithZone:zone];
        copy.success = self.success;
        copy.willRetry = self.willRetry;
        copy.trackingState = self.trackingState;
        copy.jsonResponse = [self.jsonResponse copyWithZone:zone];
        copy.attribution = [self.attribution copyWithZone:zone];
        copy.attributes = [self.attributes copyWithZone:zone];
    }

    return copy;
}

@end

@implementation MXSessionStartResponseData

- (id)initWithActivityPackage:(MXActivityPackage *)activityPackage {
    self = [super init];

    if (self == nil) {
        return nil;
    }

    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    MXSessionStartResponseData* copy = [super copyWithZone:zone];
    return copy;
}

@end


@implementation MXCustomEventResponseData
@end

@implementation MXSessionStopResponseData
@end

