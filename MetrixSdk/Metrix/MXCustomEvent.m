//

#import "MXCustomEvent.h"


@implementation MXCustomEvent {
}

+ (MXCustomEvent *)newEvent:(NSString *)slug attributes:(NSDictionary *)attributes metrics:(NSDictionary *)metrics{
    return [[MXCustomEvent alloc] initWithSlug:slug attributes:attributes metrics:metrics];
}

- (id)initWithSlug:(NSString *)slug attributes:(NSDictionary *)attributes metrics:(NSDictionary *)metrics{
    self = [super init];
    if (self == nil) return nil;
    _slug = slug;
    _attributes = attributes;
    _metrics = metrics;
    return self;
}

- (BOOL) isValid {
    return self.slug != nil;
}

- (id)copyWithZone:(struct _NSZone *)zone {
    MXCustomEvent *copy = [[[self class] allocWithZone:zone] init];

    if (copy) {
        copy->_slug = [self.slug copyWithZone:zone];
        copy->_attributes = [self.attributes copyWithZone:zone];
        copy->_metrics = [self.metrics copyWithZone:zone];
    }
    return copy;
}


@end