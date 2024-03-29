//
//  MXActivityPackage.h
//  Metrix
//

#import "MXActivityKind.h"

@interface MXActivityPackage : NSObject <NSCoding>

// Data

@property (nonatomic, copy) NSString *path;

@property (nonatomic, copy) NSString *clientSdk;

@property (nonatomic, assign) NSInteger retries;

@property (nonatomic, strong) NSMutableDictionary *parameters;

@property (nonatomic, strong) NSDictionary *partnerParameters;

@property (nonatomic, strong) NSDictionary *callbackParameters;

// Logs

@property (nonatomic, copy) NSString *suffix;

@property (nonatomic, assign) MXActivityKind activityKind;

- (NSString *)extendedString;

- (NSString *)successMessage;

- (NSString *)failureMessage;

- (NSInteger)getRetries;

- (NSInteger)increaseRetries;

@end
