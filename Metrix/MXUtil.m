//
//  MXUtil.m
//  Metrix SDK
//

#include <math.h>
#include <stdlib.h>
#include <sys/xattr.h>
#import <objc/message.h>

#import "MXUtil.h"
#import "MXLogger.h"
#import "MXReachability.h"
#import "MXLocationHandler.h"
#import "MXResponseData.h"
#import "MXMetrixFactory.h"
#import "UIDevice+MXAdditions.h"
#import "NSString+MXAdditions.h"
#import "MXUserDefaults.h"

#if !TARGET_OS_TV
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#endif

static const double kRequestTimeout = 60;   // 60 seconds
static const long INSTALL_UPDATE_DIFF_THRESHOLD = 30000;   // millis

static NSString *userAgent = nil;
static MXReachability *reachability = nil;
static MXLocationHandler *locationHandler = nil;
static NSRegularExpression *universalLinkRegex = nil;
static NSNumberFormatter *secondsNumberFormatter = nil;
static NSRegularExpression *optionalRedirectRegex = nil;
static NSRegularExpression *shortUniversalLinkRegex = nil;
static NSRegularExpression *excludedDeeplinkRegex = nil;
static NSURLSessionConfiguration *urlSessionConfiguration = nil;

#if !TARGET_OS_TV
static CTCarrier *carrier = nil;
static CTTelephonyNetworkInfo *networkInfo = nil;
#endif

static NSString * const kClientSdk                  = @"ios1.0.1";
static NSString * const kDeeplinkParam              = @"deep_link=";
static NSString * const kSchemeDelimiter            = @"://";
static NSString * const kDefaultScheme              = @"MetrixUniversalScheme";
static NSString * const kUniversalLinkPattern       = @"https://[^.]*\\.ulink\\.metrix\\.ir/ulink/?(.*)";
static NSString * const kOptionalRedirectPattern    = @"metrix_redirect=[^&#]*";
static NSString * const kShortUniversalLinkPattern  = @"http[s]?://[a-z0-9]{4}\\.metrix\\.st/?(.*)";
static NSString * const kExcludedDeeplinksPattern   = @"^(fb|vk)[0-9]{5,}[^:]*://authorize.*access_token=.*";
//static NSString * const kDateFormat                 = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'Z";
static NSString * const kDateFormat                 = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";

@implementation MXUtil

+ (void)initialize {
    if (self != [MXUtil class]) {
        return;
    }

    [self initializeUniversalLinkRegex];
    [self initializeSecondsNumberFormatter];
    [self initializeShortUniversalLinkRegex];
    [self initializeOptionalRedirectRegex];
    [self initializeExcludedDeeplinkRegex];
    [self initializeUrlSessionConfiguration];
    [self initializeReachability];
    [self initializeLocation];
#if !TARGET_OS_TV
    [self initializeNetworkInfoAndCarrier];
#endif
}

+ (void)teardown {
    reachability = nil;
    universalLinkRegex = nil;
    secondsNumberFormatter = nil;
    optionalRedirectRegex = nil;
    shortUniversalLinkRegex = nil;
    urlSessionConfiguration = nil;
#if !TARGET_OS_TV
    networkInfo = nil;
    carrier = nil;
#endif

}

+ (void)initializeUniversalLinkRegex {
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kUniversalLinkPattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if ([MXUtil isNotNull:error]) {
        [MXMetrixFactory.logger error:@"Universal link regex rule error (%@)", [error description]];
        return;
    }
    universalLinkRegex = regex;
}

+ (void)initializeShortUniversalLinkRegex {
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kShortUniversalLinkPattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if ([MXUtil isNotNull:error]) {
        [MXMetrixFactory.logger error:@"Short Universal link regex rule error (%@)", [error description]];
        return;
    }
    shortUniversalLinkRegex = regex;
}

+ (void)initializeOptionalRedirectRegex {
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kOptionalRedirectPattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if ([MXUtil isNotNull:error]) {
        [MXMetrixFactory.logger error:@"Optional redirect regex rule error (%@)", [error description]];
        return;
    }
    optionalRedirectRegex = regex;
}

+ (void)initializeExcludedDeeplinkRegex {
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:kExcludedDeeplinksPattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if ([MXUtil isNotNull:error]) {
        [MXMetrixFactory.logger error:@"Excluded deep link regex rule error (%@)", [error description]];
        return;
    }
    excludedDeeplinkRegex = regex;
}

+ (void)initializeSecondsNumberFormatter {
    secondsNumberFormatter = [[NSNumberFormatter alloc] init];
    [secondsNumberFormatter setPositiveFormat:@"0.0"];
}

+ (NSURLSessionConfiguration *)getUrlSessionConfiguration {
    if (urlSessionConfiguration != nil) {
        return urlSessionConfiguration;
    } else {
        return [NSURLSessionConfiguration defaultSessionConfiguration];
    }
}

+ (void)initializeUrlSessionConfiguration {
    urlSessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
}

#if !TARGET_OS_TV
+ (void)initializeNetworkInfoAndCarrier {
    networkInfo = [[CTTelephonyNetworkInfo alloc] init];
    carrier = [networkInfo subscriberCellularProvider];
}
#endif

+ (void)initializeReachability {
    reachability = [MXReachability reachabilityForInternetConnection];
    [reachability startNotifier];
}

+ (void)initializeLocation {
    locationHandler = [[MXLocationHandler alloc] init];
    [locationHandler startUpdatingLocationIfPossible];
}

+ (NSDictionary *)locationDictionary{
    return [MXUserDefaults getLocationDictionary];
}

+ (void)updateUrlSessionConfiguration:(MXConfig *)config {
    userAgent = config.userAgent;
}

+ (NSString *)clientSdk {
    return kClientSdk;
}

+ (NSDateFormatter *)getDateFormatter {
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    if ([NSCalendar instancesRespondToSelector:@selector(calendarWithIdentifier:)]) {
        // http://stackoverflow.com/a/3339787
        NSString *calendarIdentifier;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
        if (&NSCalendarIdentifierGregorian != NULL) {
#pragma clang diagnostic pop
            calendarIdentifier = NSCalendarIdentifierGregorian;
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            calendarIdentifier = NSGregorianCalendar;
#pragma clang diagnostic pop
        }
        dateFormatter.calendar = [NSCalendar calendarWithIdentifier:calendarIdentifier];
    }
    dateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    [dateFormatter setDateFormat:kDateFormat];

    return dateFormatter;
}

