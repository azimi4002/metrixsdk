//
//  UIDevice+MXAdditions.h
//  Metrix
//
//  Created by Christian Wellenbrock (@wellle) on 23rd July 2012.
//  Copyright © 2012-2018 Metrix GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MXActivityHandler.h"

@interface UIDevice(MXAdditions)

- (BOOL)mxTrackingEnabled;
- (NSString *)mxIdForAdvertisers;
- (NSString *)mxFbAttributionId;
- (NSString *)mxDeviceType;
- (NSString *)mxDeviceName;
- (NSString *)mxCreateUuid;
- (NSString *)mxVendorId;
- (void)mxSetIad:(MXActivityHandler *)activityHandler
     triesV3Left:(int)triesV3Left;
@end
