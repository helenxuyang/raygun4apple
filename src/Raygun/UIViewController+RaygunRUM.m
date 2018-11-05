//
//  UIViewController+RaygunRUM.m
//  raygun4apple
//
//  Created by Mitchell Duncan on 3/09/18.
//  Copyright © 2018 Raygun Limited. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#import "UIViewController+RaygunRUM.h"

#import <objc/runtime.h>

#import "RaygunRealUserMonitoring.h"

@implementation UIViewController (RaygunRUM)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // loadView
        SEL originalSelector = @selector(loadView);
        SEL swizzledSelector = @selector(loadViewCapture);
        [self swizzleOriginalSelector:originalSelector withNewSelector:swizzledSelector];
        
        // viewDidLoad
        originalSelector = @selector(viewDidLoad);
        swizzledSelector = @selector(viewDidLoadCapture);
        [self swizzleOriginalSelector:originalSelector withNewSelector:swizzledSelector];
        
        // viewWillAppear
        originalSelector = @selector(viewWillAppear:);
        swizzledSelector = @selector(viewWillAppearCapture:);
        [self swizzleOriginalSelector:originalSelector withNewSelector:swizzledSelector];
        
        // viewDidAppear
        originalSelector = @selector(viewDidAppear:);
        swizzledSelector = @selector(viewDidAppearCapture:);
        [self swizzleOriginalSelector:originalSelector withNewSelector:swizzledSelector];
    });
}

+ (void)swizzleOriginalSelector:(SEL)originalSelector withNewSelector:(SEL)swizzledSelector {
    Class class = [self class];
    
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    
    BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
    
    if (didAddMethod) {
        class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    }
    else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

- (void)loadViewCapture {
    RaygunRealUserMonitoring *rum = [RaygunRealUserMonitoring sharedInstance];
    if (rum.enabled) {
        NSString* viewName = self.description;
        NSNumber* start = (rum.timers)[viewName];
        if (start == nil) {
            double startDouble = CACurrentMediaTime();
            start = @(startDouble);
            (rum.timers)[viewName] = start;
        }
    }
    [self loadViewCapture];
}

- (void)viewDidLoadCapture {
    RaygunRealUserMonitoring *rum = [RaygunRealUserMonitoring sharedInstance];
    if (rum.enabled) {
        NSString* viewName = self.description;
        NSNumber* start = (rum.timers)[viewName];
        if (start == nil) {
            start = @(CACurrentMediaTime());
            (rum.timers)[viewName] = start;
        }
    }
    [self viewDidLoadCapture];
}

- (void)viewWillAppearCapture:(BOOL)animated {
    RaygunRealUserMonitoring *rum = [RaygunRealUserMonitoring sharedInstance];
    if (rum.enabled) {
        NSString* viewName = self.description;
        NSNumber* start = (rum.timers)[viewName];
        if (start == nil) {
            start = @(CACurrentMediaTime());
            (rum.timers)[viewName] = start;
        }
    }
    [self viewWillAppearCapture:animated];
}

- (void)viewDidAppearCapture:(BOOL)animated {
    [self viewDidAppearCapture:animated];
    
    RaygunRealUserMonitoring *rum = [RaygunRealUserMonitoring sharedInstance];
    if (rum.enabled) {
        NSString* viewName = self.description;
        NSNumber* start = (rum.timers)[viewName];
        
        int duration = 0;
        if (start != nil) {
            double interval = CACurrentMediaTime() - start.doubleValue;
            duration = interval * 1000;
        }
        
        [rum.timers removeObjectForKey:viewName];
        
        // Cleanup the view name so when only have the class name.
        viewName = [viewName stringByReplacingOccurrencesOfString:@"<" withString:@""];
        NSUInteger index = [viewName rangeOfString:@":"].location;
        if (index != NSNotFound) {
            viewName = [viewName substringToIndex:index];
        }
        
        if (![rum shouldIgnoreView:viewName]) {
            [rum sendTimingEvent:RaygunEventTimingTypeViewLoaded withName:viewName withDuration:@(duration)];
        }
    }
}

@end
