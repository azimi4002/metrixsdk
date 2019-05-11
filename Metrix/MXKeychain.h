//
//  MXKeychain.h
//  Metrix
//

#import <Foundation/Foundation.h>

@interface MXKeychain : NSObject

+ (NSString *)valueForKeychainKeyV1:(NSString *)key service:(NSString *)service;
+ (NSString *)valueForKeychainKeyV2:(NSString *)key service:(NSString *)service;
+ (BOOL)setValue:(NSString *)value forKeychainKey:(NSString *)key inService:(NSString *)service;

@end
