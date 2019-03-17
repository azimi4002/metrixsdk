//
//  MXPackageHandler.m
//  Metrix
//

#import "MXRequestHandler.h"
#import "MXActivityPackage.h"
#import "MXLogger.h"
#import "MXUtil.h"
#import "MXMetrixFactory.h"
#import "MXBackoffStrategy.h"
#import "MXPackageBuilder.h"

static NSString   * const kPackageQueueFilename = @"MetrixIoPackageQueue";
static const char * const kInternalQueueName    = "io.metrix.PackageQueue";


#pragma mark - private
@interface MXPackageHandler()

@property (nonatomic, strong) dispatch_queue_t internalQueue;
@property (nonatomic, strong) dispatch_semaphore_t sendingSemaphore;
@property (nonatomic, strong) id<MXRequestHandler> requestHandler;
@property (nonatomic, strong) NSMutableArray *packageQueue;
@property (nonatomic, strong) MXBackoffStrategy * backoffStrategy;
@property (nonatomic, assign) BOOL paused;
@property (nonatomic, weak) id<MXActivityHandler> activityHandler;
@property (nonatomic, weak) id<MXLogger> logger;
@property (nonatomic, copy) NSString *basePath;

@end

#pragma mark -
@implementation MXPackageHandler

+ (id<MXPackageHandler>)handlerWithActivityHandler:(id<MXActivityHandler>)activityHandler
                                      startsSending:(BOOL)startsSending
{
    return [[MXPackageHandler alloc] initWithActivityHandler:activityHandler startsSending:startsSending];
}

- (id)initWithActivityHandler:(id<MXActivityHandler>)activityHandler
                startsSending:(BOOL)startsSending
{
    self = [super init];
    if (self == nil) return nil;

    self.internalQueue = dispatch_queue_create(kInternalQueueName, DISPATCH_QUEUE_SERIAL);
    self.backoffStrategy = [MXMetrixFactory packageHandlerBackoffStrategy];
    self.basePath = [activityHandler getBasePath];

    [MXUtil launchInQueue:self.internalQueue
                selfInject:self
                     block:^(MXPackageHandler * selfI) {
                         [selfI initI:selfI
                     activityHandler:activityHandler
                       startsSending:startsSending];
                     }];

    return self;
}

- (void)addPackage:(MXActivityPackage *)package {
    [MXUtil launchInQueue:self.internalQueue
                selfInject:self
                     block:^(MXPackageHandler* selfI) {
                         [selfI addI:selfI package:package];
                     }];
}

- (void)sendFirstPackage {
    [MXUtil launchInQueue:self.internalQueue
                selfInject:self
                     block:^(MXPackageHandler* selfI) {
                         [selfI sendFirstI:selfI];
                     }];
}

- (void)sendNextPackage:(MXResponseData *)responseData{
    [MXUtil launchInQueue:self.internalQueue
                selfInject:self
                     block:^(MXPackageHandler* selfI) {
                         [selfI sendNextI:selfI];
                     }];

    [self.activityHandler finishedTracking:responseData];
}

- (void)closeFirstPackage:(MXResponseData *)responseData
          activityPackage:(MXActivityPackage *)activityPackage
{
    responseData.willRetry = YES;
    [self.activityHandler finishedTracking:responseData];

    dispatch_block_t work = ^{
        [self.logger verbose:@"Package handler can send"];
        dispatch_semaphore_signal(self.sendingSemaphore);

        [self sendFirstPackage];
    };

    if (activityPackage == nil) {
        work();
        return;
    }

    NSInteger retries = [activityPackage increaseRetries];
    NSTimeInterval waitTime = [MXUtil waitingTime:retries backoffStrategy:self.backoffStrategy];
    NSString * waitTimeFormatted = [MXUtil secondsNumberFormat:waitTime];

    [self.logger verbose:@"Waiting for %@ seconds before retrying the %d time", waitTimeFormatted, retries];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(waitTime * NSEC_PER_SEC)), self.internalQueue, work);
}

- (void)pauseSending {
    self.paused = YES;
}

- (void)resumeSending {
    self.paused = NO;
}

- (void)updatePackages:(MXSessionParameters *)sessionParameters
{
    // make copy to prevent possible Activity Handler changes of it
    MXSessionParameters * sessionParametersCopy = [sessionParameters copy];

    [MXUtil launchInQueue:self.internalQueue
                selfInject:self
                     block:^(MXPackageHandler* selfI) {
                         [selfI updatePackagesI:selfI sessionParameters:sessionParametersCopy];
                     }];
}

- (void)flush {
    [MXUtil launchInQueue:self.internalQueue selfInject:self block:^(MXPackageHandler *selfI) {
        [selfI flushI:selfI];
    }];
}

- (NSString *)getBasePath {
    return _basePath;
}

- (void)teardown {
    [MXMetrixFactory.logger verbose:@"MXPackageHandler teardown"];
    if (self.sendingSemaphore != nil) {
        dispatch_semaphore_signal(self.sendingSemaphore);
    }
    if (self.requestHandler != nil) {
        [self.requestHandler teardown];
    }
    [self teardownPackageQueueS];
    self.internalQueue = nil;
    self.sendingSemaphore = nil;
    self.requestHandler = nil;
    self.backoffStrategy = nil;
    self.activityHandler = nil;
    self.logger = nil;
}