// Inspired by https://gist.github.com/kevinbarrett/2002382
+ (void)excludeFromBackup:(NSString *)path {
    NSURL *url = [NSURL fileURLWithPath:path];
    const char* filePath = [[url path] fileSystemRepresentation];
    const char* attrName = "com.apple.MobileBackup";
    id<MXLogger> logger = MXMetrixFactory.logger;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunreachable-code"
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
    if (&NSURLIsExcludedFromBackupKey == nil) {
        u_int8_t attrValue = 1;
        int result = setxattr(filePath, attrName, &attrValue, sizeof(attrValue), 0, 0);
        if (result != 0) {
            [logger debug:@"Failed to exclude '%@' from backup", url.lastPathComponent];
        }
    } else { // iOS 5.0 and higher
        // First try and remove the extended attribute if it is present
        ssize_t result = getxattr(filePath, attrName, NULL, sizeof(u_int8_t), 0, 0);
        if (result != -1) {
            // The attribute exists, we need to remove it
            int removeResult = removexattr(filePath, attrName, 0);
            if (removeResult == 0) {
                [logger debug:@"Removed extended attribute on file '%@'", url];
            }
        }

        // Set the new key
        NSError *error = nil;
        BOOL success = [url setResourceValue:[NSNumber numberWithBool:YES]
                                      forKey:NSURLIsExcludedFromBackupKey
                                       error:&error];
        if (!success || error != nil) {
            [logger debug:@"Failed to exclude '%@' from backup (%@)", url.lastPathComponent, error.localizedDescription];
        }
    }
#pragma clang diagnostic pop
}

+ (NSString *)formatSeconds1970:(double)value {
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:value];
    return [self formatDate:date];
}

+ (NSString *)formatDate:(NSDate *)value {
    NSDateFormatter *dateFormatter = [MXUtil getDateFormatter];
    if (dateFormatter == nil) {
        return nil;
    }
    return [dateFormatter stringFromDate:value];
}

+ (void)saveJsonResponse:(NSData *)jsonData responseData:(MXResponseData *)responseData {
    NSError *error = nil;
    NSException *exception = nil;
    NSDictionary *jsonDict = [MXUtil buildJsonDict:jsonData exceptionPtr:&exception errorPtr:&error];

    if (exception != nil) {
        NSString *message = [NSString stringWithFormat:@"Failed to parse json response. (%@)", exception.description];
        [MXMetrixFactory.logger error:message];
        responseData.message = message;
        return;
    }
    if (error != nil) {
        NSString *message = [NSString stringWithFormat:@"Failed to parse json response. (%@)", error.localizedDescription];
        [MXMetrixFactory.logger error:message];
        responseData.message = message;
        return;
    }


    responseData.jsonResponse = jsonDict;
}

+ (NSDictionary *)buildJsonDict:(NSData *)jsonData
                   exceptionPtr:(NSException **)exceptionPtr
                       errorPtr:(NSError **)error {
    if (jsonData == nil) {
        return nil;
    }

    NSDictionary *jsonDict = nil;
    @try {
        jsonDict = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    } @catch (NSException *ex) {
        *exceptionPtr = ex;
        return nil;
    }
    return jsonDict;
}

+ (id)readObject:(NSString *)fileName
      objectName:(NSString *)objectName
           class:(Class)classToRead {
    // Try to read from Application Support directory first.
    NSString *documentsFilePath = [MXUtil getFilePathInDocumentsDir:fileName];
    NSString *appSupportFilePath = [MXUtil getFilePathInAppSupportDir:fileName];

    @try {
        id appSupportObject = [NSKeyedUnarchiver unarchiveObjectWithFile:appSupportFilePath];
        if ([appSupportObject isKindOfClass:classToRead]) {
            // Successfully read object from Application Support folder, return it.
            if ([appSupportObject isKindOfClass:[NSArray class]]) {
                [[MXMetrixFactory logger] debug:@"Package handler read %d packages", [appSupportObject count]];
            } else {
                [[MXMetrixFactory logger] debug:@"Read %@: %@", objectName, appSupportObject];
            }
            // Just in case check if old file exists in Documents folder and if yes, remove it.
            [MXUtil deleteFileInPath:documentsFilePath];
            return appSupportObject;
        } else if (appSupportObject == nil) {
            // [[MXMetrixFactory logger] verbose:@"%@ file not found", appSupportFilePath];
            [[MXMetrixFactory logger] verbose:@"%@ file not found in \"Application Support/Metrix\" folder", fileName];
        } else {
            // [[MXMetrixFactory logger] error:@"Failed to read %@ file", appSupportFilePath];
            [[MXMetrixFactory logger] error:@"Failed to read %@ file from \"Application Support/Metrix\" folder", fileName];
        }
    } @catch (NSException *ex) {
        // [[MXMetrixFactory logger] error:@"Failed to read %@ file  (%@)", appSupportFilePath, ex];
        [[MXMetrixFactory logger] error:@"Failed to read %@ file from \"Application Support/Metrix\" folder (%@)", fileName, ex];
    }

    // If in here, for some reason, reading of file from Application Support folder failed.
    // Let's check the Documents folder.
    @try {
        id documentsObject = [NSKeyedUnarchiver unarchiveObjectWithFile:documentsFilePath];
        if (documentsObject != nil) {
            // Successfully read object from Documents folder.
            if ([documentsObject isKindOfClass:[NSArray class]]) {
                [[MXMetrixFactory logger] debug:@"Package handler read %d packages", [documentsObject count]];
            } else {
                [[MXMetrixFactory logger] debug:@"Read %@: %@", objectName, documentsObject];
            }
            // Do the file migration.
            [[MXMetrixFactory logger] verbose:@"Migrating %@ file from Documents to \"Application Support/Metrix\" folder", fileName];
            [MXUtil migrateFileFromPath:documentsFilePath toPath:appSupportFilePath];
            return documentsObject;
        } else if (documentsObject == nil) {
            // [[MXMetrixFactory logger] verbose:@"%@ file not found", documentsFilePath];
            [[MXMetrixFactory logger] verbose:@"%@ file not found in Documents folder", fileName];
        } else {
            // [[MXMetrixFactory logger] error:@"Failed to read %@ file", documentsFilePath];
            [[MXMetrixFactory logger] error:@"Failed to read %@ file from Documents folder", fileName];
        }
    } @catch (NSException *ex) {
        // [[MXMetrixFactory logger] error:@"Failed to read %@ file (%@)", documentsFilePath, ex];
        [[MXMetrixFactory logger] error:@"Failed to read %@ file from Documents folder (%@)", fileName, ex];
    }
    return nil;
}

+ (void)writeObject:(id)object
           fileName:(NSString *)fileName
         objectName:(NSString *)objectName {
    NSString *filePath = [MXUtil getFilePathInAppSupportDir:fileName];
    BOOL result = (filePath != nil) && [NSKeyedArchiver archiveRootObject:object toFile:filePath];
    if (result == YES) {
        [MXUtil excludeFromBackup:filePath];
        if ([object isKindOfClass:[NSArray class]]) {
            [[MXMetrixFactory logger] debug:@"Package handler wrote %d packages", [object count]];
        } else {
            [[MXMetrixFactory logger] debug:@"Wrote %@: %@", objectName, object];
        }
    } else {
        [[MXMetrixFactory logger] error:@"Failed to write %@ file", objectName];
    }
}

+ (BOOL)migrateFileFromPath:(NSString *)oldPath toPath:(NSString *)newPath {
    NSError *errorCopy;
    [[NSFileManager defaultManager] copyItemAtPath:oldPath toPath:newPath error:&errorCopy];
    if (errorCopy != nil) {
        [[MXMetrixFactory logger] error:@"Error while copying from %@ to %@", oldPath, newPath];
        [[MXMetrixFactory logger] error:[errorCopy description]];
        return NO;
    }
    // Migration successful.
    return YES;
}

