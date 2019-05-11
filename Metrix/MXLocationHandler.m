//
// Created by Tapsell on 2019-03-18.
// Copyright (c) 2019 metrix. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MXLocationHandler.h"
#import "MXUserDefaults.h"

@implementation MXLocationHandler {
    CLLocationManager *locationManager;
    CLGeocoder *geocoder;
    CLLocation *lastLocation;
    NSString *country;
    NSString *adminArea;
    NSString *subAdminArea;
    int updateCounter;
}
static int MAX_LOC_UPDATE = 2;

- (NSDictionary *)locationDictionary{
    NSMutableDictionary *toReturn = [[NSMutableDictionary alloc] init];
    if(lastLocation) toReturn[@"latitude"] = @(lastLocation.coordinate.latitude);
    if(lastLocation) toReturn[@"longitude"] = @(lastLocation.coordinate.longitude);
    if(lastLocation) toReturn[@"country"] = country;
    if(lastLocation) toReturn[@"admin_area"] = adminArea;
    if(lastLocation) toReturn[@"sub_admin_area"] = subAdminArea;
    return toReturn;
}

- (instancetype)init{
    self = [super init];
    if(!self)return nil;
    updateCounter = 0;

    locationManager = [[CLLocationManager alloc] init];
    locationManager.delegate = self;
    locationManager.distanceFilter = kCLDistanceFilterNone;
    locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    [self startUpdatingLocationIfPossible];
    geocoder = [[CLGeocoder alloc] init];
    return self;
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if(locations.count==0)return;
    lastLocation = locations.lastObject;
    [self saveUserDefaults];
    [geocoder reverseGeocodeLocation:[locations lastObject] completionHandler:^(NSArray *placemarks, NSError *error) {
        if(!placemarks || placemarks.count == 0)return;

        CLPlacemark *placemark = [placemarks lastObject];
        country = placemark.country;
        adminArea = placemark.administrativeArea;
        subAdminArea = placemark.subAdministrativeArea;
        [self saveUserDefaults];
    }];

    if(++updateCounter >= MAX_LOC_UPDATE){
        [locationManager stopUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    [self startUpdatingLocationIfPossible];
}


- (void)startUpdatingLocationIfPossible{
    if ([[[UIDevice currentDevice] systemVersion] floatValue] < 8.0 ||
            ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorizedWhenInUse &&
                    [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) ||
            [CLLocationManager authorizationStatus] == kCLAuthorizationStatusAuthorizedAlways
            ){
        [locationManager startUpdatingLocation];
    }
}

- (void)saveUserDefaults{
    [MXUserDefaults setLocationDictionary:[self locationDictionary]];
}

- (void)dealloc {
    if(locationManager){
        [locationManager stopUpdatingLocation];
    }
}

@end