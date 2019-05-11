//
//  MXActivityState.m
//  Metrix
//

#import "MXKeychain.h"
#import "MXMetrixFactory.h"
#import "MXActivityState.h"
#import "UIDevice+MXAdditions.h"
#import "NSString+MXAdditions.h"

static NSString *appToken = nil;

@implementation MXActivityState{}

#pragma mark - Object lifecycle methods

- (id)init {
    self = [super init];
    
    if (self == nil) {
        return nil;
    }
    
    [self assignUuid:[UIDevice.currentDevice mxCreateUuid]];
    
    self.eventCount         = 0;
    self.sessionCount       = 0;
    self.subsessionCount    = -1;   // -1 means unknown
    self.sessionLength      = -1;
    self.timeSpent          = -1;
    self.lastActivity       = -1;
    self.lastInterval       = -1;
    self.enabled            = YES;
    self.askingAttribution  = NO;
    self.deviceToken        = nil;
    self.updatePackages  = NO;
    
    return self;
}

#pragma mark - Public methods

+ (void)saveAppToken:(NSString *)appTokenToSave {
    @synchronized (self) {
        appToken = appTokenToSave;
    }
}

- (void)resetSessionAttributes:(double)now {
    self.subsessionCount = 1;
    self.sessionLength   = 0;
    self.timeSpent       = 0;
    self.lastInterval    = -1;
    self.lastActivity    = now;
    self.isSessionActive = YES;
    self.screenFlows = nil;
}

- (void)addScreen:(NSString *)screen {
    // Create array.
    if (self.screenFlows == nil) {
        self.screenFlows = [NSMutableArray array];
    }
    // Add the new ID.
    [self.screenFlows addObject:screen];
}

- (NSMutableArray *)getCompleteScreenFlow {
    NSMutableArray *toReturn = [@[@"_start"] mutableCopy];
    if (self.screenFlows != nil) {
        [toReturn addObjectsFromArray:self.screenFlows];
    }
    [toReturn addObject:@"_end"];
    return toReturn;
}

- (void)refreshSessionId{
    self.sessionId = [[NSUUID UUID] UUIDString];
}

- (NSString *)sessionId {
    if(!_sessionId){
        self.sessionId = [[NSUUID UUID] UUIDString];
    }
    return _sessionId;
}


#pragma mark - Private & helper methods

- (void)assignUuid:(NSString *)uuid {
    // 1. Check if UUID is written to keychain in v2 way.
    // 1.1 If yes, take stored UUID and send it to v1 check.
    // 1.2 If not, take given UUID and send it to v1 check.
    // v1 check:
    // 2.1 If given UUID is found in v1 way, use it.
    // 2.2 If given UUID is not found in v1 way, write it in v1 way and use it.

    // First check if we have the key written with app's unique key name.
    NSString *uniqueKey = [self generateUniqueKey];
    NSString *persistedUuidUnique = [MXKeychain valueForKeychainKeyV2:uniqueKey service:@"deviceInfo"];

    if (persistedUuidUnique != nil) {
        // Check if value has UUID format.
        if ((bool)[[NSUUID alloc] initWithUUIDString:persistedUuidUnique]) {
            [[MXMetrixFactory logger] verbose:@"Value found and read from the keychain v2 way"];

            // If we read the key with v2 way, write it back in v1 way since in iOS 11, that's the only one that it works.
            [self assignUuidOldMethod:persistedUuidUnique];
        }
    }

    // At this point, UUID was not persisted in v2 way or if persisted, didn't have proper UUID format.
    // Try the v1 way with given UUID.
    [self assignUuidOldMethod:uuid];
}

- (void)assignUuidOldMethod:(NSString *)uuid {
    NSString *persistedUuid = [MXKeychain valueForKeychainKeyV1:@"metrix_persisted_uuid" service:@"deviceInfo"];

    // Check if value exists in keychain.
    if (persistedUuid != nil) {
        // Check if value has UUID format.
        if ((bool)[[NSUUID alloc] initWithUUIDString:persistedUuid]) {
            [[MXMetrixFactory logger] verbose:@"Value found and read from the keychain v1 way"];

            // Value written in keychain seems to have UUID format.
            self.uuid = persistedUuid;
            self.isPersisted = YES;

            return;
        }
    }

    // At this point, UUID was not persisted in v1 way or if persisted, didn't have proper UUID format.

    // Since we don't have anything in the keychain, we'll use the passed UUID value.
    // Try to save that value to the keychain in v1 way and flag if successfully written.
    self.uuid = uuid;
    self.isPersisted = [MXKeychain setValue:self.uuid forKeychainKey:@"metrix_persisted_uuid" inService:@"deviceInfo"];
}

- (NSString *)generateUniqueKey {
    if (appToken == nil) {
        return nil;
    }

    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];

    if (bundleIdentifier == nil) {
        return nil;
    }

    NSString *joinedKey = [NSString stringWithFormat:@"%@%@", bundleIdentifier, appToken];

    return [joinedKey mxSha1];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"ec:%d sc:%d ssc:%d ask:%d sl:%.1f ts:%.1f la:%.1f dt:%@",
            self.eventCount, self.sessionCount, self.subsessionCount, self.askingAttribution, self.sessionLength,
            self.timeSpent, self.lastActivity, self.deviceToken];
}

