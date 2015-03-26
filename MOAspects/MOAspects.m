//
//  MOAspects.m
//  Sandbox
//
//  Created by Hiromi Motodera on 2015/03/15.
//  Copyright (c) 2015年 MOAI. All rights reserved.
//

#import "MOAspects.h"

#import "MOAspectsStore.h"
#import "MOARuntime.h"

@implementation MOAspects

NSString * const MOAspectsPrefix = @"__moa_aspects_";

#pragma mark - Public

+ (BOOL)hookInstanceMethodInClass:(Class)clazz
                         selector:(SEL)selector
                      aspectsHook:(MOAspectsHook)aspectsHook
                       usingBlock:(id)block
{
    NSAssert([MOARuntime hasInstanceMethodInClass:clazz selector:selector], @"");
    if (![MOARuntime hasInstanceMethodInClass:clazz selector:selector]) {
        return NO;
    }
    
    if ([NSStringFromSelector(selector) hasPrefix:MOAspectsPrefix]) {
        return NO;
    }
    
    Class rootClass = [MOARuntime rootClassForInstanceRespondsToClass:clazz selector:selector];
    SEL aspectsSelector = [MOARuntime selectorWithSelector:selector prefix:MOAspectsPrefix];
    if (![MOARuntime hasInstanceMethodInClass:clazz selector:aspectsSelector]) {
        [MOARuntime copyInstanceMethodInClass:clazz atSelector:selector toSelector:aspectsSelector];
        [MOARuntime overwritingMessageForwardInstanceMethodInClass:clazz selector:selector];
    }
    
    __block MOAspectsTarget *target = [self targetInStoreWithClass:rootClass
                                                        methodType:MOAspectsTargetMethodTypeInstance
                                                          selector:selector
                                                   aspectsSelector:aspectsSelector];
    [self addHookMethodWithTarget:target class:clazz aspectsHook:aspectsHook usingBlock:block];
    
    SEL aspectsForwardInovcationSelector = [MOARuntime selectorWithSelector:@selector(forwardInvocation:)
                                                                     prefix:MOAspectsPrefix];
    if (![MOARuntime hasInstanceMethodInClass:rootClass selector:aspectsForwardInovcationSelector]) {
        [MOARuntime copyInstanceMethodInClass:rootClass
                                   atSelector:@selector(forwardInvocation:)
                                   toSelector:aspectsForwardInovcationSelector];
    }
    
    __weak typeof(self) weakSelf = self;
    [MOARuntime overwritingInstanceMethodInClass:rootClass
                                        selector:@selector(forwardInvocation:)
                             implementationBlock:^(id object, NSInvocation *invocation) {
                                 [weakSelf invokeWithTarget:target toObject:object invocation:invocation];
                             }];
    
    return YES;
}

+ (BOOL)hookClassMethodInClass:(Class)clazz
                      selector:(SEL)selector
                   aspectsHook:(MOAspectsHook)aspectsHook
                    usingBlock:(id)block
{
    NSAssert([MOARuntime hasClassMethodInClass:clazz selector:selector], @"");
    if (![MOARuntime hasClassMethodInClass:clazz selector:selector]) {
        return NO;
    }
    
    if ([NSStringFromSelector(selector) hasPrefix:MOAspectsPrefix]) {
        return NO;
    }
    
    Class rootClass = [MOARuntime rootClassForClassRespondsToClass:clazz selector:selector];
    SEL aspectsSelector = [MOARuntime selectorWithSelector:selector prefix:MOAspectsPrefix];
    if (![MOARuntime hasClassMethodInClass:clazz selector:aspectsSelector]) {
        [MOARuntime copyClassMethodInClass:clazz atSelector:selector toSelector:aspectsSelector];
        [MOARuntime overwritingMessageForwardClassMethodInClass:clazz selector:selector];
    }
    
    __block MOAspectsTarget *target = [self targetInStoreWithClass:rootClass
                                                        methodType:MOAspectsTargetMethodTypeClass
                                                          selector:selector
                                                   aspectsSelector:aspectsSelector];
    [self addHookMethodWithTarget:target class:clazz aspectsHook:aspectsHook usingBlock:block];
    
    __weak typeof(self) weakSelf = self;
    [MOARuntime overwritingClassMethodInClass:rootClass
                                     selector:@selector(forwardInvocation:)
                          implementationBlock:^(id object, NSInvocation *invocation) {
                              [weakSelf invokeWithTarget:target toObject:object invocation:invocation];
                          }];
    
    return YES;
}

#pragma mark - Private

+ (SEL)beforeSelectorWithTarget:(MOAspectsTarget *)target
{
    return NSSelectorFromString([NSString stringWithFormat:@"%@before_%d_%@",
                                 MOAspectsPrefix,
                                 (int)target.beforeSelectors.count,
                                 NSStringFromSelector(target.selector)]);
}

+ (SEL)afterSelectorWithTarget:(MOAspectsTarget *)target
{
    return NSSelectorFromString([NSString stringWithFormat:@"%@after_%d_%@",
                                 MOAspectsPrefix,
                                 (int)target.afterSelectors.count,
                                 NSStringFromSelector(target.selector)]);
}

