//
//  MXActivityKind.m
//  Metrix
//

#import "MXActivityKind.h"

@implementation MXActivityKindUtil

#pragma mark - Public methods

+ (MXActivityKind)activityKindFromString:(NSString *)activityKindString {
    if ([@"session_start" isEqualToString:activityKindString]) {
        return MXActivityKindSessionStart;
    } else if ([@"session_stop" isEqualToString:activityKindString]) {
        return MXActivityKindSessionStop;
    } else if ([@"custom" isEqualToString:activityKindString]) {
        return MXActivityKindCustomEvent;
    } else {
        return MXActivityKindUnknown;
    }
}

+ (NSString *)activityKindToString:(MXActivityKind)activityKind {
    switch (activityKind) {
        case MXActivityKindSessionStart:
            return @"session_start";
        case MXActivityKindSessionStop:
            return @"session_stop";
        case MXActivityKindCustomEvent:
            return @"custom";
        default:
            return @"unknown";
    }
}

@end
