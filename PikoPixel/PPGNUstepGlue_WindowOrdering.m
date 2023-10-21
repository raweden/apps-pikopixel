/*
    PPGNUstepGlue_WindowOrdering.m

    Copyright 2014-2018,2020 Josh Freeman
    http://www.twilightedge.com

    This file is part of PikoPixel for GNUstep.
    PikoPixel is a graphical application for drawing & editing pixel-art images.

    PikoPixel is free software: you can redistribute it and/or modify it under
    the terms of the GNU Affero General Public License as published by the
    Free Software Foundation, either version 3 of the License, or (at your
    option) any later version approved for PikoPixel by its copyright holder (or
    an authorized proxy).

    PikoPixel is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
    details.

    You should have received a copy of the GNU Affero General Public License
    along with this program. If not, see <http://www.gnu.org/licenses/>.
*/

//  Workarounds for several window-ordering issues in GNUstep affecting various window managers:
// Document windows (NSNormalWindowLevel) can obscure higher-level windows that should always
// stay in front.
//
//  - Menus: On Compiz & Xfwm, the main menu's submenus can be obscured behind document windows.
// The workaround is to set the window level of the main menu's submenu windows to
// NSMainMenuWindowLevel.
//
//  - Modals: On all window managers except WindowMaker, modal windows (open & save panels, etc.)
// can be obscured behind document windows. The workaround is to make the modal window a child
// window of the current main document window, ordered NSWindowAbove.
//
//  - Panels: On Compiz & KWin, floating panels can be obscured behind document windows. The
// workaround is to set all panels to be child windows of the current main document window,
// ordered NSWindowAbove.

#ifdef GNUSTEP

#import <Cocoa/Cocoa.h>
#import "NSObject_PPUtilities.h"
#import "PPAppBootUtilities.h"
#import "PPGNUstepGlueUtilities.h"
#import "PPApplication.h"
#import "PPDocumentWindowController.h"
#import "PPPanelController.h"
#import "PPPanelsController.h"
#import "PPPopupPanelsController.h"
#import "PPScreencastController.h"
#import "PPScreencastPopupPanelController.h"


#define kTargetWindowManagerTypesMask_WindowOrdering_Menus  \
                (kPPGSWindowManagerTypeMask_Compiz          \
                | kPPGSWindowManagerTypeMask_Xfwm)

#define kTargetWindowManagerTypesMask_WindowOrdering_Modals \
                (~kPPGSWindowManagerTypeMask_WindowMaker)

#define kTargetWindowManagerTypesMask_WindowOrdering_Panels \
                (kPPGSWindowManagerTypeMask_Compiz          \
                | kPPGSWindowManagerTypeMask_KWin)


@interface NSMenu (PPGNUstepGlue_WindowOrderingUtilities)
- (void) ppGSGlue_SetAllMenuWindowsToMainMenuLevel;
@end

@interface NSWindow (PPGNUstepGlue_WindowOrderingUtilities)
- (void) ppGSGlue_SetupToRemainInFrontOfWindow: (NSWindow *) window;
@end

@interface PPPanelController (PPGNUstepGlue_WindowOrderingUtilities)
- (void) ppGSGlue_SetupPanelToRemainInFrontOfWindow: (NSWindow *) window;
@end

@interface PPPanelsController (PPGNUstepGlue_WindowOrderingUtilities)
- (void) ppGSGlue_SetupPanelsToRemainInFrontOfWindow: (NSWindow *) window;
@end

@interface PPPopupPanelsController (PPGNUstepGlue_WindowOrderingUtilities)
- (void) ppGSGlue_SetupPopupPanelsToRemainInFrontOfWindow: (NSWindow *) window;
@end

@interface PPDocumentWindowController (PPGNUstepGlue_WindowOrderingUtilities)
- (void) ppGSGlue_SetupAllPanelsToRemainInFrontOfWindow: (NSWindow *) window;
@end

#if PP_OPTIONAL__BUILD_WITH_SCREENCASTING

