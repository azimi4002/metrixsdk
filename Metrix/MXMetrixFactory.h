//
//  MXMetrixFactory.h
//  Metrix
//
#import <Foundation/Foundation.h>

#import "MXActivityHandler.h"
#import "MXPackageHandler.h"
#import "MXRequestHandler.h"
#import "MXLogger.h"
#import "MXAttributionHandler.h"
#import "MXActivityPackage.h"
#import "MXBackoffStrategy.h"
#import "MXSdkClickHandler.h"

@interface MXMetrixFactory : NSObject

+ (id<MXPackageHandler>)packageHandlerForActivityHandler:(id<MXActivityHandler>)activityHandler
                                            startsSending:(BOOL)startsSending;
+ (id<MXRequestHandler>)requestHandlerForPackageHandler:(id<MXPackageHandler>)packageHandler
                                      andActivityHandler:(id<MXActivityHandler>)activityHandler;
+ (id<MXActivityHandler>)activityHandlerWithConfig:(MXConfig *)metrixConfig
                     savedPreLaunch:(MXSavedPreLaunch *)savedPreLaunch;

+ (id<MXLogger>)logger;
+ (double)sessionInterval;
+ (double)subsessionInterval;
+ (NSTimeInterval)timerInterval;
+ (NSTimeInterval)timerStart;
+ (MXBackoffStrategy *)packageHandlerBackoffStrategy;

+ (id<MXAttributionHandler>)attributionHandlerForActivityHandler:(id<MXActivityHandler>)activityHandler
                                                    startsSending:(BOOL)startsSending;
+ (BOOL)testing;
+ (NSTimeInterval)maxDelayStart;
+ (NSString *)baseUrl;
+ (BOOL)iAdFrameworkEnabled;

+ (void)setPackageHandler:(id<MXPackageHandler>)packageHandler;
+ (void)setRequestHandler:(id<MXRequestHandler>)requestHandler;
+ (void)setActivityHandler:(id<MXActivityHandler>)activityHandler;
+ (void)setLogger:(id<MXLogger>)logger;
+ (void)setSessionInterval:(double)sessionInterval;
+ (void)setSubsessionInterval:(double)subsessionInterval;
+ (void)setTimerInterval:(NSTimeInterval)timerInterval;
+ (void)setTimerStart:(NSTimeInterval)timerStart;
+ (void)setAttributionHandler:(id<MXAttributionHandler>)attributionHandler;
+ (void)setPackageHandlerBackoffStrategy:(MXBackoffStrategy *)backoffStrategy;
+ (void)setTesting:(BOOL)testing;
+ (void)setiAdFrameworkEnabled:(BOOL)iAdFrameworkEnabled;
+ (void)setMaxDelayStart:(NSTimeInterval)maxDelayStart;
+ (void)setBaseUrl:(NSString *)baseUrl;

+ (void)teardown:(BOOL)deleteState;
@end
