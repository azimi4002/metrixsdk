//
//  MXUtil.h
//  Metrix
//

#import <Foundation/Foundation.h>

#import "MXEvent.h"
#import "MXConfig.h"
#import "MXActivityKind.h"
#import "MXResponseData.h"
#import "MXActivityPackage.h"
#import "MXBackoffStrategy.h"

typedef void (^selfInjectedBlock)(id);
typedef void (^isInactiveInjected)(BOOL);

static NSString * const BASE_PATH_INIT                 = @"/init";
static NSString * const BASE_PATH_EVENTS               = @"/events";

@interface MXUtil : NSObject

+ (void)teardown;

+ (id)readObject:(NSString *)fileName
      objectName:(NSString *)objectName
           class:(Class)classToRead;

+ (void)excludeFromBackup:(NSString *)filename;

+ (void)launchDeepLinkMain:(NSURL *)deepLinkUrl;

+ (void)launchInMainThread:(dispatch_block_t)block;

+ (BOOL)isMainThread;

+ (BOOL)isInactive;

+ (void)launchInMainThreadWithInactive:(isInactiveInjected)isInactiveblock;

+ (void)updateUrlSessionConfiguration:(MXConfig *)config;

+ (void)writeObject:(id)object
           fileName:(NSString *)fileName
         objectName:(NSString *)objectName;

+ (void)launchInMainThread:(NSObject *)receiver
                  selector:(SEL)selector
                withObject:(id)object;

+ (void)launchInQueue:(dispatch_queue_t)queue
           selfInject:(id)selfInject
                block:(selfInjectedBlock)block;

+ (void)sendGetRequest:(NSURL *)baseUrl
              basePath:(NSString *)basePath
    prefixErrorMessage:(NSString *)prefixErrorMessage
       activityPackage:(MXActivityPackage *)activityPackage
   responseDataHandler:(void (^)(MXResponseData *responseData))responseDataHandler;

+ (void)sendPostRequest:(NSURL *)baseUrl
              queueSize:(NSUInteger)queueSize
     prefixErrorMessage:(NSString *)prefixErrorMessage
     suffixErrorMessage:(NSString *)suffixErrorMessage
        activityPackage:(MXActivityPackage *)activityPackage
    responseDataHandler:(void (^)(MXResponseData *responseData))responseDataHandler;

+ (NSString *)idfa;

+ (NSString *)clientSdk;

+ (long)getUpdateTimestamp;

+ (NSDate *)getUpdateTime;

+ (long)getInstallTimestamp;

+ (NSString *)getInstallTime;

+ (NSDate *)getInstallDate;

+ (NSString *)formatDate:(NSDate *)value;

+ (NSString *)formatSeconds1970:(double)value;

+ (NSString *)secondsNumberFormat:(double)seconds;

+ (NSString *)queryString:(NSDictionary *)parameters;

+ (NSString *)convertDeviceToken:(NSData *)deviceToken;

+ (BOOL)isNull:(id)value;

+ (BOOL)isNotNull:(id)value;

+ (BOOL)deleteFileWithName:(NSString *)filename;

+ (BOOL)checkAttributionDetails:(NSDictionary *)attributionDetails;

+ (BOOL)isValidParameter:(NSString *)attribute
           attributeType:(NSString *)attributeType
           parameterName:(NSString *)parameterName;

+ (NSDictionary *)convertDictionaryValues:(NSDictionary *)dictionary;

+ (NSDictionary *)buildJsonDict:(NSData *)jsonData
                   exceptionPtr:(NSException **)exceptionPtr
                       errorPtr:(NSError **)error;

+ (NSDictionary *)mergeParameters:(NSDictionary *)target
                           source:(NSDictionary *)source
                    parameterName:(NSString *)parameterName;

+ (NSURL *)convertUniversalLink:(NSURL *)url scheme:(NSString *)scheme;

+ (NSTimeInterval)waitingTime:(NSInteger)retries
              backoffStrategy:(MXBackoffStrategy *)backoffStrategy;

+ (NSNumber *)readReachabilityFlags;

+ (BOOL)isDeeplinkValid:(NSURL *)url;

+ (NSString *)sdkVersion;

#if !TARGET_OS_TV
+ (NSString *)readMCC;

+ (NSString *)readMNC;

+ (NSString *)readCurrentRadioAccessTechnology;
#endif

@end