+ (NSString *)getFilePathInDocumentsDir:(NSString *)fileName {
    // Documents directory exists by default inside app bundle, no need to check for it's presence.
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDir = [paths objectAtIndex:0];
    NSString *filePath = [documentsDir stringByAppendingPathComponent:fileName];
    return filePath;
}

+ (NSString *)getFilePathInAppSupportDir:(NSString *)fileName {
    // Application Support directory doesn't exist by default inside app bundle.
    // All Metrix files are going to be stored in Metrix sub-directory inside Application Support directory.
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupportDir = [paths firstObject];
    NSString *metrixDirName = @"Metrix";
    if (![MXUtil checkForDirectoryPresenceInPath:appSupportDir forFolder:[appSupportDir lastPathComponent]]) {
        return nil;
    }
    NSString *metrixDir = [appSupportDir stringByAppendingPathComponent:[NSString stringWithFormat:@"/%@", metrixDirName]];
    if (![MXUtil checkForDirectoryPresenceInPath:metrixDir forFolder:metrixDirName]) {
        return nil;
    }
    NSString *filePath = [metrixDir stringByAppendingPathComponent:fileName];
    return filePath;
}

+ (BOOL)checkForDirectoryPresenceInPath:(NSString *)path forFolder:(NSString *)folderName {
    // Check for presence of directory first.
    // If it doesn't exist, make one.
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [[MXMetrixFactory logger] debug:@"%@ directory not present and will be created", folderName];
        NSError *error;
        [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:NO attributes:nil error:&error];
        if (error != nil) {
            [[MXMetrixFactory logger] error:@"Error while creating % directory", path];
            [[MXMetrixFactory logger] error:[error description]];
            return NO;
        }
    }
    return YES;
}

+ (NSString *)queryString:(NSDictionary *)parameters {
    return [MXUtil queryString:parameters queueSize:0];
}

+ (NSString *)queryString:(NSDictionary *)parameters
                queueSize:(NSUInteger)queueSize {
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *key in parameters) {
        NSString *value = [parameters objectForKey:key];
        NSString *escapedValue = [value mxUrlEncode];
        NSString *escapedKey = [key mxUrlEncode];
        NSString *pair = [NSString stringWithFormat:@"%@=%@", escapedKey, escapedValue];
        [pairs addObject:pair];
    }

    double now = [NSDate.date timeIntervalSince1970];
    NSString *dateString = [MXUtil formatSeconds1970:now];
    NSString *escapedDate = [dateString mxUrlEncode];
    NSString *sentAtPair = [NSString stringWithFormat:@"%@=%@", @"sent_at", escapedDate];
    [pairs addObject:sentAtPair];

    if (queueSize > 0) {
        unsigned long queueSizeNative = (unsigned long)queueSize;
        NSString *queueSizeString = [NSString stringWithFormat:@"%lu", queueSizeNative];
        NSString *escapedQueueSize = [queueSizeString mxUrlEncode];
        NSString *queueSizePair = [NSString stringWithFormat:@"%@=%@", @"queue_size", escapedQueueSize];
        [pairs addObject:queueSizePair];
    }

    NSString *queryString = [pairs componentsJoinedByString:@"&"];
    return queryString;
}

+ (BOOL)isNull:(id)value {
    return value == nil || value == (id)[NSNull null];
}

+ (BOOL)isNotNull:(id)value {
    return value != nil && value != (id)[NSNull null];
}

+ (NSString *)formatErrorMessage:(NSString *)prefixErrorMessage
              systemErrorMessage:(NSString *)systemErrorMessage
              suffixErrorMessage:(NSString *)suffixErrorMessage {
    NSString *errorMessage = [NSString stringWithFormat:@"%@ (%@)", prefixErrorMessage, systemErrorMessage];
    if (suffixErrorMessage == nil) {
        return errorMessage;
    } else {
        return [errorMessage stringByAppendingFormat:@" %@", suffixErrorMessage];
    }
}

+ (void)sendGetRequest:(NSURL *)baseUrl
              basePath:(NSString *)basePath
    prefixErrorMessage:(NSString *)prefixErrorMessage
       activityPackage:(MXActivityPackage *)activityPackage
   responseDataHandler:(void (^)(MXResponseData *responseData))responseDataHandler {
    NSMutableDictionary *parametersCopy = [[NSMutableDictionary alloc] initWithCapacity:[activityPackage.parameters count]];
    [parametersCopy addEntriesFromDictionary:activityPackage.parameters];

    NSString *appSecret = [MXUtil extractAppSecret:parametersCopy];
    NSString *secretId = [MXUtil extractSecretId:parametersCopy];
    [MXUtil extractEventCallbackId:parametersCopy];

    NSMutableURLRequest *request = [MXUtil requestForGetPackage:activityPackage.path
                                                       clientSdk:activityPackage.clientSdk
                                                      parameters:parametersCopy
                                                         baseUrl:baseUrl
                                                        basePath:basePath];
    [MXUtil sendRequest:request
      prefixErrorMessage:prefixErrorMessage
         activityPackage:activityPackage
                secretId:secretId
               appSecret:appSecret
     responseDataHandler:responseDataHandler];
}

+ (void)sendRequest:(NSMutableURLRequest *)request
 prefixErrorMessage:(NSString *)prefixErrorMessage
    activityPackage:(MXActivityPackage *)activityPackage
           secretId:(NSString *)secretId
          appSecret:(NSString *)appSecret
responseDataHandler:(void (^)(MXResponseData *responseData))responseDataHandler {
    [MXUtil sendRequest:request
      prefixErrorMessage:prefixErrorMessage
      suffixErrorMessage:nil
                secretId:secretId
               appSecret:appSecret
         activityPackage:activityPackage
     responseDataHandler:responseDataHandler];
}

+ (void)sendPostRequest:(NSURL *)baseUrl
              queueSize:(NSUInteger)queueSize
     prefixErrorMessage:(NSString *)prefixErrorMessage
     suffixErrorMessage:(NSString *)suffixErrorMessage
        activityPackage:(MXActivityPackage *)activityPackage
    responseDataHandler:(void (^)(MXResponseData *responseData))responseDataHandler {
    NSMutableDictionary *parametersCopy = [[NSMutableDictionary alloc] initWithCapacity:[activityPackage.parameters count]];
    [parametersCopy addEntriesFromDictionary:activityPackage.parameters];

//    NSString *appSecret = [MXUtil extractAppSecret:parametersCopy];
//    NSString *secretId = [MXUtil extractSecretId:parametersCopy];
//    [MXUtil extractEventCallbackId:parametersCopy];

    NSMutableURLRequest *request = [MXUtil requestForPostPackage:activityPackage.path
                                                        clientSdk:activityPackage.clientSdk
                                                       parameters:parametersCopy
                                                          baseUrl:baseUrl queueSize:queueSize];
    [MXUtil sendRequest:request
      prefixErrorMessage:prefixErrorMessage
      suffixErrorMessage:suffixErrorMessage
                secretId:nil
               appSecret:nil
         activityPackage:activityPackage
     responseDataHandler:responseDataHandler];
}

