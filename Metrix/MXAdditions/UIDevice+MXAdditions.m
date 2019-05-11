//
//  UIDevice+MXAdditions.m
//  Metrix
//
//  Created by Christian Wellenbrock (@wellle) on 23rd July 2012.
//  Copyright © 2012-2018 Metrix GmbH. All rights reserved.
//

#import "UIDevice+MXAdditions.h"
#import "NSString+MXAdditions.h"

#import <sys/sysctl.h>

#if !METRIX_NO_IDFA
#import <AdSupport/ASIdentifierManager.h>
#endif

#if !METRIX_NO_IAD && !TARGET_OS_TV
#import <iAd/iAd.h>
#endif

#import "MXMetrixFactory.h"

@implementation UIDevice(MXAdditions)

- (BOOL)mxTrackingEnabled {
#if METRIX_NO_IDFA
    return NO;
#else
    // return [[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled];
    NSString *className = [NSString mxJoin:@"A", @"S", @"identifier", @"manager", nil];
    Class class = NSClassFromString(className);
    if (class == nil) {
        return NO;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSString *keyManager = [NSString mxJoin:@"shared", @"manager", nil];
    SEL selManager = NSSelectorFromString(keyManager);
    if (![class respondsToSelector:selManager]) {
        return NO;
    }
    id manager = [class performSelector:selManager];

    NSString *keyEnabled = [NSString mxJoin:@"is", @"advertising", @"tracking", @"enabled", nil];
    SEL selEnabled = NSSelectorFromString(keyEnabled);
    if (![manager respondsToSelector:selEnabled]) {
        return NO;
    }
    BOOL enabled = (BOOL)[manager performSelector:selEnabled];
    return enabled;
#pragma clang diagnostic pop
#endif
}

- (NSString *)mxIdForAdvertisers {
#if METRIX_NO_IDFA
    return @"";
#else
    // return [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
    NSString *className = [NSString mxJoin:@"A", @"S", @"identifier", @"manager", nil];
    Class class = NSClassFromString(className);
    if (class == nil) {
        return @"";
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

    NSString *keyManager = [NSString mxJoin:@"shared", @"manager", nil];
    SEL selManager = NSSelectorFromString(keyManager);
    if (![class respondsToSelector:selManager]) {
        return @"";
    }
    id manager = [class performSelector:selManager];

    NSString *keyIdentifier = [NSString mxJoin:@"advertising", @"identifier", nil];
    SEL selIdentifier = NSSelectorFromString(keyIdentifier);
    if (![manager respondsToSelector:selIdentifier]) {
        return @"";
    }
    id identifier = [manager performSelector:selIdentifier];

    NSString *keyString = [NSString mxJoin:@"UUID", @"string", nil];
    SEL selString = NSSelectorFromString(keyString);
    if (![identifier respondsToSelector:selString]) {
        return @"";
    }
    NSString *string = [identifier performSelector:selString];
    return string;

#pragma clang diagnostic pop
#endif
}

- (NSString *)mxFbAttributionId {
#if METRIX_NO_UIPASTEBOARD || TARGET_OS_TV
    return @"";
#else
    __block NSString *result;
    void(^resultRetrievalBlock)(void) = ^{
        result = [UIPasteboard pasteboardWithName:@"fb_app_attribution" create:NO].string;
        if (result == nil) {
            result = @"";
        }
    };
    [NSThread isMainThread] ? resultRetrievalBlock() : dispatch_sync(dispatch_get_main_queue(), resultRetrievalBlock);
    return result;
#endif
}

- (NSString *)mxDeviceType {
    NSString *type = [self.model stringByReplacingOccurrencesOfString:@" " withString:@""];
    return type;
}

- (NSString *)mxDeviceName {
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *name = malloc(size);
    sysctlbyname("hw.machine", name, &size, NULL, 0);
    NSString *machine = [NSString stringWithUTF8String:name];
    free(name);
    return machine;
}

- (NSString *)mxCreateUuid {
    CFUUIDRef newUniqueId = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef stringRef = CFUUIDCreateString(kCFAllocatorDefault, newUniqueId);
    NSString *uuidString = (__bridge_transfer NSString*)stringRef;
    NSString *lowerUuid = [uuidString lowercaseString];
    CFRelease(newUniqueId);
    return lowerUuid;
}

- (NSString *)mxVendorId {
    if ([UIDevice.currentDevice respondsToSelector:@selector(identifierForVendor)]) {
        return [UIDevice.currentDevice.identifierForVendor UUIDString];
    }
    return @"";
}

- (void)mxSetIad:(MXActivityHandler *)activityHandler
     triesV3Left:(int)triesV3Left {
    id<MXLogger> logger = [MXMetrixFactory logger];

#if METRIX_NO_IAD || TARGET_OS_TV
    [logger debug:@"METRIX_NO_IAD or TARGET_OS_TV set"];
    return;
#else
    [logger debug:@"METRIX_NO_IAD or TARGET_OS_TV not set"];

    // [[ADClient sharedClient] ...]
    Class ADClientClass = NSClassFromString(@"ADClient");
    if (ADClientClass == nil) {
        [logger warn:@"iAd framework not found in user's app (ADClientClass not found)"];
        return;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    SEL sharedClientSelector = NSSelectorFromString(@"sharedClient");
    if (![ADClientClass respondsToSelector:sharedClientSelector]) {
        [logger warn:@"iAd framework not found in user's app (sharedClient method not found)"];
        return;
    }
    id ADClientSharedClientInstance = [ADClientClass performSelector:sharedClientSelector];
    if (ADClientSharedClientInstance == nil) {
        [logger warn:@"iAd framework not found in user's app (ADClientSharedClientInstance is nil)"];
        return;
    }

    [logger debug:@"iAd framework successfully found in user's app"];
    [logger debug:@"iAd with %d tries to read v3", triesV3Left];

    // if no tries for iad v3 left, stop trying
    if (triesV3Left == 0) {
        [logger warn:@"Reached limit number of retry for iAd v3"];
        return;
    }

    BOOL isIadV3Avaliable = [self mxSetIadWithDetails:activityHandler
                         ADClientSharedClientInstance:ADClientSharedClientInstance
                                          retriesLeft:(triesV3Left - 1)];

    // if iad v3 not available
    if (!isIadV3Avaliable) {
        [logger warn:@"iAd v3 not available"];
        return;
    }
#pragma clang diagnostic pop
#endif
}

- (BOOL) mxSetIadWithDetails:(MXActivityHandler *)activityHandler
ADClientSharedClientInstance:(id)ADClientSharedClientInstance
                 retriesLeft:(int)retriesLeft {
    SEL iadDetailsSelector = NSSelectorFromString(@"requestAttributionDetailsWithBlock:");
    if (![ADClientSharedClientInstance respondsToSelector:iadDetailsSelector]) {
        return NO;
    }

//#pragma clang diagnostic push
//#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
//    [ADClientSharedClientInstance performSelector:iadDetailsSelector
//                                       withObject:^(NSDictionary *attributionDetails, NSError *error) {
//                                           [activityHandler setAttributionDetails:attributionDetails error:error retriesLeft:retriesLeft];
//                                       }];
//#pragma clang diagnostic pop

    return YES;
}

@end