@interface PPScreencastController (PPGNUstepGlue_WindowOrderingUtilities)
- (void) ppGSGlue_WindowOrdering_HandleScreencastEnableOrDisable;
- (void) ppGSGlue_SetupScreencastPopupToRemainInFrontOfWindow: (NSWindow *) window;
@end

#endif  // PP_OPTIONAL__BUILD_WITH_SCREENCASTING


@implementation NSObject (PPGNUstepGlue_WindowOrdering)

+ (void) ppGSGlue_WindowOrdering_Menus_Install
{
    [[NSApp mainMenu] ppGSGlue_SetAllMenuWindowsToMainMenuLevel];
}

+ (void) ppGSGlue_WindowOrdering_Modals_Install
{
    macroSwizzleInstanceMethod(PPApplication, runModalForWindow:,
                                ppGSPatch_WindowOrdering_RunModalForWindow:);
}

+ (void) ppGSGlue_WindowOrdering_Panels_Install
{
    macroSwizzleInstanceMethod(PPDocumentWindowController, windowDidBecomeMain:,
                                ppGSPatch_WindowDidBecomeMain:);

#if PP_OPTIONAL__BUILD_WITH_SCREENCASTING

    PPGSGlueUtils_PerformPPScreencastControllerSelectorOnEnableOrDisable(
                    @selector(ppGSGlue_WindowOrdering_HandleScreencastEnableOrDisable));

#endif  // PP_OPTIONAL__BUILD_WITH_SCREENCASTING
}

+ (void) ppGSGlue_WindowOrdering_Install
{
    if (PPGSGlueUtils_WindowManagerMatchesTypeMask(
                                        kTargetWindowManagerTypesMask_WindowOrdering_Menus))
    {
        [self ppGSGlue_WindowOrdering_Menus_Install];
    }

    if (PPGSGlueUtils_WindowManagerMatchesTypeMask(
                                        kTargetWindowManagerTypesMask_WindowOrdering_Modals))
    {
        [self ppGSGlue_WindowOrdering_Modals_Install];
    }

    if (PPGSGlueUtils_WindowManagerMatchesTypeMask(
                                        kTargetWindowManagerTypesMask_WindowOrdering_Panels))
    {
        [self ppGSGlue_WindowOrdering_Panels_Install];
    }
}

+ (void) load
{
    macroPerformNSObjectSelectorAfterAppLoads(ppGSGlue_WindowOrdering_Install);
}

@end

@implementation PPApplication (PPGNUstepGlue_WindowOrdering_Modals)

- (NSInteger) ppGSPatch_WindowOrdering_RunModalForWindow: (NSWindow *) theWindow
{
    NSWindow *mainWindow;
    NSInteger returnValue;
    bool didManuallyOrderModalWindowToFront = NO;

    mainWindow = [self mainWindow];

    [mainWindow orderFrontRegardless];

    if (![theWindow parentWindow])
    {
        [theWindow ppGSGlue_SetupToRemainInFrontOfWindow: mainWindow];
        didManuallyOrderModalWindowToFront = YES;
    }

    returnValue = [self ppGSPatch_WindowOrdering_RunModalForWindow: theWindow];

    if (didManuallyOrderModalWindowToFront)
    {
        [theWindow ppGSGlue_SetupToRemainInFrontOfWindow: nil];
    }

    return returnValue;
}

@end

@implementation PPDocumentWindowController (PPGNUstepGlue_WindowOrdering_Panels)

- (void) ppGSPatch_WindowDidBecomeMain: (NSNotification *) notification
{
    [self ppGSPatch_WindowDidBecomeMain: notification];

    [self ppGSGlue_SetupAllPanelsToRemainInFrontOfWindow: [notification object]];
}

@end

@implementation NSMenu (PPGNUstepGlue_WindowOrderingUtilities)