+ (void)sendRequest:(NSMutableURLRequest *)request
 prefixErrorMessage:(NSString *)prefixErrorMessage
 suffixErrorMessage:(NSString *)suffixErrorMessage
           secretId:(NSString *)secretId
          appSecret:(NSString *)appSecret
    activityPackage:(MXActivityPackage *)activityPackage
responseDataHandler:(void (^)(MXResponseData *responseData))responseDataHandler {
//    NSString *authHeader = [MXUtil buildAuthorizationHeader:appSecret
//                                                    secretId:secretId
//                                             activityPackage:activityPackage];
//    if (authHeader != nil) {
//        [request setValue:authHeader forHTTPHeaderField:@"Authorization"];
//    }
    if (userAgent != nil) {
        [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }

    Class NSURLSessionClass = NSClassFromString(@"NSURLSession");
    if (NSURLSessionClass != nil) {
        [MXUtil sendNSURLSessionRequest:request
                      prefixErrorMessage:prefixErrorMessage
                      suffixErrorMessage:suffixErrorMessage
                         activityPackage:activityPackage
                     responseDataHandler:responseDataHandler];
    } else {
        [MXUtil sendNSURLConnectionRequest:request
                         prefixErrorMessage:prefixErrorMessage
                         suffixErrorMessage:suffixErrorMessage
                            activityPackage:activityPackage
                        responseDataHandler:responseDataHandler];
    }
}

+ (NSString *)extractAppSecret:(NSMutableDictionary *)parameters {
    NSString *appSecret = [parameters objectForKey:@"app_secret"];
    if (appSecret == nil) {
        return nil;
    }
    [parameters removeObjectForKey:@"app_secret"];
    return appSecret;
}

+ (NSString *)extractSecretId:(NSMutableDictionary *)parameters {
    NSString *appSecret = [parameters objectForKey:@"secret_id"];
    if (appSecret == nil) {
        return nil;
    }
    [parameters removeObjectForKey:@"secret_id"];
    return appSecret;
}

+ (void)extractEventCallbackId:(NSMutableDictionary *)parameters {
    NSString *eventCallbackId = [parameters objectForKey:@"event_callback_id"];
    if (eventCallbackId == nil) {
        return;
    }
    [parameters removeObjectForKey:@"event_callback_id"];
}

+ (NSMutableURLRequest *)requestForGetPackage:(NSString *)path
                                    clientSdk:(NSString *)clientSdk
                                   parameters:(NSDictionary *)parameters
                                      baseUrl:(NSURL *)baseUrl
                                     basePath:(NSString *)basePath {
    NSString *queryStringParameters = [MXUtil queryString:parameters];
    NSString *relativePath;
    if (basePath != nil) {
        relativePath = [NSString stringWithFormat:@"%@%@?%@", basePath, path, queryStringParameters];
    } else {
        relativePath = [NSString stringWithFormat:@"%@?%@", path, queryStringParameters];
    }

    NSURL *url = [NSURL URLWithString:relativePath relativeToURL:baseUrl];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = kRequestTimeout;
    request.HTTPMethod = @"GET";
    [request setValue:clientSdk forHTTPHeaderField:@"Client-Sdk"];
    return request;
}

+ (NSMutableURLRequest *)requestForPostPackage:(NSString *)path
                                     clientSdk:(NSString *)clientSdk
                                    parameters:(NSDictionary *)parameters
                                       baseUrl:(NSURL *)baseUrl
                                     queueSize:(NSUInteger)queueSize {
    NSURL *url = [baseUrl URLByAppendingPathComponent:path];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = kRequestTimeout;
    request.HTTPMethod = @"POST";
//    if(parameters[@"app_id"]){
//        [request setValue:parameters[@"app_id"] forHTTPHeaderField:@"X-Application-Id"];
//    }
//    if(parameters[@"app_info"] && parameters[@"app_info"][@"id"]){
//        [request setValue:parameters[@"app_info"][@"id"] forHTTPHeaderField:@"X-Application-Id"];
//    }
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSString *u = parameters[@"user_id"] ? parameters[@"user_id"] : @"nil";
    NSLog(@"++++++++++ %@ %@ %@", path, parameters[@"event_type"], u);
//    [request setValue:clientSdk forHTTPHeaderField:@"Client-Sdk"];

//    NSString *bodyString = [MXUtil queryString:parameters queueSize:queueSize];
//    NSData *body = [NSData dataWithBytes:bodyString.UTF8String length:bodyString.length];
    NSError *error;
    NSData *body;
    if([path isEqualToString:BASE_PATH_INIT]){
        body = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:&error];
    }else{
        body = [NSJSONSerialization dataWithJSONObject:@[parameters] options:0 error:&error];
    }
    [request setHTTPBody:body];
    return request;
}

+ (NSString *)buildAuthorizationHeader:(NSString *)appSecret
                              secretId:(NSString *)secretId
                       activityPackage:(MXActivityPackage *)activityPackage {
    if (appSecret == nil) {
        return nil;
    }

    NSMutableDictionary *parameters = activityPackage.parameters;
    NSString *activityKindS = [MXActivityKindUtil activityKindToString:activityPackage.activityKind];
    NSDictionary *signatureParameters = [MXUtil buildSignatureParameters:parameters
                                                                appSecret:appSecret
                                                            activityKindS:activityKindS];
    NSMutableString *fields = [[NSMutableString alloc] initWithCapacity:5];
    NSMutableString *clearSignature = [[NSMutableString alloc] initWithCapacity:5];

    // signature part of header
    for (NSDictionary *key in signatureParameters) {
        [fields appendFormat:@"%@ ", key];
        NSString *value = [signatureParameters objectForKey:key];
        [clearSignature appendString:value];
    }

    NSString *secretIdHeader = [NSString stringWithFormat:@"secret_id=\"%@\"", secretId];
    // algorithm part of header
    NSString *algorithm = @"sha256";
    NSString *signature = [clearSignature mxSha256];
    NSString *signatureHeader = [NSString stringWithFormat:@"signature=\"%@\"", signature];
    NSString *algorithmHeader = [NSString stringWithFormat:@"algorithm=\"%@\"", algorithm];
    // fields part of header
    // Remove last empty space.
    if (fields.length > 0) {
        [fields deleteCharactersInRange:NSMakeRange(fields.length - 1, 1)];
    }

    NSString *fieldsHeader = [NSString stringWithFormat:@"headers=\"%@\"", fields];
    // putting it all together
    NSString *authorizationHeader = [NSString stringWithFormat:@"Signature %@,%@,%@,%@",
                                     secretIdHeader,
                                     signatureHeader,
                                     algorithmHeader,
                                     fieldsHeader];
    [MXMetrixFactory.logger debug:@"authorizationHeader %@", authorizationHeader];
    return authorizationHeader;
}

