//
//  MXRequestHandler.h
//  Metrix
//

#import <Foundation/Foundation.h>
#import "MXPackageHandler.h"

@protocol MXRequestHandler

- (id)initWithPackageHandler:(id<MXPackageHandler>)packageHandler
          andActivityHandler:(id<MXActivityHandler>)activityHandler;

- (void)sendPackage:(MXActivityPackage *)activityPackage
          queueSize:(NSUInteger)queueSize;

- (void)teardown;

@end

@interface MXRequestHandler : NSObject <MXRequestHandler>

+ (id<MXRequestHandler>)handlerWithPackageHandler:(id<MXPackageHandler>)packageHandler
                                andActivityHandler:(id<MXActivityHandler>)activityHandler;

@end
