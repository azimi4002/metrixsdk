//
//  MXResponseData.h
//  metrix
//

#import <Foundation/Foundation.h>

#import "MXAttribution.h"
#import "MXEventSuccess.h"
#import "MXEventFailure.h"
#import "MXSessionSuccess.h"
#import "MXSessionFailure.h"
#import "MXActivityPackage.h"

typedef NS_ENUM(int, MXTrackingState) {
    MXTrackingStateOptedOut = 1
};

@interface MXResponseData : NSObject <NSCopying>

@property(nonatomic, assign) MXActivityKind activityKind;

@property(nonatomic, copy) NSString *message;

@property(nonatomic, assign) BOOL success;

@property(nonatomic, assign) BOOL willRetry;

@property(nonatomic, assign) MXTrackingState trackingState;

@property(nonatomic, strong) NSDictionary *jsonResponse;

@property(nonatomic, copy) MXAttribution *attribution;

@property(nonatomic, copy) NSString *userId;

- (id)init;

+ (MXResponseData *)responseData;

+ (id)buildResponseData:(MXActivityPackage *)activityPackage;

@end

@interface MXSessionStartResponseData : MXResponseData
@end

@interface MXSessionStopResponseData : MXResponseData
@end

@interface MXCustomEventResponseData : MXResponseData
@end
