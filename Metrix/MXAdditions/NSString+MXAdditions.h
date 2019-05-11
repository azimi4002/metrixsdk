//
//  NSString+MXAdditions.h
//  Metrix
//
#import <Foundation/Foundation.h>

@interface NSString(MXAdditions)

- (NSString *)mxMd5;
- (NSString *)mxSha1;
- (NSString *)mxSha256;
- (NSString *)mxTrim;
- (NSString *)mxUrlEncode;
- (NSString *)mxUrlDecode;
- (NSString *)mxRemoveColons;

+ (NSString *)mxJoin:(NSString *)first, ...;
+ (BOOL)mxIsEqual:(NSString *)first toString:(NSString *)second;

@end
