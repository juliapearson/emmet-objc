//
//  ZenCoding.m
//  ZenCoding
//
//  Created by Сергей Чикуёнок on 2/9/12.
//  Copyright 2012 Аймобилко. All rights reserved.
//

#import "ZenCoding.h"
#import "ZenCodingDefaultsKeys.h"
#import "ZenCodingNotifications.h"
#import "NSMutableDictionary+ZCUtils.h"
#import "JSONKit.h"

@interface ZenCoding ()
- (void)setupJSContext;
- (void)loadUserData;
- (NSDictionary *)settingsFromDefaults;
- (void)shouldReloadContext:(NSNotification *)notification;
@end

@implementation ZenCoding

@synthesize context, jsc, extensionsPath=_extensionsPath;

static ZenCoding *instance = nil;

+(ZenCoding *) sharedInstance {
	@synchronized(self) {
		if (instance == nil) {
			instance = [[ZenCoding alloc] init];
		}
		return instance;
	}
}

- (id)init {
    if (self = [super init]) {
        [self setupJSContext];
		// subscribe for user preferences change notifications:
		// we have to re-create JS context in order to load the latest
		// user preferences.
		// Right now, the only easy way to understand if anything is changed
		// is to listen to "close" event of preferences window
		[[NSNotificationCenter defaultCenter] addObserver:self 
												 selector:@selector(shouldReloadContext:) 
													 name:PreferencesWindowClosed 
												   object:nil];
		
    }
    
    return self;
}

- (id)initWithExtensionsPath:(NSString *)path {
	if (self = [super init]) {
		self.extensionsPath = path;
	}
	
	return self;
}

- (void)setupJSContext {
	if (self->jsc != nil) {
		[self->jsc release];
	}
	
	self->jsc = [JSCocoa new];
	
	jsc.useAutoCall = NO;
	jsc.useJSLint = NO;
	
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	[jsc evalJSFile:[bundle pathForResource:@"zencoding" ofType:@"js"]];
	[jsc evalJSFile:[bundle pathForResource:@"objc-zeneditor-wrap" ofType:@"js"]];
	
	// load Zen Coding extensions
	if (extensionsPath) {
		NSString *extPath = extensionsPath;
		BOOL isDir;
		NSFileManager *fm = [NSFileManager defaultManager];
		if ([fm fileExistsAtPath:extPath isDirectory:&isDir] && isDir) {
			NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:extPath];
			
			// find all JS files and eval them
			NSString *file;
			while (file = [dirEnum nextObject]) {
				if ([[[file pathExtension] lowercaseString] isEqualToString: @"js"]) {
					[jsc evalJSFile:[extPath stringByAppendingPathComponent:file]];
				}
			}
		}
	}
	
	// load user preferences
	// TODO load output profiles
	[self loadUserData];
}

- (void)setContext:(id)ctx {
	if (self->context != ctx) {
		if (self->context)
			[self->context release];
		
		self->context = nil;
		if (ctx) {
			self->context = [ctx retain];
			[self evalFunction:@"objcSetContext" withArguments:ctx, nil];
		}
	}
}

- (NSString *)extensionsPath {
	NSString *path = self->_extensionsPath;
	if (path == nil || [path isEqual:@""]) {
		path = [[NSUserDefaults standardUserDefaults] stringForKey:ExtensionsPath];
	}
	
	if (path != nil && ![path isEqual:@""]) {
		path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([path hasPrefix:@"~"]) {
			path = [path stringByExpandingTildeInPath];
		}
		
		return path;
	}
	
	return nil;
}

- (void)setExtensionsPath:(NSString *)path {
	if (![extensionsPath isEqual:path]) {
		if (self->_extensionsPath != nil) {
			[self->_extensionsPath release];
		}
		
		self->_extensionsPath = [path retain];
		
		[self setupJSContext];
	}
}

- (BOOL)runAction:(id)name {
	return [jsc toBool:[self evalFunction:@"objcRunAction" withArguments:name, nil]];
}