- (void) ppGSGlue_SetAllMenuWindowsToMainMenuLevel
{
    NSWindow *menuWindow;
    NSEnumerator *menuItemsEnumerator;
    NSMenuItem *menuItem;

    menuWindow = [self window];

    if ([menuWindow level] != NSMainMenuWindowLevel)
    {
        [menuWindow setLevel: NSMainMenuWindowLevel];
    }

    menuItemsEnumerator = [[self itemArray] objectEnumerator];

    while (menuItem = [menuItemsEnumerator nextObject])
    {
        if ([menuItem hasSubmenu])
        {
            [[menuItem submenu] ppGSGlue_SetAllMenuWindowsToMainMenuLevel];
        }
    }
}

@end

@implementation NSWindow (PPGNUstepGlue_WindowOrderingUtilities)

- (void) ppGSGlue_SetupToRemainInFrontOfWindow: (NSWindow *) window
{
    NSWindow *currentParentWindow = [self parentWindow];

    if (currentParentWindow == window)
    {
        return;
    }

    if (currentParentWindow)
    {
        [currentParentWindow removeChildWindow: self];
    }

    if (window)
    {
        [window addChildWindow: self ordered: NSWindowAbove];

        if ([self isVisible])
        {
            [self orderWindow: NSWindowAbove relativeTo: [window windowNumber]];
        }
    }
}

@end

@implementation PPPanelController (PPGNUstepGlue_WindowOrderingUtilities)

- (void) ppGSGlue_SetupPanelToRemainInFrontOfWindow: (NSWindow *) window
{
    [[self window] ppGSGlue_SetupToRemainInFrontOfWindow: window];
}

@end

@implementation PPPanelsController (PPGNUstepGlue_WindowOrderingUtilities)

- (void) ppGSGlue_SetupPanelsToRemainInFrontOfWindow: (NSWindow *) window
{
    [_panelControllers makeObjectsPerformSelector:
                                        @selector(ppGSGlue_SetupPanelToRemainInFrontOfWindow:)
                        withObject: window];
}

@end

@implementation PPPopupPanelsController (PPGNUstepGlue_WindowOrderingUtilities)

- (void) ppGSGlue_SetupPopupPanelsToRemainInFrontOfWindow: (NSWindow *) window
{
    [_popupControllers makeObjectsPerformSelector:
                                        @selector(ppGSGlue_SetupPanelToRemainInFrontOfWindow:)
                        withObject: window];
}

@end

#if PP_OPTIONAL__BUILD_WITH_SCREENCASTING

@implementation PPScreencastController (PPGNUstepGlue_WindowOrderingUtilities)

- (void) ppGSGlue_WindowOrdering_HandleScreencastEnableOrDisable
{
    NSWindow *window = (_screencastingIsEnabled) ? [NSApp mainWindow] : nil;

    [_screencastPopupController ppGSGlue_SetupPanelToRemainInFrontOfWindow: window];
}

- (void) ppGSGlue_SetupScreencastPopupToRemainInFrontOfWindow: (NSWindow *) window
{
    if (!_screencastingIsEnabled)
        return;

    [_screencastPopupController ppGSGlue_SetupPanelToRemainInFrontOfWindow: window];
}

@end

#endif  // PP_OPTIONAL__BUILD_WITH_SCREENCASTING

@implementation PPDocumentWindowController (PPGNUstepGlue_WindowOrderingUtilities)

- (void) ppGSGlue_SetupAllPanelsToRemainInFrontOfWindow: (NSWindow *) window
{
    static NSWindow *previousWindow = nil;

    if (!window || (window == previousWindow))
    {
        return;
    }

    [_panelsController ppGSGlue_SetupPanelsToRemainInFrontOfWindow: window];

    [_popupPanelsController ppGSGlue_SetupPopupPanelsToRemainInFrontOfWindow: window];

    [[NSColorPanel sharedColorPanel] ppGSGlue_SetupToRemainInFrontOfWindow: window];

#if PP_OPTIONAL__BUILD_WITH_SCREENCASTING

    [[PPScreencastController sharedController]
                                ppGSGlue_SetupScreencastPopupToRemainInFrontOfWindow: window];

#endif  // PP_OPTIONAL__BUILD_WITH_SCREENCASTING

    [previousWindow release];
    previousWindow = [window retain];
}

@end

#endif  // GNUSTEP

