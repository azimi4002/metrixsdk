//
//  MXSessionParameters.h
//  Metrix
//

#import <Foundation/Foundation.h>

@interface MXSessionParameters : NSObject <NSCopying>

@property (nonatomic, strong) NSMutableDictionary* callbackParameters;
@property (nonatomic, strong) NSMutableDictionary* partnerParameters;

@end
