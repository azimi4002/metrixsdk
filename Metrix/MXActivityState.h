//
//  MXActivityState.h
//  Metrix
//

#import <Foundation/Foundation.h>

@interface MXActivityState : NSObject <NSCoding, NSCopying>

// Persistent data
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL askingAttribution;

@property (nonatomic, copy) NSString *uuid;
@property (nonatomic, copy) NSString *deviceToken;
@property (nonatomic, assign) BOOL updatePackages;

@property (nonatomic, strong) NSDictionary *attributionDetails;

// Global counters
@property (nonatomic, assign) int eventCount;
@property (nonatomic, assign) int sessionCount;

// Session attributes
@property (nonatomic, assign) int subsessionCount;

@property (nonatomic, assign) double timeSpent;
@property (nonatomic, assign) double lastActivity;      // Entire time in seconds since 1970
@property (nonatomic, assign) double sessionLength;     // Entire duration in seconds

// Not persisted, only injected
@property (nonatomic, assign) BOOL isPersisted;
@property (nonatomic, assign) double lastInterval;

@property (nonatomic, copy) NSString *sessionId;
@property (nonatomic, copy) NSString *userId;
@property (nonatomic, strong) NSDictionary *attributes; //set by "/init" response
@property (nonatomic, strong) NSMutableArray *screenFlows;
@property (nonatomic, assign) BOOL isSessionActive;

- (void)refreshSessionId;

- (void)resetSessionAttributes:(double)now;

+ (void)saveAppToken:(NSString *)appTokenToSave;

- (void)addScreen:(NSString *)screen;
- (NSMutableArray *)getCompleteScreenFlow;
@end