+ (MOAspectsTarget *)targetInStoreWithClass:(Class)clazz
                                 methodType:(MOAspectsTargetMethodType)methodType
                                   selector:(SEL)selector
                            aspectsSelector:(SEL)aspectsSelector
{
    NSString *key = [MOAspectsStore keyWithClass:clazz
                                      methodType:methodType
                                        selector:selector
                                 aspectsSelector:aspectsSelector];
    MOAspectsTarget *target = [[MOAspectsStore sharedStore] targetForKey:key];
    if (!target) {
        target = [[MOAspectsTarget alloc] initWithClass:clazz
                                              mehodType:methodType
                                         methodSelector:selector
                                        aspectsSelector:aspectsSelector];
        [[MOAspectsStore sharedStore] setTarget:target forKey:key];
    }
    return target;
}

+ (void)addHookMethodWithTarget:(MOAspectsTarget *)target
                          class:(Class)clazz
                    aspectsHook:(MOAspectsHook)aspectsHook
                     usingBlock:(id)block
{
    switch (aspectsHook) {
        case MOAspectsHookBefore:
        {
            SEL beforeSelector = [self beforeSelectorWithTarget:target];
            [self addMethodInClass:target.class
                        methodType:target.methodType
                          selector:beforeSelector
                             block:block];
            [target addBeforeSelector:beforeSelector forClass:clazz];
        }
            break;
        case MOAspectsHookAfter:
        {
            SEL afterSelector = [self afterSelectorWithTarget:target];
            [self addMethodInClass:target.class
                        methodType:target.methodType
                          selector:afterSelector
                             block:block];
            [target addAfterSelector:afterSelector forClass:clazz];
        }
            break;
    }
}

+ (NSMethodSignature *)methodSignatureWithTarget:(MOAspectsTarget *)target
{
    NSMethodSignature *methodSignature;
    if (target.methodType == MOAspectsTargetMethodTypeClass) {
        methodSignature = [MOARuntime classMethodSignatureWithClass:target.class
                                                           selector:target.selector];
    } else {
        methodSignature = [MOARuntime instanceMethodSignatureWithClass:target.class
                                                              selector:target.selector];
    }
    return methodSignature;
}

+ (Class)rootClassWithClass:(Class)clazz methodType:(MOAspectsTargetMethodType)methodType selector:(SEL)selector
{
    if (methodType == MOAspectsTargetMethodTypeClass) {
        return [MOARuntime rootClassForClassRespondsToClass:clazz
                                                   selector:selector];
    } else {
        return [MOARuntime rootClassForInstanceRespondsToClass:clazz
                                                      selector:selector];
    }
}

+ (BOOL)addMethodInClass:(Class)clazz
              methodType:(MOAspectsTargetMethodType)methodType
                selector:(SEL)selector
                   block:(id)block
{
    if (methodType == MOAspectsTargetMethodTypeClass) {
        return [MOARuntime addClassMethodInClass:clazz
                                        selector:selector
                             implementationBlock:block];
    } else {
        return [MOARuntime addInstanceMethodInClass:clazz
                                           selector:selector
                                implementationBlock:block];
    }
}

+ (NSInvocation *)invocationWithBaseInvocation:(NSInvocation *)baseInvocation
                                        targetObject:(id)object
{
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:baseInvocation.methodSignature];
    [invocation setArgument:(__bridge void *)(object) atIndex:0];
    void *argp = NULL;
    for (NSUInteger idx = 2; idx < baseInvocation.methodSignature.numberOfArguments; idx++) {
        const char *type = [baseInvocation.methodSignature getArgumentTypeAtIndex:idx];
        NSUInteger argSize;
        NSGetSizeAndAlignment(type, &argSize, NULL);
        
        if (!(argp = reallocf(argp, argSize))) {
            // TODO: エラー処理
            return nil;
        }
        [baseInvocation getArgument:argp atIndex:idx];
        [invocation setArgument:argp atIndex:idx];
    }
    if (argp != NULL) {
        free(argp);
    }
    return invocation;
}

+ (void)invokeWithTarget:(MOAspectsTarget *)target toObject:(id)object invocation:(NSInvocation *)invocation
{
    NSInvocation *aspectsInvocation = [self invocationWithBaseInvocation:invocation
                                                            targetObject:object];
    for (NSValue *value in target.beforeSelectors) {
        SEL selector = [value pointerValue];
        if ([object class] == [target classForSelector:selector]) {
            [aspectsInvocation setSelector:selector];
            [aspectsInvocation invokeWithTarget:object];
        }
    }
    
    invocation.selector = target.aspectsSelector;
    [invocation invoke];
    
    for (NSValue *value in target.afterSelectors) {
        SEL selector = [value pointerValue];
        if ([object class] == [target classForSelector:selector]) {
            [aspectsInvocation setSelector:selector];
            [aspectsInvocation invokeWithTarget:object];
        }
    }
}

@end