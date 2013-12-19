//
//  AppDelegate.m
//  BeardedSpice
//
//  Created by Tyler Rhodes on 12/8/13.
//  Copyright (c) 2013 Tyler Rhodes / Jose Falcon. All rights reserved.
//

#import "AppDelegate.h"
#import "MASShortcut+UserDefaults.h"

#import "ChromeTabAdapter.h"
#import "SafariTabAdapter.h"

@implementation BeardedSpiceApp
- (void)sendEvent:(NSEvent *)theEvent
{
	// If event tap is not installed, handle events that reach the app instead
	BOOL shouldHandleMediaKeyEventLocally = ![SPMediaKeyTap usesGlobalMediaKeyTap];

	if(shouldHandleMediaKeyEventLocally && [theEvent type] == NSSystemDefined && [theEvent subtype] == SPSystemDefinedEventMediaKeys) {
		[(id)[self delegate] mediaKeyTap:nil receivedMediaKeyEvent:theEvent];
	}
	[super sendEvent:theEvent];
}
@end

@implementation AppDelegate

NSString *const BeardedSpiceActiveTabShortcut = @"BeardedSpiceActiveTabShortcut";

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    // Register defaults for the whitelist of apps that want to use media keys
	[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithObjectsAndKeys:
                                                             [SPMediaKeyTap defaultMediaKeyUserBundleIdentifiers], kMediaKeyUsingBundleIdentifiersDefaultsKey,
                                                             nil]];
    keyTap = [[SPMediaKeyTap alloc] initWithDelegate:self];
	if([SPMediaKeyTap usesGlobalMediaKeyTap]) {
		[keyTap startWatchingMediaKeys];
	} else {
		NSLog(@"Media key monitoring disabled");
    }

    // associate view with userdefaults
    self.shortcutView.associatedUserDefaultsKey = BeardedSpiceActiveTabShortcut;

    // check if there is a user default
    if (!self.shortcutView.shortcutValue) {
        self.shortcutView.shortcutValue = [MASShortcut shortcutWithKeyCode:kVK_F8
                                                             modifierFlags:NSCommandKeyMask];
    }

    [self refreshActiveTabShortcut];
    
    // setup default media strategy
    mediaStrategyRegistry = [MediaStrategyRegistry getDefaultRegistry];
}

- (void)awakeFromNib
{
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

    [statusItem setMenu:statusMenu];
    [statusItem setImage:[NSImage imageNamed:@"youtube-play.png"]];
    [statusItem setHighlightMode:YES];

    [statusItem setAction:@selector(refreshTabs:)];
    [statusItem setTarget:self];

    [self refreshApplications];
}

- (void)menuWillOpen:(NSMenu *)menu
{
    [self refreshTabs: menu];
}

- (void)removeAllItems
{
    NSInteger count = statusMenu.itemArray.count;
    for (int i = 0; i < count - 3; i++) {
        [statusMenu removeItemAtIndex:0];
    }
}

- (IBAction)exitApp:(id)sender {
    [NSApp terminate: nil];
}

- (void)refreshTabs:(id) sender
{
    NSLog(@"Refreshing tabs...");
    [self removeAllItems];
    [self refreshApplications];

    if (chromeApp) {
        for (ChromeWindow *chromeWindow in chromeApp.windows) {
            for (ChromeTab *chromeTab in chromeWindow.tabs) {
                [self addChromeStatusMenuItemFor:chromeTab andWindow:chromeWindow];
            }
        }
    }
    if (safariApp) {
        for (SafariWindow *safariWindow in safariApp.windows) {
            for (SafariTab *safariTab in safariWindow.tabs) {
                [self addSafariStatusMenuItemFor:safariTab andWindow:safariWindow];
            }
        }
    }
    
    if ([statusMenu numberOfItems] == 3) {
        NSMenuItem *item = [statusMenu insertItemWithTitle:@"No applicable tabs open :(" action:nil keyEquivalent:@"" atIndex:0];
        [item setEnabled:NO];
    }
}

-(void)addChromeStatusMenuItemFor:(ChromeTab *)chromeTab andWindow:(ChromeWindow*)chromeWindow
{
    NSMenuItem *menuItem = [self addStatusMenuItemFor:chromeTab withTitle:[chromeTab title] andURL:[chromeTab URL]];
    if (menuItem) {
        id<Tab> tab = [ChromeTabAdapter initWithTab:chromeTab andWindow:chromeWindow];
        [menuItem setRepresentedObject:tab];
        [self setStatusMenuItemStatus:menuItem forTab:tab];
    }
}

-(void)addSafariStatusMenuItemFor:(SafariTab *)safariTab andWindow:(SafariWindow*)safariWindow
{
    NSMenuItem *menuItem = [self addStatusMenuItemFor:safariTab withTitle:[safariTab name] andURL:[safariTab URL]];
    if (menuItem) {
        id<Tab> tab = [SafariTabAdapter initWithApplication:safariApp
                                                  andWindow:safariWindow
                                                     andTab:safariTab];
        [menuItem setRepresentedObject:tab];
        [self setStatusMenuItemStatus:menuItem forTab:tab];
    }
}