+ (NSDictionary *)buildSignatureParameters:(NSMutableDictionary *)parameters
                                 appSecret:(NSString *)appSecret
                             activityKindS:(NSString *)activityKindS {
    NSString *activityKindName = @"activity_kind";
    NSString *activityKindValue = activityKindS;
    NSString *createdAtName = @"created_at";
    NSString *createdAtValue = [parameters objectForKey:createdAtName];
    NSString *deviceIdentifierName = [MXUtil getValidIdentifier:parameters];
    NSString *deviceIdentifierValue = [parameters objectForKey:deviceIdentifierName];
    NSMutableDictionary *signatureParameters = [[NSMutableDictionary alloc] initWithCapacity:4];

    [MXUtil checkAndAddEntry:signatureParameters key:@"app_secret" value:appSecret];
    [MXUtil checkAndAddEntry:signatureParameters key:createdAtName value:createdAtValue];
    [MXUtil checkAndAddEntry:signatureParameters key:activityKindName value:activityKindValue];
    [MXUtil checkAndAddEntry:signatureParameters key:deviceIdentifierName value:deviceIdentifierValue];
    return signatureParameters;
}

+ (void)checkAndAddEntry:(NSMutableDictionary *)parameters
                     key:(NSString *)key
                   value:(NSString *)value {
    if (key == nil) {
        return;
    }

    if (value == nil) {
        return;
    }

    [parameters setObject:value forKey:key];
}

+ (NSString *)getValidIdentifier:(NSMutableDictionary *)parameters {
    NSString *idfaName = @"idfa";
    NSString *persistentUUIDName = @"persistent_ios_uuid";
    NSString *uuidName = @"ios_uuid";

    if ([parameters objectForKey:idfaName] != nil) {
        return idfaName;
    }
    if ([parameters objectForKey:persistentUUIDName] != nil) {
        return persistentUUIDName;
    }
    if ([parameters objectForKey:uuidName] != nil) {
        return uuidName;
    }
    return nil;
}

+ (void)sendNSURLSessionRequest:(NSMutableURLRequest *)request
             prefixErrorMessage:(NSString *)prefixErrorMessage
             suffixErrorMessage:(NSString *)suffixErrorMessage
                activityPackage:(MXActivityPackage *)activityPackage
            responseDataHandler:(void (^)(MXResponseData *responseData))responseDataHandler {
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[MXUtil getUrlSessionConfiguration]];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:
                                  ^(NSData *data, NSURLResponse *response, NSError *error) {
                                      MXResponseData *responseData = [MXUtil completionHandler:data
                                                                                        response:(NSHTTPURLResponse *)response
                                                                                           error:error
                                                                              prefixErrorMessage:prefixErrorMessage
                                                                              suffixErrorMessage:suffixErrorMessage
                                                                                 activityPackage:activityPackage];
                                      responseDataHandler(responseData);
                                  }];
    [task resume];
    [session finishTasksAndInvalidate];
}

+ (void)sendNSURLConnectionRequest:(NSMutableURLRequest *)request
                prefixErrorMessage:(NSString *)prefixErrorMessage
                suffixErrorMessage:(NSString *)suffixErrorMessage
                   activityPackage:(MXActivityPackage *)activityPackage
               responseDataHandler:(void (^)(MXResponseData *responseData))responseDataHandler {
    NSError *responseError = nil;
    NSHTTPURLResponse *urlResponse = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                         returningResponse:&urlResponse
                                                     error:&responseError];
#pragma clang diagnostic pop
    MXResponseData *responseData = [MXUtil completionHandler:data
                                                      response:(NSHTTPURLResponse *)urlResponse
                                                         error:responseError
                                            prefixErrorMessage:prefixErrorMessage
                                            suffixErrorMessage:suffixErrorMessage
                                               activityPackage:activityPackage];
    responseDataHandler(responseData);
}

+ (MXResponseData *)completionHandler:(NSData *)data
                              response:(NSHTTPURLResponse *)urlResponse
                                 error:(NSError *)responseError
                    prefixErrorMessage:(NSString *)prefixErrorMessage
                    suffixErrorMessage:(NSString *)suffixErrorMessage
                       activityPackage:(MXActivityPackage *)activityPackage {
    MXResponseData *responseData = [MXResponseData buildResponseData:activityPackage];
    // Connection error
    if (responseError != nil) {
        NSString *errorMessage = [MXUtil formatErrorMessage:prefixErrorMessage
                                          systemErrorMessage:responseError.localizedDescription
                                          suffixErrorMessage:suffixErrorMessage];
        [MXMetrixFactory.logger error:errorMessage];
        responseData.message = errorMessage;
        return responseData;
    }
    if ([MXUtil isNull:data]) {
        NSString *errorMessage = [MXUtil formatErrorMessage:prefixErrorMessage
                                          systemErrorMessage:@"empty error"
                                          suffixErrorMessage:suffixErrorMessage];
        [MXMetrixFactory.logger error:errorMessage];
        responseData.message = errorMessage;
        return responseData;
    }

    NSString *responseString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] mxTrim];
    NSInteger statusCode = urlResponse.statusCode;
    [MXMetrixFactory.logger verbose:@"Response: %@", responseString];

    if (statusCode == 429) {
        [MXMetrixFactory.logger error:@"Too frequent requests to the endpoint (429)"];
        return responseData;
    }
    [MXUtil saveJsonResponse:data responseData:responseData];
    if ([MXUtil isNull:responseData.jsonResponse]) {
        if(![activityPackage.path isEqualToString:BASE_PATH_INIT]){
            responseData.jsonResponse = @{};
        }
        return responseData;
    }

    NSString *messageResponse = [responseData.jsonResponse objectForKey:@"message"];
    responseData.message = messageResponse;
//    responseData.timeStamp = [responseData.jsonResponse objectForKey:@"timestamp"];
//    responseData.mxid = [responseData.jsonResponse objectForKey:@"mxid"];
    responseData.userId = [responseData.jsonResponse objectForKey:@"user_id"];
    responseData.attributes = [responseData.jsonResponse objectForKey:@"attributes"];
    responseData.success = [[responseData.jsonResponse objectForKey:@"success"] boolValue];

//    NSString *trackingState = [responseData.jsonResponse objectForKey:@"tracking_state"];
//    if (trackingState != nil) {
//        if ([trackingState isEqualToString:@"opted_out"]) {
//            responseData.trackingState = MXTrackingStateOptedOut;
//        }
//    }
//    if (messageResponse == nil) {
//        messageResponse = @"No message found";
//    }
    if (statusCode == 200 && responseData.success) {
        [MXMetrixFactory.logger info:@"%@", messageResponse];
//        responseData.success = YES;
    } else {
        [MXMetrixFactory.logger error:@"%@", messageResponse];
    }
    return responseData;
}

