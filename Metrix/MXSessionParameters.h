//
//  MXSessionParameters.h
//  Metrix
//

#import <Foundation/Foundation.h>

@interface MXSessionParameters : NSObject <NSCopying>

@property (nonatomic, copy) NSString* userId;
@property (nonatomic, strong) NSMutableDictionary* attributes;

@end
