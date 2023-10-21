/*
    PPGNUstepGlue_ModalSessions.m

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

// Workarounds for issues during GNUstep modal dialog sessions:
// - During a modal session, should not be able to start a new modal session in a different
// document window (new/open/save menu actions)
// - Panels stay visible during save & alert dialogs because they're not sheets on GNUstep, so
// manually post NSWindow willBeginSheet & didEndSheet notifications (triggers panel-hiding
// logic), and add additonal logic to keep panels hidden during non-sheet modal sessions
// - Screencasting implementation currently misses events during modal sessions, so manually
// hide the screencasting popup when a modal session begins
// - GNUstep doesn't prevent the window manager from bringing a different document window to
// the front if a user clicks on it during a modal session, however the new frontmost window
// won't respond to further user interaction because the app's still in a modal runloop, so
// signal to the user that non-main windows are currently non-interactive by overlaying a
// 'greyed-out' pattern over them


#ifdef GNUSTEP

#import <Cocoa/Cocoa.h>
#import "NSObject_PPUtilities.h"
#import "PPAppBootUtilities.h"
#import "PPApplication.h"
#import "PPPanelsController.h"
#import "PPDocument.h"
#import "PPDocumentWindow.h"
#import "PPDocumentWindowController.h"
#import "PPScreencastController.h"
#import "PPGNUstepGlueUtilities.h"
#import "PPCanvasView.h"
#import "NSColor_PPUtilities.h"
#import "NSBitmapImageRep_PPUtilities.h"
#import "NSImage_PPUtilities.h"


#define kMinTimeIntervalToAllowNewDocumentAfterModalSessionEnds     (0.5)

// kInactiveCanvasOverlayColor: the pattern color drawn on top of non-main canvas views during
// a modal session; GNUstep's NSRectFill() - used when generating PikoPixel's pattern colors -
// doesn't handle transparent colors correctly (doesn't use NSCompositeCopy mode), so in order
// to make a partially-transparent pattern color, need to first make an opaque version with
// non-transparent colors, then manually dissolve the pattern's bitmap to the correct opacity
// (using local utility method, ppGSGlue_PatternColorDissolvedToOpacity:)
#define kInactiveCanvasOverlayColor                                                 \
            [[NSColor ppDiagonalCheckerboardPatternColorWithBoxDimension: 4         \
                        color1: [NSColor ppSRGBColorWithWhite: 0.333 alpha: 1.0]    \
                        color2: [NSColor ppSRGBColorWithWhite: 0.0 alpha: 1.0]]     \
                ppGSGlue_PatternColorDissolvedToOpacity: 0.6]


static int gModalSessionCount = 0;
static NSTimeInterval gLastModalSessionEndTime = 0;
static PPCanvasView *gMainCanvasViewDuringModalSession = nil;
static bool gDisallowManualPostingOfSheetNotifications = NO, gScreencastingIsEnabled = NO,
            gCanvasViewDrawRectPatchIsInstalled = NO;


static inline NSSet *DisallowedModalActionNamesSet(void)
{
    return [NSSet setWithObjects: @"newDocument:", @"newDocumentFromSelection:",
                                    @"newDocumentFromPasteboard:", @"openDocument:",
                                    @"saveDocument:", @"saveDocumentAs:", @"saveDocumentTo:",
                                    @"editHotkeySettings:", nil];
}

static void ToggleModalSessionCanvasViewDrawRectPatch(void);
static void RedrawAllCanvasViews(void);
static PPCanvasView *CurrentMainWindowCanvasView(void);


@interface NSColor (PPGNUstepGlue_ModalSessionsUtilities)

- (NSColor *) ppGSGlue_PatternColorDissolvedToOpacity: (float) opacity;

@end

@interface NSApplication (PPGNUstepGlue_ModalSessionsUtilities)

- (void) ppGSGlue_IncrementModalSessionCount;
- (void) ppGSGlue_DecrementModalSessionCount;

@end

@implementation NSObject (PPGNUstepGlue_ModalSessions)

+ (void) ppGSGlue_ModalSessions_InstallPatches
{
    macroSwizzleInstanceMethod(PPApplication,
                                beginSheet:modalForWindow:modalDelegate:
                                    didEndSelector:contextInfo:,
                                ppGSPatch_BeginSheet:modalForWindow:modalDelegate:
                                    didEndSelector:contextInfo:);

    macroSwizzleInstanceMethod(PPApplication, runModalForWindow:,
                                ppGSPatch_ModalSessions_RunModalForWindow:);


    macroSwizzleInstanceMethod(NSMenu, performActionForItemAtIndex:,
                                ppGSPatch_PerformActionForItemAtIndex:);


    macroSwizzleInstanceMethod(NSDocumentController, newDocument:, ppGSPatch_NewDocument:);


    macroSwizzleInstanceMethod(PPPanelsController, updatePanelsVisibilityAllowedForWindow:,
                                ppGSPatch_UpdatePanelsVisibilityAllowedForWindow:);
}

+ (void) ppGSGlue_ModalSessions_Install
{
    [self ppGSGlue_ModalSessions_InstallPatches];

#if PP_OPTIONAL__BUILD_WITH_SCREENCASTING

    PPGSGlueUtils_PerformPPScreencastControllerSelectorOnEnableOrDisable(
                    @selector(ppGSGlue_ModalSessions_HandleScreencastEnableOrDisable));

#endif  // PP_OPTIONAL__BUILD_WITH_SCREENCASTING
}

+ (void) load
{
    macroPerformNSObjectSelectorAfterAppLoads(ppGSGlue_ModalSessions_Install);
}

@end

@implementation PPApplication (PPGNUstepGlue_ModalSessions)

- (void) ppGSPatch_BeginSheet: (NSWindow *) sheet
            modalForWindow: (NSWindow *) docWindow
            modalDelegate: (id) modalDelegate
            didEndSelector: (SEL) didEndSelector
            contextInfo: (void *) contextInfo
{
    bool oldDisallowManualPostingOfSheetNotifications =
                                                gDisallowManualPostingOfSheetNotifications;

    gDisallowManualPostingOfSheetNotifications = YES;

    [self ppGSPatch_BeginSheet: sheet
            modalForWindow: docWindow
            modalDelegate: modalDelegate
            didEndSelector: didEndSelector
            contextInfo: contextInfo];

    gDisallowManualPostingOfSheetNotifications = oldDisallowManualPostingOfSheetNotifications;
}

- (NSInteger) ppGSPatch_ModalSessions_RunModalForWindow: (NSWindow *) theWindow
{
    NSInteger returnValue;
    NSWindow *notifyingWindow = nil;
    bool shouldSendSheetNotifications;

    [self ppGSGlue_IncrementModalSessionCount];

#if PP_OPTIONAL__BUILD_WITH_SCREENCASTING

    if (gScreencastingIsEnabled)
    {
        [[PPScreencastController sharedController] performSelector:
                                                             @selector(clearScreencastState)];
    }

#endif  // PP_OPTIONAL__BUILD_WITH_SCREENCASTING

    shouldSendSheetNotifications = (gDisallowManualPostingOfSheetNotifications) ? NO : YES;

    if (shouldSendSheetNotifications)
    {
        notifyingWindow = [theWindow parentWindow];

        if (!notifyingWindow)
        {
            notifyingWindow = [self mainWindow];
        }

        [[NSNotificationCenter defaultCenter]
                                    postNotificationName: NSWindowWillBeginSheetNotification
                                    object: notifyingWindow];
    }

    returnValue = [self ppGSPatch_ModalSessions_RunModalForWindow: theWindow];

    if (shouldSendSheetNotifications)
    {
        [[NSNotificationCenter defaultCenter]
                                    postNotificationName: NSWindowDidEndSheetNotification
                                    object: notifyingWindow];
    }

    [self ppGSGlue_DecrementModalSessionCount];

    gLastModalSessionEndTime = [NSDate timeIntervalSinceReferenceDate];

    return returnValue;
}

@end

@implementation NSMenu (PPGNUstepGlue_ModalSessions)

- (void) ppGSPatch_PerformActionForItemAtIndex: (NSInteger) index
{
    if (gModalSessionCount > 0)
    {
        static NSSet *disallowedModalActionNamesSet = nil;

        SEL action = [[self itemAtIndex: index] action];
        NSString *actionName = (action) ? NSStringFromSelector(action) : nil;

        if (!disallowedModalActionNamesSet)
        {
            disallowedModalActionNamesSet = [DisallowedModalActionNamesSet() retain];
        }

        if (actionName && [disallowedModalActionNamesSet containsObject: actionName])
        {
            return;
        }
    }

    [self ppGSPatch_PerformActionForItemAtIndex: index];
}

@end

@implementation NSDocumentController (PPGNUstepGlue_ModalSessions)

- (void) ppGSPatch_NewDocument: (id) sender
{
    if (([NSDate timeIntervalSinceReferenceDate] - gLastModalSessionEndTime)
            < kMinTimeIntervalToAllowNewDocumentAfterModalSessionEnds)
    {
        return;
    }

    [NSApp ppGSGlue_IncrementModalSessionCount];

    [self ppGSPatch_NewDocument: sender];

    [NSApp ppPerformSelectorFromNewStackFrame: @selector(ppGSGlue_DecrementModalSessionCount)];
}

@end

@interface PPPanelsController (PPGNUstepGlue_ModalSessions_PrivateMethodDeclarations)

// -[PPPanelsController updatePanelsVisibilityAllowedForWindow:] patch below needs to call
// private PPPanelsController method:
- (void) setPanelsVisibilityAllowed: (bool) panelsVisibilityAllowed;

@end

@implementation PPPanelsController (PPGNUstepGlue_ModalSessions)

- (void) ppGSPatch_UpdatePanelsVisibilityAllowedForWindow: (NSWindow *) window
{
    bool panelsVisibilityAllowed = NO;

    if (([window class] == [PPDocumentWindow class]) && ![window attachedSheet]
        && (gModalSessionCount <= 0))
    {
        panelsVisibilityAllowed = YES;
    }

    [self setPanelsVisibilityAllowed: panelsVisibilityAllowed];
}

@end

#if PP_OPTIONAL__BUILD_WITH_SCREENCASTING

@implementation PPScreencastController (PPGNUstepGlue_ModalSessions)

- (void) ppGSGlue_ModalSessions_HandleScreencastEnableOrDisable
{
    gScreencastingIsEnabled = (_screencastingIsEnabled) ? YES : NO;
}

@end

#endif  // PP_OPTIONAL__BUILD_WITH_SCREENCASTING

@implementation NSColor (PPGNUstepGlue_ModalSessionsUtilities)

- (NSColor *) ppGSGlue_PatternColorDissolvedToOpacity: (float) opacity
{
    NSImage *patternImage, *dissolvedPatternImage;
    NSColor *dissolvedPatternColor;

    if (opacity >= 1.0)
    {
        return self;
    }
    else if (opacity <= 0.0)
    {
        return [NSColor clearColor];
    }

    patternImage = [self patternImage];

    if (!patternImage)
        goto ERROR;

    dissolvedPatternImage =
        [NSImage ppImageWithBitmap:
                        [[patternImage ppBitmap] ppImageBitmapDissolvedToOpacity: opacity]];

    if (!dissolvedPatternImage)
        goto ERROR;

    dissolvedPatternColor = [NSColor colorWithPatternImage: dissolvedPatternImage];

    if (!dissolvedPatternColor)
        goto ERROR;

    return dissolvedPatternColor;

ERROR:
    return [NSColor clearColor];
}

@end

@implementation NSApplication (PPGNUstepGlue_ModalSessionsUtilities)

- (void) ppGSGlue_IncrementModalSessionCount
{
    gModalSessionCount++;

    if (gModalSessionCount == 1)
    {
        gMainCanvasViewDuringModalSession = CurrentMainWindowCanvasView();

        if (!gCanvasViewDrawRectPatchIsInstalled)
        {
            ToggleModalSessionCanvasViewDrawRectPatch();
            gCanvasViewDrawRectPatchIsInstalled = YES;
        }
    }
    else if (gModalSessionCount > 1)
    {
        // when creating a new image, the new document window doesn't become main until
        // gModalSessionCount > 1, so need to check whether the main canvas view has changed
        PPCanvasView *currentMainCanvasView = CurrentMainWindowCanvasView();

        if (gMainCanvasViewDuringModalSession != currentMainCanvasView)
        {
            PPCanvasView *lastMainCanvasView = gMainCanvasViewDuringModalSession;

            gMainCanvasViewDuringModalSession = currentMainCanvasView;

            [lastMainCanvasView setNeedsDisplay: YES];
            [lastMainCanvasView displayIfNeeded];

            [gMainCanvasViewDuringModalSession setNeedsDisplay: YES];
            [gMainCanvasViewDuringModalSession displayIfNeeded];
        }
    }
}

- (void) ppGSGlue_DecrementModalSessionCount
{
    gModalSessionCount--;

    if (gModalSessionCount <= 0)
    {
        gMainCanvasViewDuringModalSession = nil;

        if (gCanvasViewDrawRectPatchIsInstalled)
        {
            ToggleModalSessionCanvasViewDrawRectPatch();
            gCanvasViewDrawRectPatchIsInstalled = NO;
        }
    }
}

@end

@implementation PPCanvasView (PPGNUstepGlue_ModalSessionsTemporaryPatch)

// temporary patch for -[PPCanvasView drawRect:], installed during a modal session to draw a
// 'disabled' pattern over non-main canvas views - GNUstep can't prevent the window manager
// from bringing other document windows to the front during a modal session (though they won't
// respond to user interaction while the app's in a modal runloop), so the disabled pattern
// signals to the user that non-main windows aren't currently interactive

- (void) ppGSPatch_ModalSessions_DrawRect: (NSRect) rect
{
    static NSColor *inactiveCanvasOverlayColor = nil;

    if (!inactiveCanvasOverlayColor)
    {
        inactiveCanvasOverlayColor = [kInactiveCanvasOverlayColor retain];
    }

    [self ppGSPatch_ModalSessions_DrawRect: rect];

    if ((gModalSessionCount > 0) && (self != gMainCanvasViewDuringModalSession))
    {
        [inactiveCanvasOverlayColor set];
        [[NSBezierPath bezierPathWithRect: rect] fill];
    }
}

@end

static void ToggleModalSessionCanvasViewDrawRectPatch(void)
{
    macroSwizzleInstanceMethod(PPCanvasView, drawRect:, ppGSPatch_ModalSessions_DrawRect:);

    // force all canvas views to redraw after toggling patch
    RedrawAllCanvasViews();
}

static void RedrawAllCanvasViews(void)
{
    static Class PPDocumentClass = nil;
    NSEnumerator *documentEnumerator;
    PPDocument *ppDocument;
    PPCanvasView *canvasView;

    if (!PPDocumentClass)
    {
        PPDocumentClass = [PPDocument class];
    }

    documentEnumerator =
                [[[NSDocumentController sharedDocumentController] documents] objectEnumerator];

    while (ppDocument = (PPDocument *) [documentEnumerator nextObject])
    {
        if ([ppDocument isMemberOfClass: PPDocumentClass])
        {
            canvasView = [[ppDocument ppDocumentWindowController] canvasView];
            [canvasView setNeedsDisplay: YES];
            [canvasView displayIfNeeded];
        }
    }
}

static PPCanvasView *CurrentMainWindowCanvasView(void)
{
    static Class PPDocumentWindowControllerClass = nil;
    PPDocumentWindowController *ppDocumentWindowController;

    if (!PPDocumentWindowControllerClass)
    {
        PPDocumentWindowControllerClass = [PPDocumentWindowController class];
    }

    ppDocumentWindowController = [[NSApp mainWindow] windowController];

    if (![ppDocumentWindowController isMemberOfClass: PPDocumentWindowControllerClass])
    {
        return nil;
    }

    return [ppDocumentWindowController canvasView];
}

#endif  // GNUSTEP

