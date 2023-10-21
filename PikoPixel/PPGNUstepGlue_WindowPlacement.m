/*
    PPGNUstepGlue_WindowPlacement.m

    Copyright 2023 Josh Freeman
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

//  Fix for an issue on Openbox WM (LXDE, LXQt) where PP's initial document window is placed
// too high onscreen, obscuring its title bar behind the desktop's menu bar (if it's a top-edge
// menu bar, as with Raspberry Pi OS).
//  Other WMs automatically reposition windows to prevent them from overlapping with the
// desktop menu, but Openbox doesn't appear to do this, so when running on that WM, force the
// initial document window to be positioned at a lower point that accounts for a top-edge menu.
//  The workaround temporarily patches -[NSScreen visibleFrame] while PikoPixel's setting up
// its globals for positioning the initial document window (in
// -[PPDocumentWindowController setupNewWindowGlobals]), so that visibleFrame returns a
// modified screen frame with the top edge moved down by kTopEdgeMenuBarMargin.

#ifdef GNUSTEP

#import <Cocoa/Cocoa.h>
#import "NSObject_PPUtilities.h"
#import "PPAppBootUtilities.h"
#import "PPGNUstepGlueUtilities.h"
#import "PPDocumentWindowController.h"


#define kTargetWindowManagerTypesMask_WindowPlacement       \
                (kPPGSWindowManagerTypeMask_Openbox)         


#define kTopEdgeMenuBarMargin   32


@implementation NSObject (PPGNUstepGlue_WindowPlacement)

+ (void) ppGSGlue_WindowPlacement_InstallPatches
{
    macroSwizzleClassMethod(PPDocumentWindowController, setupNewWindowGlobals, 
                            ppGSPatch_WindowPlacement_SetupNewWindowGlobals);
}

+ (void) ppGSGlue_WindowPlacement_Install
{
    if (!PPGSGlueUtils_WindowManagerMatchesTypeMask(
                                            kTargetWindowManagerTypesMask_WindowPlacement))
    {
        return;
    }

    [self ppGSGlue_WindowPlacement_InstallPatches];

    // +[PPDocumentWindowController setupNewWindowGlobals] will already have been called at
    // this point (from +[PPDocumentWindowController initialize]), so manually call it again
    // to have it run with the patches installed
    [PPDocumentWindowController performSelector: @selector(setupNewWindowGlobals)];
}

+ (void) load
{
    macroPerformNSObjectSelectorAfterAppLoads(ppGSGlue_WindowPlacement_Install);
}

@end

@implementation PPDocumentWindowController (PPGNUstepGlue_WindowPlacement)

+ (void) ppGSPatch_WindowPlacement_SetupNewWindowGlobals
{
    macroSwizzleInstanceMethod(NSScreen, visibleFrame, ppGSPatch_WindowPlacement_VisibleFrame);

    [self ppGSPatch_WindowPlacement_SetupNewWindowGlobals];

    macroSwizzleInstanceMethod(NSScreen, visibleFrame, ppGSPatch_WindowPlacement_VisibleFrame);
}

@end

@implementation NSScreen (PPGNUstepGlue_WindowPlacement)

- (NSRect) ppGSPatch_WindowPlacement_VisibleFrame
{
    NSRect visibleFrame = [self ppGSPatch_WindowPlacement_VisibleFrame];

    if (visibleFrame.size.height > kTopEdgeMenuBarMargin)
    {
        visibleFrame.size.height -= kTopEdgeMenuBarMargin;
    }

    return visibleFrame;
}

@end

#endif  // GNUSTEP

