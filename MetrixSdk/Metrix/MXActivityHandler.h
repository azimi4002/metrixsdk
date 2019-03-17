//
//  MXActivityHandler.h
//  Metrix
//

#import "Metrix.h"
#import "MXResponseData.h"
#import "MXActivityState.h"
#import "MXDeviceInfo.h"
#import "MXSessionParameters.h"

@interface MXInternalState : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL offline;
@property (nonatomic, assign) BOOL background;
@property (nonatomic, assign) BOOL delayStart;
@property (nonatomic, assign) BOOL updatePackages;
@property (nonatomic, assign) BOOL firstLaunch;
@property (nonatomic, assign) BOOL sessionResponseProcessed;

- (id)init;

- (BOOL)isEnabled;
- (BOOL)isDisabled;
- (BOOL)isOffline;
- (BOOL)isOnline;
- (BOOL)isInBackground;
- (BOOL)isInForeground;
- (BOOL)isInDelayedStart;
- (BOOL)isNotInDelayedStart;
- (BOOL)itHasToUpdatePackages;
- (BOOL)isFirstLaunch;
- (BOOL)hasSessionResponseNotBeenProcessed;

@end

@interface MXSavedPreLaunch : NSObject

@property (nonatomic, strong) NSMutableArray *preLaunchActionsArray;
@property (nonatomic, copy) NSNumber *enabled;
@property (nonatomic, assign) BOOL offline;
@property (nonatomic, copy) NSString *basePath;

- (id)init;

@end

@protocol MXActivityHandler <NSObject>

@property (nonatomic, copy) MXAttribution *attribution;
- (NSString *)mxid;

- (id)initWithConfig:(MXConfig *)metrixConfig
      savedPreLaunch:(MXSavedPreLaunch *)savedPreLaunch;

- (void)applicationDidBecomeActive;
- (void)applicationWillResignActive;

- (void)trackCustomEvent:(MXCustomEvent *)event;
- (void)trackScreen:(NSString *)screenName;

- (void)finishedTracking:(MXResponseData *)responseData;
- (void)launchCustomEventResponseTasks:(MXCustomEventResponseData *)eventResponseData;
- (void)launchSessionStartResponseTasks:(MXSessionStartResponseData *)sessionResponseData;
- (void)setEnabled:(BOOL)enabled;
- (BOOL)isEnabled;

- (void)setOfflineMode:(BOOL)offline;
- (void)sendFirstPackages;

- (NSString *)getBasePath;

- (MXDeviceInfo *)deviceInfo;
- (MXActivityState *)activityState;
- (MXConfig *)metrixConfig;
- (MXSessionParameters *)sessionParameters;

- (void)teardown;
+ (void)deleteState;
@end

@interface MXActivityHandler : NSObject <MXActivityHandler>

+ (id<MXActivityHandler>)handlerWithConfig:(MXConfig *)metrixConfig
                             savedPreLaunch:(MXSavedPreLaunch *)savedPreLaunch;

@end
