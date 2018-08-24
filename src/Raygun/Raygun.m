//
//  Raygun.m
//  CrashReporter
//
//  Created by Martin on 25/09/13.
//
//

#import <UIKit/UIKit.h>

#import "Raygun.h"
#import "Pulse.h"
#import "KSCrash.h"
#import "RaygunCrashInstallation.h"
#import "RaygunOnBeforeSendDelegate.h"
#import "RaygunCrashReportCustomSink.h"

static NSString * const kRaygunIdentifierUserDefaultsKey = @"com.raygun.identifier";
static NSString * const kApiEndPoint = @"https://api.raygun.com/entries";

static Raygun *sharedRaygunInstance = nil;
static RaygunCrashInstallation *sharedCrashInstallation = nil;

@interface Raygun()

@property (nonatomic, readwrite, copy) NSString *apiKey;
@property (nonatomic, readwrite, retain) NSOperationQueue *queue;

@end

@implementation Raygun

@synthesize applicationVersion   = _applicationVersion;
@synthesize tags                 = _tags;
@synthesize customData           = _customData;
@synthesize onBeforeSendDelegate = _onBeforeSendDelegate;
@synthesize userInformation      = _userInformation;

#pragma mark - Setters -

- (void)setApplicationVersion:(NSString *)applicationVersion {
    _applicationVersion = applicationVersion;
    [self updateCrashReportUserInfo];
}

-(void)setTags:(NSArray *)tags {
    _tags = tags;
    [self updateCrashReportUserInfo];
}

- (void)setCustomData:(NSDictionary *)customData {
    _customData = customData;
    [self updateCrashReportUserInfo];
}

- (void)setOnBeforeSendDelegate:(id)delegate {
    _onBeforeSendDelegate = delegate;
}

#pragma mark - Initialising Methods -

+ (id)sharedClient {
    return sharedRaygunInstance;
}

+ (id)sharedClientWithApiKey:(NSString *)apiKey {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedRaygunInstance = [[self alloc] initWithApiKey:apiKey];
    });
    return sharedRaygunInstance;
}

- (id)initWithApiKey:(NSString *)apiKey {
    if ((self = [super init])) {
        self.apiKey = apiKey;
        self.queue  = [[NSOperationQueue alloc] init];
    }
    return self;
}

#pragma mark - Crash Reporting -

- (void)enableCrashReporting {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Install the crash reporter.
        sharedCrashInstallation = [[RaygunCrashInstallation alloc] init];
        [sharedCrashInstallation install];
        
        // Configure KSCrash settings.
        [KSCrash.sharedInstance setMaxReportCount:10]; // TODO: Allow this to be configured
        
        // Set an anonymous user for any new reports.
        [self assignAnonymousUser];
        
        // Send any outstanding reports.
        [sharedCrashInstallation sendAllReports];
    });
}

- (void)sendException:(NSException *)exception {
    [self sendException:exception withTags:nil withCustomData:nil];
}

- (void)sendException:(NSException *)exception withTags:(NSArray *)tags {
    [self sendException:exception withTags:tags withCustomData:nil];
}

- (void)sendException:(NSException *)exception withTags:(NSArray *)tags withCustomData:(NSDictionary *)customData {
    [KSCrash.sharedInstance reportUserException:exception.name
                                         reason:exception.reason
                                       language:@""
                                     lineOfCode:nil
                                     stackTrace:[exception callStackSymbols]
                                  logAllThreads:NO
                               terminateProgram:NO];
    
    [sharedCrashInstallation sendAllReportsWithSink:[[RaygunCrashReportCustomSink alloc] initWithTags:tags withCustomData:customData]];
}

- (void)sendException:(NSString *)exceptionName withReason:(NSString *)reason withTags:(NSArray *)tags withCustomData:(NSDictionary *)customData {
    NSException *exception = [NSException exceptionWithName:exceptionName reason:reason userInfo:nil];
    
    @try {
        @throw exception;
    }
    @catch (NSException *caughtException) {
        [self sendException:caughtException withTags:tags withCustomData:customData];
    }
}

