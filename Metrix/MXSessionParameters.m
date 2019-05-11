//
//  MXSessionParameters.m
//  Metrix
//

#import "MXSessionParameters.h"

@implementation MXSessionParameters

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super init];

    if (self == nil) {
        return nil;
    }

    return self;
}

#pragma mark - NSCopying
-(id)copyWithZone:(NSZone *)zone
{
    MXSessionParameters* copy = [[[self class] allocWithZone:zone] init];
    if (copy) {
        copy.userId = [self.userId copyWithZone:zone];
        copy.attributes  = [self.attributes copyWithZone:zone];
    }

    return copy;
}

@end
