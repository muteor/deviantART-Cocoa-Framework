// Copyright © 1999-2011 deviantART Inc.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>


@protocol DAStashUploaderDelegate

@optional

- (void) uploadStarted:(NSString*)fileName;
- (void) uploadProgress:(float)newProgress;
- (void) uploadDone:(NSInteger)aStashid folderId: (NSInteger)aFolderId;
- (void) uploadError:(NSString*)errorHuman;

- (void) uploadsRemaining:(unsigned int)filesLeft total:(unsigned int)total;
- (void) uploadsDone;

- (void) loggedout;
- (void) loggedin;

- (void) internetOffline;
- (void) internetOnline;

@end