- (void)sendError:(NSError *)error withTags:(NSArray *)tags withCustomData:(NSDictionary *)customData {
    NSError *innerError = [self getInnerError:error];
    NSString *reason = [innerError localizedDescription];
    if (!reason) {
        reason = @"Unknown";
    }
    
    NSException *exception = [NSException exceptionWithName:[NSString stringWithFormat:@"%@ [code: %ld]", innerError.domain, (long)innerError.code] reason:reason userInfo:nil];
    
    @try {
        @throw exception;
    }
    @catch (NSException *caughtException) {
        [self sendException:caughtException withTags:tags withCustomData:customData];
    }
}

- (void)sendMessage:(RaygunMessage *)message {
    bool send = true;
    
    if (_onBeforeSendDelegate != nil) {
        send = [_onBeforeSendDelegate onBeforeSend:message];
    }
    
    if (send) {
        [self sendCrashData:[message convertToJson] completionHandler:NULL];
    }
}

- (void)crash {
    char* invalid = (char*)-1;
    *invalid = 1;
}

- (NSError *)getInnerError:(NSError *)error {
    NSError *innerErrror = error.userInfo[NSUnderlyingErrorKey];
    if (innerErrror) {
        return [self getInnerError:innerErrror];
    }
    return error;
}

- (void)updateCrashReportUserInfo {
    NSMutableDictionary *userInfo = [[NSMutableDictionary alloc] init];
    userInfo[@"applicationVersion"] = _applicationVersion;
    userInfo[@"tags"]               = _tags;
    userInfo[@"customData"]         = _customData;
    userInfo[@"userInfo"]           = [_userInformation convertToDictionary];
    
    [KSCrash.sharedInstance setUserInfo:userInfo];
}

- (void)sendCrashData:(NSData *)crashData completionHandler:(void (^)(NSURLResponse*, NSData*, NSError*))handler {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kApiEndPoint]];
    
    request.HTTPMethod = @"POST";
    [request setValue:self.apiKey forHTTPHeaderField:@"X-ApiKey"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"%tu", [crashData length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:crashData];
    
    [NSURLConnection sendAsynchronousRequest:request queue:self.queue completionHandler:handler];
}

#pragma mark - Real User Monitoring -

- (void)enableRealUserMonitoring {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // TODO
    });
}

- (void)enableAutomaticNetworkLogging:(bool)networkLogging {
    // TODO
}

- (void)ignoreViews:(NSArray *)viewNames {
    // TODO
}

- (void)ignoreURLs:(NSArray *)urls {
    // TODO
}

- (void)sendTimingEvent:(RaygunEventType)eventType withName:(NSString *)name withDuration:(int)milliseconds {
    NSString* type = @"p";
    if (eventType == NetworkCall) {
        type = @"n";
    }
    [Pulse sendPulseEvent:name withType:type withDuration:[NSNumber numberWithInteger:milliseconds]];
}

#pragma mark - Unique User Tracking -

- (void)assignAnonymousUser {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *identifier = [defaults stringForKey:kRaygunIdentifierUserDefaultsKey];
    
    if (!identifier) {
        identifier = [self generateAnonymousIdentifier];
        [self storeIdentifier:identifier];
    }
    
    RaygunUserInformation *userInfo = [[RaygunUserInformation alloc] initWithIdentifier:identifier];
    userInfo.isAnonymous = true;
    
    [self identifyWithUserInformation:userInfo];
}

- (NSString *)generateAnonymousIdentifier {
    NSString *identifier;
    
    if ([[UIDevice currentDevice] respondsToSelector:@selector(identifierForVendor)]) {
        identifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    }
    else {
        CFUUIDRef theUUID = CFUUIDCreate(NULL);
        identifier = (__bridge NSString *)CFUUIDCreateString(NULL, theUUID);
        CFRelease(theUUID);
    }
    
    return identifier;
}

- (void)storeIdentifier:(NSString *)identifier {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:identifier forKey:kRaygunIdentifierUserDefaultsKey];
    [defaults synchronize];
}

- (void)identifyWithIdentifier:(NSString *)userId {
    _userInformation = [[RaygunUserInformation alloc] initWithIdentifier:userId];
    [self identifyWithUserInformation:_userInformation];
}

- (void)identifyWithUserInformation:(RaygunUserInformation *)userInformation {
    _userInformation = userInformation;
    
    //[self.pulse identifyWithUserInfo:userInfo];
    [self updateCrashReportUserInfo];
}

@end

