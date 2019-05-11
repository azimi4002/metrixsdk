//
//  MXRequestHandler.m
//  Metrix
//

#import "MXUtil.h"
#import "MXLogger.h"
#import "MXActivityKind.h"
#import "MXMetrixFactory.h"
#import "MXPackageBuilder.h"
#import "MXActivityPackage.h"
#import "NSString+MXAdditions.h"

static const char * const kInternalQueueName = "io.metrix.RequestQueue";

@interface MXRequestHandler()

@property (nonatomic, strong) dispatch_queue_t internalQueue;

@property (nonatomic, weak) id<MXLogger> logger;

@property (nonatomic, weak) id<MXPackageHandler> packageHandler;

@property (nonatomic, weak) id<MXActivityHandler> activityHandler;

@property (nonatomic, copy) NSString *basePath;

@end

@implementation MXRequestHandler

#pragma mark - Public methods

+ (MXRequestHandler *)handlerWithPackageHandler:(id<MXPackageHandler>)packageHandler
                              andActivityHandler:(id<MXActivityHandler>)activityHandler {
    return [[MXRequestHandler alloc] initWithPackageHandler:packageHandler
                                          andActivityHandler:activityHandler];
}

- (id)initWithPackageHandler:(id<MXPackageHandler>)packageHandler
          andActivityHandler:(id<MXActivityHandler>)activityHandler {
    self = [super init];
    
    if (self == nil) {
        return nil;
    }
    
    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);
    self.packageHandler = packageHandler;
    self.activityHandler = activityHandler;
    self.logger = MXMetrixFactory.logger;
    self.basePath = [packageHandler getBasePath];

    return self;
}

- (void)sendPackage:(MXActivityPackage *)activityPackage queueSize:(NSUInteger)queueSize {
    [MXUtil launchInQueue:self.internalQueue
                selfInject:self
                     block:^(MXRequestHandler* selfI) {
                         [selfI sendI:selfI activityPackage:activityPackage queueSize:queueSize];
                     }];
}

- (void)teardown {
    [MXMetrixFactory.logger verbose:@"MXRequestHandler teardown"];
    
    self.logger = nil;
    self.internalQueue = nil;
    self.packageHandler = nil;
    self.activityHandler = nil;
}

#pragma mark - Private & helper methods

- (void)sendI:(MXRequestHandler *)selfI activityPackage:(MXActivityPackage *)activityPackage queueSize:(NSUInteger)queueSize {
    NSURL *url;

    NSString *baseUrl = [MXMetrixFactory baseUrl];
    if (selfI.basePath != nil) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", baseUrl, selfI.basePath]];
    } else {
        url = [NSURL URLWithString:baseUrl];
    }

    [MXUtil sendPostRequest:url
                   queueSize:queueSize
          prefixErrorMessage:activityPackage.failureMessage
          suffixErrorMessage:@"Will retry later"
             activityPackage:activityPackage
         responseDataHandler:^(MXResponseData *responseData) {
             // Check if any package response contains information that user has opted out.
             // If yes, disable SDK and flush any potentially stored packages that happened afterwards.
//             if (responseData.trackingState == MXTrackingStateOptedOut) {
//                 [selfI.activityHandler setTrackingStateOptedOut];
//                 return;
//             }

             if (responseData.jsonResponse == nil) {
                 [selfI.packageHandler closeFirstPackage:responseData activityPackage:activityPackage];
                 return;
             }

             [selfI.packageHandler sendNextPackage:responseData];
         }];
}

@end
