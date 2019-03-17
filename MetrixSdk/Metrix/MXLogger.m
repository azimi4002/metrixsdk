//
//  MXLogger.m
//  Metrix
//

#import "MXLogger.h"

static NSString * const kLogTag = @"Metrix";

@interface MXLogger()

@property (nonatomic, assign) MXLogLevel loglevel;
@property (nonatomic, assign) BOOL logLevelLocked;
@property (nonatomic, assign) BOOL isProductionEnvironment;

@end

#pragma mark -
@implementation MXLogger

- (id)init {
    self = [super init];
    if (self == nil) return nil;

    //default values
    _loglevel = MXLogLevelInfo;
    self.logLevelLocked = NO;
    self.isProductionEnvironment = NO;

    return self;
}

- (void)setLogLevel:(MXLogLevel)logLevel
isProductionEnvironment:(BOOL)isProductionEnvironment
{
    if (self.logLevelLocked) {
        return;
    }
    _loglevel = logLevel;
    self.isProductionEnvironment = isProductionEnvironment;
}

- (void)lockLogLevel {
    self.logLevelLocked = YES;
}

- (void)verbose:(NSString *)format, ... {
    if (self.isProductionEnvironment) return;
    if (self.loglevel > MXLogLevelVerbose) return;
    va_list parameters; va_start(parameters, format);
    [self logLevel:@"v" format:format parameters:parameters];
}

- (void)debug:(NSString *)format, ... {
    if (self.isProductionEnvironment) return;
    if (self.loglevel > MXLogLevelDebug) return;
    va_list parameters; va_start(parameters, format);
    [self logLevel:@"d" format:format parameters:parameters];
}

- (void)info:(NSString *)format, ... {
    if (self.isProductionEnvironment) return;
    if (self.loglevel > MXLogLevelInfo) return;
    va_list parameters; va_start(parameters, format);
    [self logLevel:@"i" format:format parameters:parameters];
}

- (void)warn:(NSString *)format, ... {
    if (self.isProductionEnvironment) return;
    if (self.loglevel > MXLogLevelWarn) return;
    va_list parameters; va_start(parameters, format);
    [self logLevel:@"w" format:format parameters:parameters];
}
- (void)warnInProduction:(nonnull NSString *)format, ... {
    if (self.loglevel > MXLogLevelWarn) return;
    va_list parameters; va_start(parameters, format);
    [self logLevel:@"w" format:format parameters:parameters];
}

- (void)error:(NSString *)format, ... {
    if (self.isProductionEnvironment) return;
    if (self.loglevel > MXLogLevelError) return;
    va_list parameters; va_start(parameters, format);
    [self logLevel:@"e" format:format parameters:parameters];
}

- (void)assert:(NSString *)format, ... {
    if (self.isProductionEnvironment) return;
    if (self.loglevel > MXLogLevelAssert) return;
    va_list parameters; va_start(parameters, format);
    [self logLevel:@"a" format:format parameters:parameters];
}

// private implementation
- (void)logLevel:(NSString *)logLevel format:(NSString *)format parameters:(va_list)parameters {
    NSString *string = [[NSString alloc] initWithFormat:format arguments:parameters];
    va_end(parameters);

    NSArray *lines = [string componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSLog(@"\t[%@]%@: %@", kLogTag, logLevel, line);
    }
}

+ (MXLogLevel)logLevelFromString:(NSString *)logLevelString {
    if ([logLevelString isEqualToString:@"verbose"])
        return MXLogLevelVerbose;

    if ([logLevelString isEqualToString:@"debug"])
        return MXLogLevelDebug;

    if ([logLevelString isEqualToString:@"info"])
        return MXLogLevelInfo;

    if ([logLevelString isEqualToString:@"warn"])
        return MXLogLevelWarn;

    if ([logLevelString isEqualToString:@"error"])
        return MXLogLevelError;

    if ([logLevelString isEqualToString:@"assert"])
        return MXLogLevelAssert;

    if ([logLevelString isEqualToString:@"suppress"])
        return MXLogLevelSuppress;

    // default value if string does not match
    return MXLogLevelInfo;
}

@end
