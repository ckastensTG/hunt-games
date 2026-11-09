// Timeless Games: the iOS share sheet for a short text, with no Godot plugin.
//
// timeless_core's iOS export step (editor/ios_native_sources.gd) copies this
// file into the exported Xcode project and adds it to the app target, so
// Xcode compiles it with the rest of the app. The game calls
// OS.shell_open("timelessshare:?text=<percent-encoded text>") (ShareSheet in
// platform/share_sheet.gd). Godot's shell_open asks UIApplication canOpenURL:
// and then openURL:options:completionHandler:. This file swaps in its own
// versions of those two methods when the app loads: for the timelessshare
// scheme it says yes and shows UIActivityViewController with the text; any
// other address goes on to iOS as before.
//
// Plain Objective-C with ARC (Godot's Xcode project turns ARC on), UIKit only.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const TGShareScheme = @"timelessshare";

static BOOL TGIsShareURL(NSURL *url) {
	return url != nil && [url.scheme caseInsensitiveCompare:TGShareScheme] == NSOrderedSame;
}

static NSString *TGShareText(NSURL *url) {
	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	for (NSURLQueryItem *item in components.queryItems) {
		if ([item.name isEqualToString:@"text"] && item.value != nil) {
			return item.value;
		}
	}
	return @"";
}

// The view controller on top: the key window's root, then whatever it presents.
static UIViewController *TGTopViewController(void) {
	UIWindow *window = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:[UIWindowScene class]]) {
			continue;
		}
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) {
				window = w;
				break;
			}
			if (window == nil) {
				window = w;
			}
		}
		if (window.isKeyWindow) {
			break;
		}
	}
	id<UIApplicationDelegate> delegate = UIApplication.sharedApplication.delegate;
	if (window == nil && [delegate respondsToSelector:@selector(window)]) {
		window = delegate.window;
	}
	UIViewController *top = window.rootViewController;
	while (top.presentedViewController != nil && !top.presentedViewController.isBeingDismissed) {
		top = top.presentedViewController;
	}
	return top;
}

static BOOL TGPresentShareSheet(NSString *text) {
	UIViewController *top = TGTopViewController();
	if (top == nil) {
		return NO;
	}
	UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[ text ] applicationActivities:nil];
	// On iPad the sheet is a popover and needs a place to point to: the middle
	// of the screen, with no arrow.
	UIPopoverPresentationController *popover = sheet.popoverPresentationController;
	if (popover != nil) {
		popover.sourceView = top.view;
		CGRect bounds = top.view.bounds;
		popover.sourceRect = CGRectMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds), 1, 1);
		popover.permittedArrowDirections = 0;
	}
	[top presentViewController:sheet animated:YES completion:nil];
	return YES;
}

@implementation UIApplication (TimelessShare)

+ (void)load {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		Class cls = [UIApplication class];
		Method canOpen = class_getInstanceMethod(cls, @selector(canOpenURL:));
		Method tgCanOpen = class_getInstanceMethod(cls, @selector(tg_canOpenURL:));
		if (canOpen != NULL && tgCanOpen != NULL) {
			method_exchangeImplementations(canOpen, tgCanOpen);
		}
		Method open = class_getInstanceMethod(cls, @selector(openURL:options:completionHandler:));
		Method tgOpen = class_getInstanceMethod(cls, @selector(tg_openURL:options:completionHandler:));
		if (open != NULL && tgOpen != NULL) {
			method_exchangeImplementations(open, tgOpen);
		}
	});
}

// After the exchange, calling tg_… runs UIKit's original method.
- (BOOL)tg_canOpenURL:(NSURL *)url {
	if (TGIsShareURL(url)) {
		return YES;
	}
	return [self tg_canOpenURL:url];
}

- (void)tg_openURL:(NSURL *)url
		options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options
		completionHandler:(void (^)(BOOL success))completion {
	if (!TGIsShareURL(url)) {
		[self tg_openURL:url options:options completionHandler:completion];
		return;
	}
	NSString *text = TGShareText(url);
	dispatch_async(dispatch_get_main_queue(), ^{
		BOOL shown = TGPresentShareSheet(text);
		if (completion != nil) {
			completion(shown);
		}
	});
}

@end
