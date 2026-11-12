// Timeless Games: Apple's App Store sheet inside the game, for "Other Timeless
// Games", with no Godot plugin.
//
// timeless_core's iOS export step (editor/ios_native_sources.gd) copies this
// file into the exported Xcode project and adds it to the app target, like
// TimelessShare.m. The game calls OS.shell_open("timelessstore:?id=<Apple ID>")
// (StoreLinks in catalog/store_links.gd). Godot's shell_open asks
// UIApplication canOpenURL: and then openURL:options:completionHandler:. This
// file swaps in its own versions of those two methods when the app loads:
// for the timelessstore scheme it says yes and shows SKStoreProductViewController
// with that app's page; any other address goes on to iOS as before (and to
// TimelessShare.m's versions, when both are in the app).
//
// StoreKit is looked up when it's used (NSClassFromString), so this file
// needs no framework added to the project: the purchase plugin already
// brings StoreKit into the app. If the sheet can't be shown, or the page
// doesn't load, the App Store app opens the page instead
// (https://apps.apple.com/app/id<Apple ID>).
//
// Plain Objective-C with ARC (Godot's Xcode project turns ARC on), UIKit only.

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const TGStoreScheme = @"timelessstore";

static BOOL TGIsStoreURL(NSURL *url) {
	return url != nil && [url.scheme caseInsensitiveCompare:TGStoreScheme] == NSOrderedSame;
}

// The Apple ID from timelessstore:?id=<digits>; nil unless it's all digits.
static NSString *TGStoreAppleID(NSURL *url) {
	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	for (NSURLQueryItem *item in components.queryItems) {
		if (![item.name isEqualToString:@"id"] || item.value.length == 0 || item.value.length > 12) {
			continue;
		}
		NSCharacterSet *notDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
		if ([item.value rangeOfCharacterFromSet:notDigits].location == NSNotFound) {
			return item.value;
		}
	}
	return nil;
}

static UIViewController *TGStoreTopViewController(void) {
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

static void TGOpenAppStorePage(NSString *appleID);

// Closes the sheet when the player taps Done (StoreKit calls
// productViewControllerDidFinish: on its delegate).
@interface TGStoreSheetDelegate : NSObject
@end

@implementation TGStoreSheetDelegate
- (void)productViewControllerDidFinish:(UIViewController *)viewController {
	[viewController dismissViewControllerAnimated:YES completion:nil];
}
@end

static TGStoreSheetDelegate *TGSheetDelegate(void) {
	static TGStoreSheetDelegate *delegate = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		delegate = [TGStoreSheetDelegate new];
	});
	return delegate;
}

static BOOL TGPresentStoreSheet(NSString *appleID) {
	Class sheetClass = NSClassFromString(@"SKStoreProductViewController");
	UIViewController *top = TGStoreTopViewController();
	SEL load = NSSelectorFromString(@"loadProductWithParameters:completionBlock:");
	if (sheetClass == Nil || top == nil || ![sheetClass instancesRespondToSelector:load]) {
		return NO;
	}
	UIViewController *sheet = [[sheetClass alloc] init];
	if ([sheet respondsToSelector:@selector(setDelegate:)]) {
		((void (*)(id, SEL, id))objc_msgSend)(sheet, @selector(setDelegate:), TGSheetDelegate());
	}
	// SKStoreProductParameterITunesItemIdentifier is @"id", an NSNumber.
	NSDictionary *parameters = @{ @"id" : @(appleID.longLongValue) };
	__weak UIViewController *weakSheet = sheet;
	void (^loaded)(BOOL, NSError *) = ^(BOOL ok, NSError *error) {
		if (ok) {
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			UIViewController *shown = weakSheet;
			if (shown.presentingViewController != nil) {
				[shown dismissViewControllerAnimated:NO completion:^{
					TGOpenAppStorePage(appleID);
				}];
			} else {
				TGOpenAppStorePage(appleID);
			}
		});
	};
	((void (*)(id, SEL, NSDictionary *, void (^)(BOOL, NSError *)))objc_msgSend)(sheet, load, parameters, loaded);
	[top presentViewController:sheet animated:YES completion:nil];
	return YES;
}

@implementation UIApplication (TimelessStoreSheet)

+ (void)load {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		Class cls = [UIApplication class];
		Method canOpen = class_getInstanceMethod(cls, @selector(canOpenURL:));
		Method tgCanOpen = class_getInstanceMethod(cls, @selector(tgstore_canOpenURL:));
		if (canOpen != NULL && tgCanOpen != NULL) {
			method_exchangeImplementations(canOpen, tgCanOpen);
		}
		Method open = class_getInstanceMethod(cls, @selector(openURL:options:completionHandler:));
		Method tgOpen = class_getInstanceMethod(cls, @selector(tgstore_openURL:options:completionHandler:));
		if (open != NULL && tgOpen != NULL) {
			method_exchangeImplementations(open, tgOpen);
		}
	});
}

// After the exchange, calling tgstore_… runs the method that was there before.
- (BOOL)tgstore_canOpenURL:(NSURL *)url {
	if (TGIsStoreURL(url)) {
		return TGStoreAppleID(url) != nil;
	}
	return [self tgstore_canOpenURL:url];
}

- (void)tgstore_openURL:(NSURL *)url
		options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options
		completionHandler:(void (^)(BOOL success))completion {
	if (!TGIsStoreURL(url)) {
		[self tgstore_openURL:url options:options completionHandler:completion];
		return;
	}
	NSString *appleID = TGStoreAppleID(url);
	dispatch_async(dispatch_get_main_queue(), ^{
		BOOL shown = appleID != nil && TGPresentStoreSheet(appleID);
		if (!shown && appleID != nil) {
			TGOpenAppStorePage(appleID);
			shown = YES;
		}
		if (completion != nil) {
			completion(shown);
		}
	});
}

@end

// The App Store app on the game's page: the plain web address, which iOS
// hands to the App Store.
static void TGOpenAppStorePage(NSString *appleID) {
	NSURL *page = [NSURL URLWithString:[NSString stringWithFormat:@"https://apps.apple.com/app/id%@", appleID]];
	if (page != nil) {
		[UIApplication.sharedApplication openURL:page options:@{} completionHandler:nil];
	}
}
