//
//  Created by Sergey on 2/17/12.
//  Copyright (c) 2012 Аймобилко. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#define MODAL_ACTION_OK     0
#define MODAL_ACTION_CANCEL 1

#define MODAL_DEFAULT_LABEL @"Enter value"

@interface EMPromptDialogController : NSWindowController {
	NSTextField *label;
	NSTextField *inputField;
}

@property (assign) IBOutlet NSTextField *label;
@property (assign) IBOutlet NSTextField *inputField;

- (IBAction)performOK:(id)sender;
- (IBAction)performCancel:(id)sender;

+ (NSString *)prompt:(NSString *)labelText;
+ (NSString *)promptForWindow:(NSWindow *)wnd withLabel:(NSString *)labelText;

- (NSString *)promptWithLabel:(NSString *)labelText;
- (NSString *)promptForWindow:(NSWindow *)wnd withLabel:(NSString *)labelText;

@end
