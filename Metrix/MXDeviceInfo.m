//
//  MXDeviceInfo.m
//  metrix
//

#import "MXDeviceInfo.h"
#import "UIDevice+MXAdditions.h"
#import "NSString+MXAdditions.h"
#import "MXUtil.h"
#import "MXSystemProfile.h"
#import "NSData+MXAdditions.h"
#import "MXReachability.h"

#if !TARGET_OS_TV
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#endif

@implementation MXDeviceInfo

+ (MXDeviceInfo *) deviceInfoWithSdkPrefix:(NSString *)sdkPrefix {
    return [[MXDeviceInfo alloc] initWithSdkPrefix:sdkPrefix];
}

- (id)initWithSdkPrefix:(NSString *)sdkPrefix {
    self = [super init];
    if (self == nil) return nil;

    UIDevice *device = UIDevice.currentDevice;
    NSLocale *locale = NSLocale.currentLocale;
    NSBundle *bundle = NSBundle.mainBundle;
    NSDictionary *infoDictionary = bundle.infoDictionary;

    self.trackingEnabled  = UIDevice.currentDevice.mxTrackingEnabled;
    self.idForAdvertisers = UIDevice.currentDevice.mxIdForAdvertisers;
    self.fbAttributionId  = UIDevice.currentDevice.mxFbAttributionId;
    self.vendorId         = UIDevice.currentDevice.mxVendorId;
    self.bundeIdentifier  = [infoDictionary objectForKey:(NSString *)kCFBundleIdentifierKey];
    self.bundleVersion    = [infoDictionary objectForKey:(NSString *)kCFBundleVersionKey];
    self.bundleShortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    self.languageCode     = [locale objectForKey:NSLocaleLanguageCode];
    self.countryCode      = [locale objectForKey:NSLocaleCountryCode];
    self.osName           = @"ios";
    self.deviceType       = device.mxDeviceType;
    self.deviceName       = device.mxDeviceName;
    self.systemVersion    = device.systemVersion;
    self.machineModel     = [MXSystemProfile machineModel];
    self.cpuSubtype       = [MXSystemProfile cpuSubtype];
    self.osBuild          = [MXSystemProfile osVersion];
    self.screenWidth      = (long) [UIScreen mainScreen].nativeBounds.size.width;
    self.screenHeight     = (long) [UIScreen mainScreen].nativeBounds.size.height;

    if (sdkPrefix == nil) {
        self.clientSdk        = MXUtil.clientSdk;
    } else {
        self.clientSdk = [NSString stringWithFormat:@"%@@%@", sdkPrefix, MXUtil.clientSdk];
    }

    [self injectInstallReceipt:bundle];

    return self;
}

- (void)injectInstallReceipt:(NSBundle *)bundle{
    @try {
        if (![bundle respondsToSelector:@selector(appStoreReceiptURL)]) {
            return;
        }
        NSURL * installReceiptLocation = [bundle appStoreReceiptURL];
        if (installReceiptLocation == nil) return;

        NSData * installReceiptData = [NSData dataWithContentsOfURL:installReceiptLocation];
        if (installReceiptData == nil) return;

        self.installReceiptBase64 = [installReceiptData mxEncodeBase64];
    } @catch (NSException *exception) {
    }
}

/*
-(id)copyWithZone:(NSZone *)zone
{
    MXDeviceInfo* copy = [[[self class] allocWithZone:zone] init];
    if (copy) {
        copy.idForAdvertisers = [self.idForAdvertisers copyWithZone:zone];
        copy.fbAttributionId = [self.fbAttributionId copyWithZone:zone];
        copy.trackingEnabled = self.trackingEnabled;
        copy.vendorId = [self.vendorId copyWithZone:zone];
        copy.clientSdk = [self.clientSdk copyWithZone:zone];
        copy.bundeIdentifier = [self.bundeIdentifier copyWithZone:zone];
        copy.bundleVersion = [self.bundleVersion copyWithZone:zone];
        copy.bundleShortVersion = [self.bundleShortVersion copyWithZone:zone];
        copy.deviceType = [self.deviceType copyWithZone:zone];
        copy.deviceName = [self.deviceName copyWithZone:zone];
        copy.osName = [self.osName copyWithZone:zone];
        copy.systemVersion = [self.systemVersion copyWithZone:zone];
        copy.languageCode = [self.languageCode copyWithZone:zone];
        copy.countryCode = [self.countryCode copyWithZone:zone];
        copy.machineModel = [self.machineModel copyWithZone:zone];
        copy.cpuSubtype = [self.cpuSubtype copyWithZone:zone];
    }

    return copy;
}
*/

@end
