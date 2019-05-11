//
//  MXPackageBuilder.h
//  Metrix SDK
//

#import "MXEvent.h"
#import "MXConfig.h"
#import "MXDeviceInfo.h"
#import "MXActivityState.h"
#import "MXActivityPackage.h"
#import "MXSessionParameters.h"
#import <Foundation/Foundation.h>

@interface MXPackageBuilder : NSObject

//@property (nonatomic, copy) MXAttribution *attribution;

- (id)initWithDeviceInfo:(MXDeviceInfo *)deviceInfo
           activityState:(MXActivityState *)activityState
                  config:(MXConfig *)metrixConfig
               createdAt:(double)createdAt;

- (id)initWithDeviceInfo:(MXDeviceInfo *)deviceInfo
           activityState:(MXActivityState *)activityState
                  config:(MXConfig *)metrixConfig
       sessionParameters:(MXSessionParameters *)sessionParameters
               createdAt:(double)createdAt;

- (MXActivityPackage *)buildSessionStartPackage:(BOOL)isInDelay;

- (MXActivityPackage *)buildSessionStopPackage;

- (MXActivityPackage *)buildCustomEventPackage:(MXCustomEvent *)event
                                isInDelay:(BOOL)isInDelay;

+ (void)parameters:(NSMutableDictionary *)parameters
     setDictionary:(NSDictionary *)dictionary
            forKey:(NSString *)key;

+ (void)parameters:(NSMutableDictionary *)parameters
         setString:(NSString *)value
            forKey:(NSString *)key;

@end
