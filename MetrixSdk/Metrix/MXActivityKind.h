//
//  MXActivityKind.h
//  Metrix
//

#import <Foundation/Foundation.h>

#ifndef NS_ENUM
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

typedef NS_ENUM(int, MXActivityKind) {
    MXActivityKindUnknown       = 0,
    MXActivityKindSessionStart  = 1,
    MXActivityKindSessionStop   = 2,
    MXActivityKindCustomEvent   = 3,
};

@interface MXActivityKindUtil : NSObject

+ (NSString *)activityKindToString:(MXActivityKind)activityKind;

+ (MXActivityKind)activityKindFromString:(NSString *)activityKindString;

@end