// Convert all values to strings, if value is dictionary -> recursive call
+ (NSDictionary *)convertDictionaryValues:(NSDictionary *)dictionary {
    NSMutableDictionary *convertedDictionary = [[NSMutableDictionary alloc] initWithCapacity:dictionary.count];
    for (NSString *key in dictionary) {
        id value = [dictionary objectForKey:key];
        if ([value isKindOfClass:[NSDictionary class]]) {
            // Dictionary value, recursive call
            NSDictionary *dictionaryValue = [MXUtil convertDictionaryValues:(NSDictionary *)value];
            [convertedDictionary setObject:dictionaryValue forKey:key];
        } else if ([value isKindOfClass:[NSDate class]]) {
            // Format date to our custom format
            NSString *dateStingValue = [MXUtil formatDate:value];
            if (dateStingValue != nil) {
                [convertedDictionary setObject:dateStingValue forKey:key];
            }
        } else {
            // Convert all other objects directly to string
            NSString *stringValue = [NSString stringWithFormat:@"%@", value];
            [convertedDictionary setObject:stringValue forKey:key];
        }
    }
    return convertedDictionary;
}

+ (NSString *)idfa {
    return [[UIDevice currentDevice] mxIdForAdvertisers];
}

+ (long)getUpdateTimestampNormalized {
    long updateTime = (long) ([[MXUtil getUpdateTime] timeIntervalSince1970] *1000);
    if([MXUtil getInstallTimestamp] + INSTALL_UPDATE_DIFF_THRESHOLD > updateTime){
        return [MXUtil getInstallTimestamp];
    }
    return updateTime;
}

+ (long)getUpdateTimestamp {
    return (long) ([[MXUtil getUpdateTime] timeIntervalSince1970] *1000);
}

+ (NSDate *)getUpdateTime {
    NSDate *updateTime = nil;
    id<MXLogger> logger = MXMetrixFactory.logger;
    @try {
        __autoreleasing NSError *error;
        NSString *infoPlistPath = [[NSBundle mainBundle] pathForResource:@"Info" ofType:@"plist"];
        updateTime = [[[NSFileManager defaultManager] attributesOfItemAtPath:infoPlistPath error:&error] objectForKey:NSFileModificationDate];
//        NSLog(@"UpdateTime  path***** %@", infoPlistPath);
//        NSLog(@"UpdateTime  path***** %@", [[NSBundle mainBundle] bundleIdentifier]);
//        NSLog(@"UpdateTime***** %@", [[[NSFileManager defaultManager] attributesOfItemAtPath:infoPlistPath error:&error] objectForKey:NSFileCreationDate]);
//        NSLog(@"UpdateTime***** %@", [[[NSFileManager defaultManager] attributesOfItemAtPath:infoPlistPath error:&error] objectForKey:NSFileModificationDate]);
    } @catch (NSException *exception) {
        [logger error:@"Error while trying to check update date. Exception: %@", exception];
    }
    return updateTime;
}

+ (NSString *)getInstallTime {
    return [MXUtil formatDate:[MXUtil getInstallDate]];
}

+ (long)getInstallTimestamp {
    return (long) ([[MXUtil getInstallDate] timeIntervalSince1970] *1000);
}

+ (NSDate *)getInstallDate {
    id<MXLogger> logger = MXMetrixFactory.logger;
    NSDate *installTime = nil;
    NSString *pathToCheck = nil;
    NSSearchPathDirectory folderToCheck = NSDocumentDirectory;
#if TARGET_OS_TV
    folderToCheck = NSCachesDirectory;
#endif
    @try {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(folderToCheck, NSUserDomainMask, YES);
        if (paths.count > 0) {
            pathToCheck = [paths objectAtIndex:0];
        } else {
            // There's no NSDocumentDirectory (or NSCachesDirectory).
            // Check app's bundle creation date instead.
            pathToCheck = [[NSBundle mainBundle] bundlePath];
        }
//        NSLog(@"install path::: %@", pathToCheck);
//        NSLog(@"install modif date ::: %@", [[NSFileManager defaultManager] attributesOfItemAtPath:pathToCheck error:nil][NSFileModificationDate]);
//        NSLog(@"install creation date ::: %@", [[NSFileManager defaultManager] attributesOfItemAtPath:pathToCheck error:nil][NSFileModificationDate]);
        installTime = [[NSFileManager defaultManager] attributesOfItemAtPath:pathToCheck error:nil][NSFileCreationDate];
    } @catch (NSException *exception) {
        [logger error:@"Error while trying to check install date. Exception: %@", exception];
    }
    return installTime;
}

+ (NSURL *)convertUniversalLink:(NSURL *)url scheme:(NSString *)scheme {
    id<MXLogger> logger = MXMetrixFactory.logger;

    if ([MXUtil isNull:url]) {
        [logger error:@"Received universal link is nil"];
        return nil;
    }
    if ([MXUtil isNull:scheme] || [scheme length] == 0) {
        [logger warn:@"Non-empty scheme required, using the scheme \"metrixUniversalScheme\""];
        scheme = kDefaultScheme;
    }
    NSString *urlString = [url absoluteString];
    if ([MXUtil isNull:urlString]) {
        [logger error:@"Parsed universal link is nil"];
        return nil;
    }
    if (universalLinkRegex == nil) {
        [logger error:@"Universal link regex not correctly configured"];
        return nil;
    }
    if (shortUniversalLinkRegex == nil) {
        [logger error:@"Short Universal link regex not correctly configured"];
        return nil;
    }

    NSArray<NSTextCheckingResult *> *matches = [universalLinkRegex matchesInString:urlString options:0 range:NSMakeRange(0, [urlString length])];
    if ([matches count] == 0) {
        matches = [shortUniversalLinkRegex matchesInString:urlString options:0 range:NSMakeRange(0, [urlString length])];
        if ([matches count] == 0) {
            [logger error:@"Url doesn't match as universal link or short version"];
            return nil;
        }
    }
    if ([matches count] > 1) {
        [logger error:@"Url match as universal link multiple times"];
        return nil;
    }

    NSTextCheckingResult *match = matches[0];
    if ([match numberOfRanges] != 2) {
        [logger error:@"Wrong number of ranges matched"];
        return nil;
    }

    NSString *tailSubString = [urlString substringWithRange:[match rangeAtIndex:1]];
    NSString *finalTailSubString = [MXUtil removeOptionalRedirect:tailSubString];
    NSString *extractedUrlString = [NSString stringWithFormat:@"%@://%@", scheme, finalTailSubString];
    [logger info:@"Converted deeplink from universal link %@", extractedUrlString];
    NSURL *extractedUrl = [NSURL URLWithString:extractedUrlString];
    if ([MXUtil isNull:extractedUrl]) {
        [logger error:@"Unable to parse converted deeplink from universal link %@", extractedUrlString];
        return nil;
    }
    return extractedUrl;
}

