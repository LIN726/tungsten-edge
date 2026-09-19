#import "DockGlassRuntimeBridge.h"

#import <AppKit/AppKit.h>
#import <dlfcn.h>
#import <limits.h>
#import <QuartzCore/QuartzCore.h>

typedef uint32_t (*MainConnectionIDFunction)(void);
typedef int32_t (*SetWindowBlurFunction)(uint32_t, uint32_t, uint32_t);

static MainConnectionIDFunction mainConnectionID = NULL;
static SetWindowBlurFunction setWindowBlur = NULL;

static void TEDockGlassLoadWindowBlurFunctions(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_LAZY | RTLD_LOCAL
        );
        if (handle == NULL) return;
        mainConnectionID = (MainConnectionIDFunction)dlsym(handle, "SLSMainConnectionID");
        setWindowBlur = (SetWindowBlurFunction)dlsym(
            handle,
            "SLSSetWindowBackgroundBlurRadius"
        );
    });
}

BOOL TEDockGlassCanSetWindowBackgroundBlur(void) {
    TEDockGlassLoadWindowBlurFunctions();
    return mainConnectionID != NULL && setWindowBlur != NULL;
}

BOOL TEDockGlassSetWindowBackgroundBlurRadius(NSInteger windowNumber, uint32_t radius) {
    TEDockGlassLoadWindowBlurFunctions();

    if (windowNumber <= 0 || (uint64_t)windowNumber > UINT32_MAX ||
        mainConnectionID == NULL || setWindowBlur == NULL) {
        return NO;
    }
    @try {
        return setWindowBlur(
            mainConnectionID(),
            (uint32_t)windowNumber,
            MIN(radius, (uint32_t)64)
        ) == 0;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static SEL TEDockGlassVariantSelector(void) {
    return NSSelectorFromString(@"set_variant:");
}

BOOL TEDockGlassSupportsSystemVariant(void) {
    Class glassClass = NSClassFromString(@"NSGlassEffectView");
    return glassClass != Nil && [glassClass instancesRespondToSelector:TEDockGlassVariantSelector()];
}

BOOL TEDockGlassSetSystemVariant(id glassView, NSInteger variant) {
    SEL selector = TEDockGlassVariantSelector();
    if (glassView == nil || ![glassView respondsToSelector:selector]) return NO;
    @try {
        IMP implementation = [glassView methodForSelector:selector];
        ((void (*)(id, SEL, NSInteger))implementation)(glassView, selector, variant);
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

BOOL TEDockGlassSetRefraction(id candidate, double height, double amount) {
    if (![candidate isKindOfClass:CALayer.class] || !isfinite(height) || !isfinite(amount) || height <= 0) {
        return NO;
    }
    CALayer *layer = candidate;
    @try {
        NSMutableArray *filters = [layer.filters mutableCopy];
        BOOL changed = NO;
        for (NSUInteger index = 0; index < filters.count; index++) {
            id filter = filters[index];
            if (![filter respondsToSelector:NSSelectorFromString(@"type")] ||
                ![[filter valueForKey:@"type"] isEqual:@"glassBackground"]) continue;
            if (![filter respondsToSelector:NSSelectorFromString(@"inputKeys")] ||
                ![filter respondsToSelector:@selector(copyWithZone:)]) continue;
            NSArray *keys = [filter valueForKey:@"inputKeys"];
            NSString *heightKey = @"inputInnerRefractionHeight";
            NSString *amountKey = @"inputInnerRefractionAmount";
            if (![keys containsObject:heightKey] || ![keys containsObject:amountKey]) continue;
            if ([[filter valueForKey:heightKey] isEqual:@(height)] &&
                [[filter valueForKey:amountKey] isEqual:@(amount)]) continue;
            id copy = [filter copy];
            [copy setValue:@(height) forKey:heightKey];
            [copy setValue:@(amount) forKey:amountKey];
            filters[index] = copy;
            changed = YES;
        }
        if (changed) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            layer.filters = filters;
            [CATransaction commit];
        }
        return changed;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}
