//
//  MXAttributionHandler.h
//  metrix
//

#import <Foundation/Foundation.h>
#import "MXActivityHandler.h"
#import "MXActivityPackage.h"

@protocol MXAttributionHandler

- (id)initWithActivityHandler:(id<MXActivityHandler>) activityHandler
                startsSending:(BOOL)startsSending;

- (void)checkSessionResponse:(MXSessionStartResponseData *)sessionResponseData;

- (void)pauseSending;

- (void)resumeSending;

- (void)teardown;

@end

@interface MXAttributionHandler : NSObject <MXAttributionHandler>

+ (id<MXAttributionHandler>)handlerWithActivityHandler:(id<MXActivityHandler>)activityHandler
                                          startsSending:(BOOL)startsSending;

@end
