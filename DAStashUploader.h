// Copyright © 1999-2011 deviantART Inc.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <WebKit/WebFrameLoadDelegate.h>
#import <OAuth2Client/NXOAuth2.h>
#import <DeviantART/DAStashUploaderDelegate.h>

@interface DAStashUploader : NSObject <NXOAuth2ClientDelegate, NXOAuth2ConnectionDelegate> {
	NSString *dASecureURL;
	NSString *dAStashAPIURL;
	NSString *dAStashAPIPlaceboURL;
	NSURLConnection *connection;
	NSMutableURLRequest *lastRequest;
	NXOAuth2Client *client;
	NSObject<DAStashUploaderDelegate> *delegate;
	NSFileManager *fileManager;
	WebView *webView;
    WebFrame *webFrame;
	NSWindow *webWindow;
	
	NSMutableDictionary *sizeList;
	NSMutableArray *fileNames;
	NSMutableDictionary *fileInfo;
	NSInteger folderid;
	
	BOOL tokenResetDuringSession;
	BOOL submitting;
	BOOL retry;
	BOOL voluntaryLogout;
	unsigned int total;
	unsigned int currentSize;
	unsigned int totalSize;
	unsigned int totalProgress;
}

// Public

- (id) initWithClientID:(NSString *)clientID clientSecret:(NSString *)clientSecret delegate:(NSObject<DAStashUploaderDelegate> *)aDelegate;
- (void) queueFileName:(NSString *)newFileName;
- (void) queueFileName:(NSString *)newFileName title:(NSString *)title comments:(NSString *)comments folder:(NSString *)folder;
- (void) cancelFileName:(NSString *)existingFileName;
- (void) logout;
- (BOOL) isLoggedIn;

// Private

- (void) queueFileInfo:(NSDictionary *)fileInfo;

- (NXOAuth2Client *) client;
- (void) oauthClientNeedsAuthentication:(NXOAuth2Client *)aClient;
- (void) oauthClientDidGetAccessToken:(NXOAuth2Client *)aClient;
- (void) oauthClientDidLoseAccessToken:(NXOAuth2Client *)aClient;
- (void) oauthClient:(NXOAuth2Client *)aClient didFailToGetAccessTokenWithError:(NSError *)error;

- (void) connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response;
- (void) connection:(NSURLConnection *)connection didReceiveData:(NSData*)data;
- (void) connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite;

- (void) uploadNextFileName;
- (void) submitToStash;

@end