- (JSValueRef)evalFunction:(NSString *)funcName withArguments:(id)firstArg, ... {
	// Convert args to array
	id arg;
	NSMutableArray *arguments = [NSMutableArray array];
	NSMutableArray *argNames = [NSMutableArray array];
	
	if (firstArg) {
		[arguments addObject:firstArg];
		
		va_list	args;
		va_start(args, firstArg);
		while ((arg = va_arg(args, id)))	
			[arguments addObject:arg];
		va_end(args);
	}
	
	// register all arguments in JS context
	for (NSUInteger i = 0; i < [arguments count]; i++) {
		[argNames addObject:[NSString stringWithFormat:@"__objcArg%d", i]];
		[jsc setObject:[arguments objectAtIndex:i] withName:[argNames lastObject]];
	}
	
	// create JS string to evaluate
	NSString *jsString = [NSString stringWithFormat:@"%@(%@)", funcName, [argNames componentsJoinedByString:@", "]];
	
	NSLog(@"Eval JS: %@", jsString);
	JSValueRef result = [jsc evalJSString:jsString];
	
	// unregister all arguments from JS context
	for (NSString *argName in argNames) {
		[jsc removeObjectWithName:argName];
	}
	
	return result;
}

- (void)loadUserData {
	NSString *settingsContents = @"{}";
	
	// check if settings.json exists in extensions path
	if (extensionsPath) {
		NSString *settingsFile = [extensionsPath stringByAppendingPathComponent:@"settings.json"];
		if ([[NSFileManager defaultManager] isReadableFileAtPath:settingsFile]) {
			settingsContents = [NSString stringWithContentsOfFile:settingsFile encoding:NSUTF8StringEncoding error:nil];
		}
	}
	
	// pass data as JSON strings for safer internal types conversion
	[self evalFunction:@"objcLoadUserPrefs" withArguments:settingsContents, [[self settingsFromDefaults] JSONString], nil];
}

- (NSDictionary *)settingsFromDefaults {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *result = [NSMutableDictionary new];
	NSMutableDictionary *ctx;
	
	// read variables
	NSArray *defaultsCtx = [defaults arrayForKey:Variables];
	if (defaultsCtx) {
		ctx = [NSMutableDictionary new];
		for (NSDictionary *item in defaultsCtx) {
			[ctx setObject:[item objectForKey:@"value"] forKey:[item objectForKey:@"name"]];
		}
		
		[result setObject:ctx forKey:@"variables"];
		[ctx release];
		defaultsCtx = nil;
	}
	
	// Read abbreviations and snippets. Since they share the same syntax
	// context, we need to create single context for both of them
	ctx = [NSMutableDictionary new];
	NSMutableDictionary *syntaxCtx;
	NSString *syntax;
	
	defaultsCtx = [defaults arrayForKey:Abbreviations];
	if (defaultsCtx) {
		for (NSDictionary *item in defaultsCtx) {
			syntax = [item objectForKey:@"syntax"];			
			syntaxCtx = [[ctx dictionaryForKey:syntax] dictionaryForKey:@"abbreviations"];
			[syntaxCtx setObject:[item objectForKey:@"value"] forKey:[item objectForKey:@"name"]];
		}
	}
	
	defaultsCtx = [defaults arrayForKey:Snippets];
	if (defaultsCtx) {
		for (NSDictionary *item in defaultsCtx) {
			syntax = [item objectForKey:@"syntax"];			
			syntaxCtx = [[ctx dictionaryForKey:syntax] dictionaryForKey:@"snippets"];
			[syntaxCtx setObject:[item objectForKey:@"value"] forKey:[item objectForKey:@"name"]];
		}
	}
	
	[result addEntriesFromDictionary:ctx];
	[ctx release];
	
	return result;
}

- (void)shouldReloadContext:(NSNotification *)notification {
	NSLog(@"Reloading context");
	// remember previously saved context
	id ctx = self.context;
	self.context = nil;
	[self setupJSContext];
	self.context = ctx;
}

- (void)dealloc {
	if (self->_extensionsPath) {
		[self->_extensionsPath release];
	}
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

@end