+ (NSString *)removeOptionalRedirect:(NSString *)tailSubString {
    id<MXLogger> logger = MXMetrixFactory.logger;

    if (optionalRedirectRegex == nil) {
        [MXMetrixFactory.logger error:@"Remove Optional Redirect regex not correctly configured"];
        return tailSubString;
    }
    NSArray<NSTextCheckingResult *> *optionalRedirectmatches = [optionalRedirectRegex matchesInString:tailSubString
                                                                                              options:0
                                                                                                range:NSMakeRange(0, [tailSubString length])];
    if ([optionalRedirectmatches count] == 0) {
        [logger debug:@"Universal link does not contain option metrix_redirect parameter"];
        return tailSubString;
    }
    if ([optionalRedirectmatches count] > 1) {
        [logger error:@"Universal link contains multiple option metrix_redirect parameters"];
        return tailSubString;
    }

    NSTextCheckingResult *redirectMatch = optionalRedirectmatches[0];
    NSRange redirectRange = [redirectMatch rangeAtIndex:0];
    NSString *beforeRedirect = [tailSubString substringToIndex:redirectRange.location];
    NSString *afterRedirect = [tailSubString substringFromIndex:(redirectRange.location + redirectRange.length)];
    if (beforeRedirect.length > 0 && afterRedirect.length > 0) {
        NSString *lastCharacterBeforeRedirect = [beforeRedirect substringFromIndex:beforeRedirect.length - 1];
        NSString *firstCharacterAfterRedirect = [afterRedirect substringToIndex:1];
        if ([@"&" isEqualToString:lastCharacterBeforeRedirect] &&
            [@"&" isEqualToString:firstCharacterAfterRedirect]) {
            beforeRedirect = [beforeRedirect substringToIndex:beforeRedirect.length - 1];
        }
        if ([@"&" isEqualToString:lastCharacterBeforeRedirect] &&
            [@"#" isEqualToString:firstCharacterAfterRedirect]) {
            beforeRedirect = [beforeRedirect substringToIndex:beforeRedirect.length - 1];
        }
        if ([@"?" isEqualToString:lastCharacterBeforeRedirect] &&
            [@"#" isEqualToString:firstCharacterAfterRedirect]) {
            beforeRedirect = [beforeRedirect substringToIndex:beforeRedirect.length - 1];
        }
        if ([@"?" isEqualToString:lastCharacterBeforeRedirect] &&
            [@"&" isEqualToString:firstCharacterAfterRedirect]) {
            afterRedirect = [afterRedirect substringFromIndex:1];
        }
    }
    
    NSString *removedRedirect = [NSString stringWithFormat:@"%@%@", beforeRedirect, afterRedirect];
    return removedRedirect;
}

+ (NSString *)secondsNumberFormat:(double)seconds {
    // Normalize negative zero
    if (seconds < 0) {
        seconds = seconds * -1;
    }
    if (secondsNumberFormatter == nil) {
        return nil;
    }
    return [secondsNumberFormatter stringFromNumber:[NSNumber numberWithDouble:seconds]];
}

+ (double)randomInRange:(double)minRange maxRange:(double)maxRange {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        srand48(arc4random());
    });
    double random = drand48();
    double range = maxRange - minRange;
    double scaled = random  * range;
    double shifted = scaled + minRange;
    return shifted;
}

+ (NSTimeInterval)waitingTime:(NSInteger)retries
              backoffStrategy:(MXBackoffStrategy *)backoffStrategy {
    if (retries < backoffStrategy.minRetries) {
        return 0;
    }

    // Start with base 0
    NSInteger base = retries - backoffStrategy.minRetries;
    // Get the exponential Time from the base: 1, 2, 4, 8, 16, ... * times the multiplier
    NSTimeInterval exponentialTime = pow(2.0, base) * backoffStrategy.secondMultiplier;
    // Limit the maximum allowed time to wait
    NSTimeInterval ceilingTime = MIN(exponentialTime, backoffStrategy.maxWait);
    // Add 1 to allow maximum value
    double randomRange = [MXUtil randomInRange:backoffStrategy.minRange maxRange:backoffStrategy.maxRange];
    // Apply jitter factor
    NSTimeInterval waitingTime =  ceilingTime * randomRange;
    return waitingTime;
}

+ (void)launchInMainThread:(NSObject *)receiver
                  selector:(SEL)selector
                withObject:(id)object {
    if (MXMetrixFactory.testing) {
        [MXMetrixFactory.logger debug:@"Launching in the background for testing"];
        [receiver performSelectorInBackground:selector withObject:object];
    } else {
        [receiver performSelectorOnMainThread:selector
                                   withObject:object
                                waitUntilDone:NO];  // non-blocking
    }
}

+ (void)launchInMainThread:(dispatch_block_t)block {
    if (MXMetrixFactory.testing) {
        [MXMetrixFactory.logger debug:@"Launching in the background for testing"];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), block);
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

+ (BOOL)isMainThread {
    return [[NSThread currentThread] isMainThread];
}

+ (BOOL)isInactive {
#if METRIX_IM
    // Assume iMessage extension app can't be started from background.
    return NO;
#else
    return [[UIApplication sharedApplication] applicationState] != UIApplicationStateActive;
#endif
}

+ (void)launchInMainThreadWithInactive:(isInactiveInjected)isInactiveblock {
    dispatch_block_t block = ^void(void) {
        __block BOOL isInactive = [MXUtil isInactive];
        isInactiveblock(isInactive);
    };
    if ([MXUtil isMainThread]) {
        block();
        return;
    }
    if (MXMetrixFactory.testing) {
        [MXMetrixFactory.logger debug:@"Launching in the background for testing"];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), block);
    } else {
        dispatch_async(dispatch_get_main_queue(), block);
    }
}

+ (BOOL)isValidParameter:(NSString *)attribute
           attributeType:(NSString *)attributeType
           parameterName:(NSString *)parameterName {
    if ([MXUtil isNull:attribute]) {
        [MXMetrixFactory.logger error:@"%@ parameter %@ is missing", parameterName, attributeType];
        return NO;
    }
    if ([attribute isEqualToString:@""]) {
        [MXMetrixFactory.logger error:@"%@ parameter %@ is empty", parameterName, attributeType];
        return NO;
    }
    return YES;
}

+ (NSDictionary *)mergeParameters:(NSDictionary *)target
                           source:(NSDictionary *)source
                    parameterName:(NSString *)parameterName {
    if (target == nil) {
        return source;
    }
    if (source == nil) {
        return target;
    }

    NSMutableDictionary *mergedParameters = [NSMutableDictionary dictionaryWithDictionary:target];
    [source enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *obj, BOOL *stop) {
        NSString *oldValue = [mergedParameters objectForKey:key];
        if (oldValue != nil) {
            [MXMetrixFactory.logger warn:@"Key %@ with value %@ from %@ parameter was replaced by value %@",
             key, oldValue, parameterName, obj];
        }
        [mergedParameters setObject:obj forKey:key];
    }];
    return (NSDictionary *)mergedParameters;
}

+ (void)launchInQueue:(dispatch_queue_t)queue
           selfInject:(id)selfInject
                block:(selfInjectedBlock)block {
    if (queue == nil) {
        return;
    }
    __weak __typeof__(selfInject) weakSelf = selfInject;
    dispatch_async(queue, ^{
        __typeof__(selfInject) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        block(strongSelf);
    });
}

