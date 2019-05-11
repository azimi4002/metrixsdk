//
// Created by Tapsell on 2019-03-18.
// Copyright (c) 2019 metrix. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface MXLocationHandler : NSObject<CLLocationManagerDelegate>
- (NSDictionary *)locationDictionary;
- (void)startUpdatingLocationIfPossible;
@end