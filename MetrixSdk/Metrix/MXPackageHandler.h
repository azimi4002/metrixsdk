//
//  MXPackageHandler.h
//  Metrix
//
#import <Foundation/Foundation.h>

#import "MXActivityPackage.h"
#import "MXPackageHandler.h"
#import "MXActivityHandler.h"
#import "MXResponseData.h"
#import "MXSessionParameters.h"

@protocol MXPackageHandler

- (id)initWithActivityHandler:(id<MXActivityHandler>)activityHandler
                startsSending:(BOOL)startsSending;

- (void)addPackage:(MXActivityPackage *)package;
- (void)sendFirstPackage;
- (void)sendNextPackage:(MXResponseData *)responseData;
- (void)closeFirstPackage:(MXResponseData *)responseData
          activityPackage:(MXActivityPackage *)activityPackage;
- (void)pauseSending;
- (void)resumeSending;
- (void)updatePackages:(MXSessionParameters *)sessionParameters;
- (void)flush;
- (NSString *)getBasePath;

- (void)teardown;
+ (void)deleteState;
@end

@interface MXPackageHandler : NSObject <MXPackageHandler>

+ (id<MXPackageHandler>)handlerWithActivityHandler:(id<MXActivityHandler>)activityHandler
                                      startsSending:(BOOL)startsSending;

@end