+ (BOOL)deleteFileWithName:(NSString *)fileName {
    NSString *documentsFilePath = [MXUtil getFilePathInDocumentsDir:fileName];
    NSString *appSupportFilePath = [MXUtil getFilePathInAppSupportDir:fileName];
    BOOL deletedDocumentsFilePath = [MXUtil deleteFileInPath:documentsFilePath];
    BOOL deletedAppSupportFilePath = [MXUtil deleteFileInPath:appSupportFilePath];
    return deletedDocumentsFilePath || deletedAppSupportFilePath;
}

+ (BOOL)deleteFileInPath:(NSString *)filePath {
    NSError *error;
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        // [[MXMetrixFactory logger] verbose:@"File does not exist at path %@", filePath];
        return YES;
    }

    BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:filePath error:&error];
    if (!deleted) {
        [[MXMetrixFactory logger] verbose:@"Unable to delete file at path %@", filePath];
    }
    if (error) {
        [[MXMetrixFactory logger] error:@"Error while deleting file at path %@", filePath];
    }
    return deleted;
}

+ (void)launchDeepLinkMain:(NSURL *)deepLinkUrl {
#if METRIX_IM
    // No deep linking in iMessage extension apps.
    return;
#else
    UIApplication *sharedUIApplication = [UIApplication sharedApplication];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    SEL openUrlSelector = @selector(openURL:options:completionHandler:);
#pragma clang diagnostic pop
    if ([sharedUIApplication respondsToSelector:openUrlSelector]) {
        /*
         [sharedUIApplication openURL:deepLinkUrl options:@{} completionHandler:^(BOOL success) {
         if (!success) {
         [MXMetrixFactory.logger error:@"Unable to open deep link (%@)", deepLinkUrl];
         }
         }];
         */
        NSMethodSignature *methSig = [sharedUIApplication methodSignatureForSelector:openUrlSelector];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methSig];
        [invocation setSelector: openUrlSelector];
        [invocation setTarget: sharedUIApplication];
        NSDictionary *emptyDictionary = @{};
        void (^completion)(BOOL) = ^(BOOL success) {
            if (!success) {
                [MXMetrixFactory.logger error:@"Unable to open deep link (%@)", deepLinkUrl];
            }
        };
        [invocation setArgument:&deepLinkUrl atIndex: 2];
        [invocation setArgument:&emptyDictionary atIndex: 3];
        [invocation setArgument:&completion atIndex: 4];
        [invocation invoke];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        BOOL success = [sharedUIApplication openURL:deepLinkUrl];
#pragma clang diagnostic pop
        if (!success) {
            [MXMetrixFactory.logger error:@"Unable to open deep link (%@)", deepLinkUrl];
        }
    }
#endif
}

+ (NSString *)convertDeviceToken:(NSData *)deviceToken {
    if (deviceToken == nil) {
        return nil;;
    }

    NSString *deviceTokenString = [deviceToken.description stringByTrimmingCharactersInSet:
                                   [NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    if (deviceTokenString == nil) {
        return nil;;
    }

    deviceTokenString = [deviceTokenString stringByReplacingOccurrencesOfString:@" " withString:@""];
    return deviceTokenString;
}

+ (BOOL)checkAttributionDetails:(NSDictionary *)attributionDetails {
    if ([MXUtil isNull:attributionDetails]) {
        return NO;
    }

    NSDictionary *details = [attributionDetails objectForKey:@"Version3.1"];
    if ([MXUtil isNull:details]) {
        return YES;
    }

    // Common fields for both iAd3 and Apple Search Ads
    if (![MXUtil contains:details key:@"iad-org-name" value:@"OrgName"] ||
        ![MXUtil contains:details key:@"iad-campaign-id" value:@"1234567890"] ||
        ![MXUtil contains:details key:@"iad-campaign-name" value:@"CampaignName"] ||
        ![MXUtil contains:details key:@"iad-lineitem-id" value:@"1234567890"] ||
        ![MXUtil contains:details key:@"iad-lineitem-name" value:@"LineName"]) {
        [MXMetrixFactory.logger debug:@"iAd attribution details has dummy common fields for both iAd3 and Apple Search Ads"];
        return YES;
    }
    // Apple Search Ads fields
    if ([MXUtil contains:details key:@"iad-adgroup-id" value:@"1234567890"] &&
        [MXUtil contains:details key:@"iad-adgroup-name" value:@"AdgroupName"] &&
        [MXUtil contains:details key:@"iad-keyword" value:@"Keyword"]) {
        [MXMetrixFactory.logger debug:@"iAd attribution details has dummy Apple Search Ads fields"];
        return NO;
    }
    // iAd3 fields
    if ([MXUtil contains:details key:@"iad-adgroup-id" value:@"1234567890"] &&
        [MXUtil contains:details key:@"iad-creative-name" value:@"CreativeName"]) {
        [MXMetrixFactory.logger debug:@"iAd attribution details has dummy iAd3 fields"];
        return NO;
    }

    return YES;
}

+ (BOOL)contains:(NSDictionary *)dictionary
        key:(NSString *)key
        value:(NSString *)value {
    id readValue = [dictionary objectForKey:key];
    if ([MXUtil isNull:readValue]) {
        return NO;
    }
    return [value isEqualToString:[readValue description]];
}

+ (NSNumber *)readReachabilityFlags {
    if (reachability == nil) {
        return nil;
    }
    return [reachability currentReachabilityFlags];
}

+ (NSString *)readConnectionType{
    MXNetworkStatus status = [reachability currentReachabilityStatus];
    switch (status){
        case MXReachableViaWiFi:
            return @"wifi";
        case MXReachableViaWWAN:
            return @"mobileData";
        default:
            return @"offline";
    }
}


+ (BOOL)isDeeplinkValid:(NSURL *)url {
    if (url == nil) {
        return NO;
    }
    if ([[url absoluteString] length] == 0) {
        return NO;
    }
    if (excludedDeeplinkRegex == nil) {
        [MXMetrixFactory.logger error:@"Excluded deep link regex not correctly configured"];
        return NO;
    }

    NSString *urlString = [url absoluteString];
    NSArray<NSTextCheckingResult *> *matches = [excludedDeeplinkRegex matchesInString:urlString
                                                                              options:0
                                                                                range:NSMakeRange(0, [urlString length])];
    if ([matches count] > 0) {
        [MXMetrixFactory.logger debug:@"Deep link (%@) processing skipped", urlString];
        return NO;
    }

    return YES;
}

+ (NSString *)sdkVersion {
    return kClientSdk;
}

#if !TARGET_OS_TV
+ (NSString *)readMCC {
    if (carrier == nil) {
        return nil;
    }
    return [carrier mobileCountryCode];
}

+ (NSString *)readMNC {
    if (carrier == nil) {
        return nil;
    }
    return [carrier mobileNetworkCode];
}

+ (NSString *)readCurrentRadioAccessTechnology {
    if (networkInfo == nil) {
        return nil;
    }
    SEL radioTechSelector = NSSelectorFromString(@"currentRadioAccessTechnology");
    if (![networkInfo respondsToSelector:radioTechSelector]) {
        return nil;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id radioTech = [networkInfo performSelector:radioTechSelector];
#pragma clang diagnostic pop
    return radioTech;
}
#endif

@end