-(void)setStatusMenuItemStatus:(NSMenuItem *)item forTab:(id <Tab>)tab
{
    if (activeTab && [[activeTab key] isEqualToString:[tab key]]) {
        [item setState:NSOnState];
    }
}

-(NSMenuItem *)addStatusMenuItemFor:(id)tab withTitle:(NSString *)title andURL:(NSString *)URL
{
    if ([mediaStrategyRegistry getMediaStrategyForURL:URL]) {
        return [statusMenu insertItemWithTitle:[self trim:title toLength:40] action:@selector(updateActiveTab:) keyEquivalent:@"" atIndex:0];
    }
    return NULL;
}

- (void)updateActiveTab:(id) sender
{
    activeTab = [sender representedObject];
    NSLog(@"Active tab set to %@", activeTab);
}

-(void)mediaKeyTap:(SPMediaKeyTap*)keyTap receivedMediaKeyEvent:(NSEvent*)event;
{
    if (!activeTab) {
        return;
    }
    
	NSAssert([event type] == NSSystemDefined && [event subtype] == SPSystemDefinedEventMediaKeys, @"Unexpected NSEvent in mediaKeyTap:receivedMediaKeyEvent:");
	// here be dragons...
	int keyCode = (([event data1] & 0xFFFF0000) >> 16);
	int keyFlags = ([event data1] & 0x0000FFFF);
	BOOL keyIsPressed = (((keyFlags & 0xFF00) >> 8)) == 0xA;
	int keyRepeat = (keyFlags & 0x1);

	if (keyIsPressed) {
        MediaStrategy *strategy = [mediaStrategyRegistry getMediaStrategyForURL:[activeTab URL]];
        if (!strategy) {
            return;
        }
		NSString *debugString = [NSString stringWithFormat:@"%@", keyRepeat?@", repeated.":@"."];
		switch (keyCode) {
			case NX_KEYTYPE_PLAY:
				debugString = [@"Play/pause pressed" stringByAppendingString:debugString];
                [activeTab executeJavascript:[strategy toggle]];
				break;
			case NX_KEYTYPE_FAST:
				debugString = [@"Ffwd pressed" stringByAppendingString:debugString];
                [activeTab executeJavascript:[strategy next]];
				break;
			case NX_KEYTYPE_REWIND:
				debugString = [@"Rewind pressed" stringByAppendingString:debugString];
                [activeTab executeJavascript:[strategy previous]];
				break;
			default:
				debugString = [NSString stringWithFormat:@"Key %d pressed%@", keyCode, debugString];
				break;
                // More cases defined in hidsystem/ev_keymap.h
		}
        NSLog(@"%@", debugString);
	}
}

-(SBApplication *)getRunningSBApplicationWithIdentifier:(NSString *)bundleIdentifier
{
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier];
    if ([apps count] > 0) {
        NSRunningApplication *app = [apps objectAtIndex:0];
        NSLog(@"App %@ is running %@", bundleIdentifier, app);
        return [SBApplication applicationWithProcessIdentifier:[app processIdentifier]];
    }
    return NULL;
}

-(NSString *)trim:(NSString *)string toLength:(NSInteger)max
{
    if ([string length] > max) {
        return [NSString stringWithFormat:@"%@...", [string substringToIndex:(max - 3)]];
    }
    return [string substringToIndex: [string length]];
}

- (void)refreshApplications
{
    chromeApp = (ChromeApplication *)[self getRunningSBApplicationWithIdentifier:@"com.google.Chrome"];
    safariApp = (SafariApplication *)[self getRunningSBApplicationWithIdentifier:@"com.apple.Safari"];
}

- (void)refreshActiveTabShortcut
{
    [MASShortcut registerGlobalShortcutWithUserDefaultsKey:BeardedSpiceActiveTabShortcut handler:^{
        if (chromeApp.frontmost) {
            // chromeApp.windows[0] is the front most window.
            ChromeWindow *chromeWindow = chromeApp.windows[0];

            // use 'get' to force a hard reference.
            activeTab = [ChromeTabAdapter initWithTab:[[chromeWindow activeTab] get] andWindow:chromeWindow];
        } else if (safariApp.frontmost) {
            // is safari.windows[0] the frontmost?
            SafariWindow *safariWindow = safariApp.windows[0];

            // use 'get' to force a hard reference.
            activeTab = [SafariTabAdapter initWithApplication:safariApp
                                                    andWindow:safariWindow
                                                       andTab:[[safariWindow currentTab] get]];
        }

        if (activeTab) {
            NSLog(@"Active tab set to %@", activeTab);
        }
    }];
}

@end