#pragma mark - NSCoding protocol methods

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super init];
    
    if (self == nil) {
        return nil;
    }
    
    self.eventCount         = [decoder decodeIntForKey:@"eventCount"];
    self.sessionCount       = [decoder decodeIntForKey:@"sessionCount"];
    self.subsessionCount    = [decoder decodeIntForKey:@"subsessionCount"];
    self.sessionLength      = [decoder decodeDoubleForKey:@"sessionLength"];
    self.timeSpent          = [decoder decodeDoubleForKey:@"timeSpent"];
    self.lastActivity       = [decoder decodeDoubleForKey:@"lastActivity"];

    // Default values for migrating devices
    if ([decoder containsValueForKey:@"uuid"]) {
        [self assignUuid:[decoder decodeObjectForKey:@"uuid"]];
    }
    
    if (self.uuid == nil) {
        [self assignUuid:[UIDevice.currentDevice mxCreateUuid]];
    }
    
    if ([decoder containsValueForKey:@"enabled"]) {
        self.enabled = [decoder decodeBoolForKey:@"enabled"];
    } else {
        self.enabled = YES;
    }

    if ([decoder containsValueForKey:@"askingAttribution"]) {
        self.askingAttribution = [decoder decodeBoolForKey:@"askingAttribution"];
    } else {
        self.askingAttribution = NO;
    }
    
    if ([decoder containsValueForKey:@"deviceToken"]) {
        self.deviceToken        = [decoder decodeObjectForKey:@"deviceToken"];
    }
    
    if ([decoder containsValueForKey:@"updatePackages"]) {
        self.updatePackages     = [decoder decodeBoolForKey:@"updatePackages"];
    } else {
        self.updatePackages     = NO;
    }
    
    if ([decoder containsValueForKey:@"userId"]) {
        self.userId               = [decoder decodeObjectForKey:@"userId"];
    }

    if ([decoder containsValueForKey:@"sessionId"]) {
        self.sessionId               = [decoder decodeObjectForKey:@"sessionId"];
    }

    if ([decoder containsValueForKey:@"isSessionActive"]) {
        self.isSessionActive = [decoder decodeBoolForKey:@"isSessionActive"];
    }

    if ([decoder containsValueForKey:@"screenFlows"]) {
        self.screenFlows = [decoder decodeObjectForKey:@"screenFlows"];
    }

    if ([decoder containsValueForKey:@"attributionDetails"]) {
        self.attributionDetails = [decoder decodeObjectForKey:@"attributionDetails"];
    }
    
    if ([decoder containsValueForKey:@"attributes"]) {
        self.attributes = [decoder decodeObjectForKey:@"attributes"];
    }

    self.lastInterval = -1;
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeInt:self.eventCount         forKey:@"eventCount"];
    [encoder encodeInt:self.sessionCount       forKey:@"sessionCount"];
    [encoder encodeInt:self.subsessionCount    forKey:@"subsessionCount"];
    [encoder encodeDouble:self.sessionLength   forKey:@"sessionLength"];
    [encoder encodeDouble:self.timeSpent       forKey:@"timeSpent"];
    [encoder encodeDouble:self.lastActivity    forKey:@"lastActivity"];
    [encoder encodeObject:self.uuid            forKey:@"uuid"];
    [encoder encodeBool:self.enabled           forKey:@"enabled"];
    [encoder encodeBool:self.askingAttribution forKey:@"askingAttribution"];
    [encoder encodeObject:self.deviceToken     forKey:@"deviceToken"];
    [encoder encodeBool:self.updatePackages    forKey:@"updatePackages"];
    [encoder encodeObject:self.userId            forKey:@"userId"];
    [encoder encodeObject:self.sessionId            forKey:@"sessionId"];
    [encoder encodeObject:self.attributionDetails forKey:@"attributionDetails"];
    [encoder encodeObject:self.attributes forKey:@"attributes"];
    [encoder encodeBool:self.isSessionActive forKey:@"isSessionActive"];
    [encoder encodeObject:self.screenFlows     forKey:@"screenFlows"];
}

#pragma mark - NSCopying protocol methods

- (id)copyWithZone:(NSZone *)zone {
    MXActivityState *copy = [[[self class] allocWithZone:zone] init];
    
    // Copy only values used by package builder.
    if (copy) {
        copy.sessionCount       = self.sessionCount;
        copy.subsessionCount    = self.subsessionCount;
        copy.sessionLength      = self.sessionLength;
        copy.timeSpent          = self.timeSpent;
        copy.uuid               = [self.uuid copyWithZone:zone];
        copy.lastInterval       = self.lastInterval;
        copy.eventCount         = self.eventCount;
        copy.enabled            = self.enabled;
        copy.lastActivity       = self.lastActivity;
        copy.askingAttribution  = self.askingAttribution;
        copy.deviceToken        = [self.deviceToken copyWithZone:zone];
        copy.updatePackages     = self.updatePackages;
        copy.userId             = self.userId;
        copy.sessionId          = self.sessionId;
        copy.isSessionActive    = self.isSessionActive;
        copy.screenFlows        = self.screenFlows;
    }
    
    return copy;
}

@end
