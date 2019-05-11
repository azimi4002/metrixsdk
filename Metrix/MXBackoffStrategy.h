//
//  MXBackoffStrategy.h
//  Metrix
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MXBackoffStrategyType) {
    MXLongWait = 0,
    MXShortWait = 1,
    MXTestWait = 2,
    MXNoWait = 3,
    MXNoRetry = 4
};

@interface MXBackoffStrategy : NSObject

@property (nonatomic, assign) double minRange;

@property (nonatomic, assign) double maxRange;

@property (nonatomic, assign) NSInteger minRetries;

@property (nonatomic, assign) NSTimeInterval maxWait;

@property (nonatomic, assign) NSTimeInterval secondMultiplier;

- (id) initWithType:(MXBackoffStrategyType)strategyType;

+ (MXBackoffStrategy *)backoffStrategyWithType:(MXBackoffStrategyType)strategyType;

@end
