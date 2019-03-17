//
//  MXAttributionHandler.m
//  metrix
//

#import "MXAttributionHandler.h"
#import "MXMetrixFactory.h"
#import "MXUtil.h"
#import "MXActivityHandler.h"
#import "NSString+MXAdditions.h"
#import "MXTimerOnce.h"
#import "MXPackageBuilder.h"

static const char * const kInternalQueueName     = "ir.metrix.AttributionQueue";
static NSString   * const kAttributionTimerName   = @"Attribution timer";

@interface MXAttributionHandler()

@property (nonatomic, strong) dispatch_queue_t internalQueue;
@property (nonatomic, weak) id<MXActivityHandler> activityHandler;
@property (nonatomic, weak) id<MXLogger> logger;
@property (nonatomic, strong) MXTimerOnce *attributionTimer;
@property (atomic, assign) BOOL paused;
@property (nonatomic, copy) NSString *basePath;
@property (nonatomic, copy) NSString *lastInitiatedBy;

@end

@implementation MXAttributionHandler

+ (id<MXAttributionHandler>)handlerWithActivityHandler:(id<MXActivityHandler>)activityHandler
                                          startsSending:(BOOL)startsSending;
{
    return [[MXAttributionHandler alloc] initWithActivityHandler:activityHandler
                                                    startsSending:startsSending];
}

- (id)initWithActivityHandler:(id<MXActivityHandler>) activityHandler
                startsSending:(BOOL)startsSending;
{
    self = [super init];
    if (self == nil) return nil;

    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);
    self.activityHandler = activityHandler;
    self.logger = MXMetrixFactory.logger;
    self.paused = !startsSending;
    self.basePath = [activityHandler getBasePath];
//    __weak __typeof__(self) weakSelf = self;
//    self.attributionTimer = [MXTimerOnce timerWithBlock:^{
//        __typeof__(self) strongSelf = weakSelf;
//        if (strongSelf == nil) return;
//
//        [strongSelf requestAttributionI:strongSelf];
//    }
//                                                   queue:self.internalQueue
//                                                    name:kAttributionTimerName];

    return self;
}

- (void)checkSessionResponse:(MXSessionStartResponseData *)sessionResponseData {
    [MXUtil launchInQueue:self.internalQueue
                selfInject:self
                     block:^(MXAttributionHandler* selfI) {
                         [selfI checkSessionResponseI:selfI
                                  sessionResponseData:sessionResponseData];
                     }];
}

- (void)pauseSending {
    self.paused = YES;
}

- (void)resumeSending {
    self.paused = NO;
}

#pragma mark - internal
- (void)checkSessionResponseI:(MXAttributionHandler*)selfI
          sessionResponseData:(MXSessionStartResponseData *)sessionResponseData {

    [selfI.activityHandler launchSessionStartResponseTasks:sessionResponseData];
}


#pragma mark - private

- (void)teardown {
    [MXMetrixFactory.logger verbose:@"MXAttributionHandler teardown"];

    if (self.attributionTimer != nil) {
        [self.attributionTimer cancel];
    }
    self.internalQueue = nil;
    self.activityHandler = nil;
    self.logger = nil;
    self.attributionTimer = nil;
}

@end