+ (void)deleteState {
    [MXPackageHandler deletePackageQueue];
}

+ (void)deletePackageQueue {
    [MXUtil deleteFileWithName:kPackageQueueFilename];
}

#pragma mark - internal
- (void)initI:(MXPackageHandler *)selfI
activityHandler:(id<MXActivityHandler>)activityHandler
startsSending:(BOOL)startsSending
{
    selfI.activityHandler = activityHandler;
    selfI.paused = !startsSending;
    selfI.requestHandler = [MXMetrixFactory requestHandlerForPackageHandler:selfI
                                                          andActivityHandler:selfI.activityHandler];
    selfI.logger = MXMetrixFactory.logger;
    selfI.sendingSemaphore = dispatch_semaphore_create(1);
    [selfI readPackageQueueI:selfI];
}

- (void)addI:(MXPackageHandler *)selfI
     package:(MXActivityPackage *)newPackage
{
    [selfI.packageQueue addObject:newPackage];
    [selfI.logger debug:@"Added package %d (%@)", selfI.packageQueue.count, newPackage];
    [selfI.logger verbose:@"%@", newPackage.extendedString];

    [selfI writePackageQueueS:selfI];
}

- (void)sendFirstI:(MXPackageHandler *)selfI
{
    NSUInteger queueSize = selfI.packageQueue.count;
    if (queueSize == 0) return;

    if (selfI.paused) {
        [selfI.logger debug:@"Package handler is paused"];
        return;
    }

    if (dispatch_semaphore_wait(selfI.sendingSemaphore, DISPATCH_TIME_NOW) != 0) {
        [selfI.logger verbose:@"Package handler is already sending"];
        return;
    }

    MXActivityPackage *activityPackage = [selfI.packageQueue objectAtIndex:0];
    if (![activityPackage isKindOfClass:[MXActivityPackage class]]) {
        [selfI.logger error:@"Failed to read activity package"];
        [selfI sendNextI:selfI];
        return;
    }

    [selfI.requestHandler sendPackage:activityPackage
                            queueSize:queueSize - 1];
}

- (void)sendNextI:(MXPackageHandler *)selfI {
    if ([selfI.packageQueue count] > 0) {
        [selfI.packageQueue removeObjectAtIndex:0];
        [selfI writePackageQueueS:selfI];
    }

    dispatch_semaphore_signal(selfI.sendingSemaphore);
    [selfI sendFirstI:selfI];
}

- (void)updatePackagesI:(MXPackageHandler *)selfI
      sessionParameters:(MXSessionParameters *)sessionParameters
{
    [selfI.logger debug:@"Updating package handler queue"];
//    [selfI.logger verbose:@"Session callback parameters: %@", sessionParameters.callbackParameters];
//    [selfI.logger verbose:@"Session partner parameters: %@", sessionParameters.partnerParameters];

//    for (MXActivityPackage * activityPackage in selfI.packageQueue) {
//        // callback parameters
//        NSDictionary * mergedCallbackParameters = [MXUtil mergeParameters:sessionParameters.callbackParameters
//                                                                    source:activityPackage.callbackParameters
//                                                             parameterName:@"Callback"];

//        [MXPackageBuilder parameters:activityPackage.parameters
//                        setDictionary:mergedCallbackParameters
//                               forKey:@"callback_params"];

//        // partner parameters
//        NSDictionary * mergedPartnerParameters = [MXUtil mergeParameters:sessionParameters.partnerParameters
//                                                                   source:activityPackage.partnerParameters
//                                                            parameterName:@"Partner"];

//        [MXPackageBuilder parameters:activityPackage.parameters
//                        setDictionary:mergedPartnerParameters
//                               forKey:@"partner_params"];
//    }

    [selfI writePackageQueueS:selfI];
}

- (void)flushI:(MXPackageHandler *)selfI {
    [selfI.packageQueue removeAllObjects];
    [selfI writePackageQueueS:selfI];
}

#pragma mark - private
- (void)readPackageQueueI:(MXPackageHandler *)selfI {
    [NSKeyedUnarchiver setClass:[MXActivityPackage class] forClassName:@"AIActivityPackage"];

    id object = [MXUtil readObject:kPackageQueueFilename objectName:@"Package queue" class:[NSArray class]];

    if (object != nil) {
        selfI.packageQueue = object;
    } else {
        selfI.packageQueue = [NSMutableArray array];
    }
}

- (void)writePackageQueueS:(MXPackageHandler *)selfS {
    @synchronized ([MXPackageHandler class]) {
        if (selfS.packageQueue == nil) {
            return;
        }

        [MXUtil writeObject:selfS.packageQueue fileName:kPackageQueueFilename objectName:@"Package queue"];
    }
}

- (void)teardownPackageQueueS {
    @synchronized ([MXPackageHandler class]) {
        if (self.packageQueue == nil) {
            return;
        }

        [self.packageQueue removeAllObjects];
        self.packageQueue = nil;
    }
}

- (void)dealloc {
    // Cleanup code
    if (self.sendingSemaphore != nil) {
        dispatch_semaphore_signal(self.sendingSemaphore);
    }
}

@end
