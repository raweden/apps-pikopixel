/*
    PPDocumentSamplerImagesSettingsSheetController.h

    Copyright 2013-2018 Josh Freeman
    http://www.twilightedge.com

    This file is part of PikoPixel for Mac OS X and GNUstep.
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

#import "PPDocumentSheetController.h"


@interface PPDocumentSamplerImagesSettingsSheetController : PPDocumentSheetController
{
    IBOutlet NSTableView *_samplerImagesTable;

    IBOutlet NSButton *_copyImageToClipboardButton;
    IBOutlet NSButton *_removeImageButton;
    IBOutlet NSButton *_removeAllImagesButton;

    NSMutableArray *_samplerImages;

    NSInteger _samplerImagesTableImageColumn;
}

+ (bool) beginSamplerImagesSettingsSheetForWindow: (NSWindow *) window
            samplerImages: (NSArray *) samplerImages
            delegate: (id) delegate;

- (IBAction) addImageFromClipboardButtonPressed: (id) sender;
- (IBAction) addImageFromFileButtonPressed: (id) sender;
- (IBAction) copyImageToClipboardButtonPressed: (id) sender;
- (IBAction) removeImageButtonPressed: (id) sender;
- (IBAction) removeAllImagesButtonPressed: (id) sender;

@end

@interface NSObject (PPDocumentSamplerImagesSettingsSheetDelegateMethods)

- (void) samplerImagesSettingsSheetDidFinishWithSamplerImages: (NSArray *) samplerImages;

- (void) samplerImagesSettingsSheetDidCancel;

@end
