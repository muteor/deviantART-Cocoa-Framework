// Copyright © 1999-2011 deviantART Inc.

#import <DeviantART/DAStashUploader.h>
#import <JSON/JSON.h>
#import "NSString+Base64.h"


@implementation DAStashUploader

- (id) initWithClientID:(NSString *)clientID clientSecret:(NSString *)clientSecret delegate:(NSObject<DAStashUploaderDelegate> *)aDelegate {
	if (self = [super init]) {
		fileNames = [[NSMutableArray alloc] init];
		sizeList = [[NSMutableDictionary alloc] init];
		
		dASecureURL = [[NSString alloc ]initWithString:@"https://www.deviantart.com"];
		dAStashAPIURL = [[NSString alloc] initWithString:@"https://www.deviantart.com/api/draft10/submit"];
		dAStashAPIPlaceboURL = [[NSString alloc] initWithString:@"https://www.deviantart.com/api/draft10/placebo"];
		
		client = [[NXOAuth2Client alloc] initWithClientID:clientID
											 clientSecret:clientSecret
											 authorizeURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", dASecureURL, @"/oauth2/authorize"]]
												 tokenURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", dASecureURL, @"/oauth2/token"]]
												 delegate:self];
		
		delegate = [aDelegate retain];
		
		fileManager = [[NSFileManager defaultManager] retain];
		
		webWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0f,0.0f,700.0f,550.0f)
											 styleMask:NSTitledWindowMask|NSClosableWindowMask
											   backing:NSBackingStoreBuffered
												 defer:NO];
		
		
		webView  = [[WebView alloc] initWithFrame: NSMakeRect (0,0,700,550)];
		webFrame = [webView mainFrame];
		[webView setFrameLoadDelegate:self];
		
		[webWindow setContentView:webView];
		[webWindow setTitle:@"Authorize this app"];
		[webWindow setReleasedWhenClosed:NO];
	}
	
	return self;
}

- (void) dealloc {
	[webView release];
	[webFrame release];
	[webWindow release];
	[fileManager release];
	[fileNames release];
	[dASecureURL release];
	[dAStashAPIURL release];
	[client release];
	[delegate release];
	[sizeList release];
	
	if (connection) {
		[connection release];
	}
	
	if (lastRequest) {
		[lastRequest release];
	}
	
	if (fileInfo) {
		[fileInfo release];
	}
	
	[super dealloc];
}

- (NXOAuth2Client *) client {
	return client;
}

- (void) oauthClientNeedsAuthentication:(NXOAuth2Client *)aClient {
	NSURL *authorizationURL = [aClient authorizationURLWithRedirectURL:[NSURL URLWithString:@"dAStashUploader://oauth2"]];
	
	NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
	[request setURL:authorizationURL];
	
	[webFrame loadRequest:request];
	
	[request release];
}

- (void) oauthClientDidGetAccessToken:(NXOAuth2Client *)aClient {
	[delegate loggedin];
	
    if (submitting) {
        if (fileInfo) {
            [self submitToStash];
        } else {
            [self uploadNextFileName];
        }
    }
}

- (void) oauthClientDidLoseAccessToken:(NXOAuth2Client *)aClient {
    [delegate loggedout];
}

- (void) oauthClientDidRefreshAccessToken:(NXOAuth2Client *)aClient {
    [delegate loggedin];
    
    if (fileInfo) {
        [self submitToStash];
    }
}

- (void) oauthClient:(NXOAuth2Client *)aClient didFailToGetAccessTokenWithError:(NSError *)error {
	NSLog(@"(Framework) Failed to get access token %ld", [error code]);
	[delegate loggedout];
    
    if (submitting) {
        [aClient setAccessToken:NO];
        [aClient requestAccess];
        
        if (totalProgress > 0) {
            totalProgress -= currentSize;
        }
    }
}

- (void) connection:(NSURLConnection *) connection didReceiveData:(NSData*) data {
	NSMutableData *receivedData = [[NSMutableData alloc] init];
	[receivedData appendData:data];
	
	NSString *JSONString = [[NSString alloc] initWithData:receivedData encoding:NSUTF8StringEncoding];
	
	SBJsonParser *parser = [[SBJsonParser alloc] init];
	NSDictionary *JSON = [parser objectWithString:JSONString error:nil];
	
	NSString *status = [JSON objectForKey: @"status"];
	
	if ([status isEqualToString:@"success"]) {
		id stashid = [JSON objectForKey: @"stashid"];
		
		if (stashid == nil) { // Then we're dealing with a placebo call
			NSLog(@"Successful placebo call, send the file now");
			[self submitToStash];
			return;
		} else {
            // Upload was successful, clear the "current file to upload"
            if (fileInfo) {
                [fileInfo release];
                fileInfo = nil;
            }
        }
        
		folderid = [[JSON objectForKey: @"folderid"] intValue];
		[delegate uploadDone: [stashid longValue] folderId: folderid];
	} else {
        NSString *error = [JSON objectForKey: @"error"];
        if ([error isEqualToString:@"expired_token"]) {
            [client refreshAccessToken];
            return;
        } else if ([error isEqualToString:@"invalid_token"]) {
            [client setAccessToken:NO];
            [client requestAccess];
            
            if (totalProgress > 0) {
                totalProgress -= currentSize;
            }
            return;
        } else {
            [delegate uploadError: [[JSON objectForKey: @"error_human"] stringValue]];
        }
	}
	
	[receivedData release];
	[JSONString release];
	[parser release];
	
	submitting = NO;
	totalProgress += currentSize;
	[self uploadNextFileName];
}

- (void) connection:(NSURLConnection *) connection didSendBodyData:(NSInteger) bytesWritten totalBytesWritten:(NSInteger) totalBytesWritten totalBytesExpectedToWrite:(NSInteger) totalBytesExpectedToWrite {
	[delegate uploadProgress:(totalProgress + [[NSNumber numberWithInteger:totalBytesWritten] floatValue]) / totalSize];
}

- (void) connection:(NSURLConnection *) connection didFailWithError:(NSError *)error {
	// Connection error, probably the user's internet connection failing, let's schedule a retry
	NSLog(@"Internet connection failed, scheduling retry: %@", [error localizedDescription]);
	
	[NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(retrySubmitToStash:) userInfo:nil repeats: NO];
}

- (void) retrySubmitToStash:(NSTimer*)theTimer {
	[connection initWithRequest:lastRequest delegate:self];
}

- (void) webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame {
	NSString *url = [[[[frame provisionalDataSource] request] URL] absoluteString];
	NSLog(@"didStartProvisionalLoadForFrame: %@", url);
}

- (void) webView:(WebView *) sender didReceiveServerRedirectForProvisionalLoadForFrame:(WebFrame *) frame {
	WebDataSource *ds = [frame provisionalDataSource];
	NSMutableURLRequest *ur = [ds request];
	
	NSURL *url = [ur mainDocumentURL];
	NSString *urls = [url absoluteString];
	
	if ([urls rangeOfString:@"dAStashUploader://" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        if ([urls rangeOfString:@"error=" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [self logout];
        } else {
            [client openRedirectURL:url];
        }
        [webWindow close];
	} else {
		[webWindow makeKeyAndOrderFront:self];
		[webWindow center];
	}
}

- (void) webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame {
	NSString *url = [[[[frame provisionalDataSource] request] URL] absoluteString];
	NSLog(@"didFailProvisionalLoadWithError: %@", url);
}

- (void) webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame {
	[webWindow makeKeyAndOrderFront:self];
	[webWindow center];
}

- (void)webView:(WebView *)sender willPerformClientRedirectToURL:(NSURL *)URL delay:(NSTimeInterval)seconds fireDate:(NSDate *)date forFrame:(WebFrame *)frame {
	NSLog(@"willPerformClientRedirectToURL: %@", URL);
}

- (void) uploadNextFileName {
	BOOL wasSubmitting = submitting;
	submitting = YES;
	
	NXOAuth2AccessToken	*accessToken = [client accessToken];
	NSString *token = [accessToken accessToken];
	
	if ([fileNames count] <= 0) {
		if (!wasSubmitting) {
			submitting = NO;
			totalSize = 0;
			totalProgress = 0;
			total = 0;
			[delegate uploadsDone];
		}
		return;
	}
	
	if ([token length] == 0) {
		[self logout];
		[client requestAccess];
		return;
	}
	
	NSString *path = [NSString stringWithFormat:@"%@?", dAStashAPIPlaceboURL];
	if ([token length] > 0) {
		path = [NSString stringWithFormat:@"%@token=%@&", path, token];
	}
	
	if (fileInfo) {
		[fileInfo release];
	}
	
	fileInfo = [[fileNames objectAtIndex:0] retain]; // FIFO
	[fileNames removeObjectAtIndex:0];
	
	NSDictionary *attributes = [fileManager attributesOfItemAtPath:[fileInfo objectForKey:@"filename"] error:nil];
	currentSize = [[attributes valueForKey:NSFileSize] intValue];
	
	if (lastRequest) {
		[lastRequest release];
	}
	
	lastRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path]];
	
	[lastRequest retain];
	
	if (connection) {
		[connection release];
	}
	
	connection = [[NSURLConnection alloc] initWithRequest:lastRequest delegate:self];
	if (!connection) {
		NSLog(@"Connection failed");
	}
}

- (void) queueFileName:(NSString *)newFileName {
	NSMutableDictionary *someFileInfo = [[[NSMutableDictionary alloc] init] autorelease];
	[someFileInfo setObject:newFileName forKey:@"filename"];
	
	[self queueFileInfo:someFileInfo];
}

- (void) queueFileName:(NSString *)newFileName folder:(NSString *)folder {
    NSMutableDictionary *someFileInfo = [[[NSMutableDictionary alloc] init] autorelease];
	[someFileInfo setObject:newFileName forKey:@"filename"];
    [someFileInfo setObject:folder forKey:@"folder"];
	
	[self queueFileInfo:someFileInfo];
}

- (void) queueFileName:(NSString *)newFileName title:(NSString *)title comments:(NSString *)comments folder:(NSString *)folder {
	NSMutableDictionary *someFileInfo = [[[NSMutableDictionary alloc] init] autorelease];
	[someFileInfo setObject:newFileName forKey:@"filename"];
	[someFileInfo setObject:title forKey:@"title"];
	[someFileInfo setObject:comments forKey:@"artist_comments"];
	[someFileInfo setObject:folder forKey:@"folder"];
	
	[self queueFileInfo:someFileInfo];
}

- (void) queueFileInfo:(NSDictionary *)someFileInfo {
	total++;
	
	NSString *newFileName = [someFileInfo objectForKey:@"filename"];
	
	NSDictionary *attributes = [fileManager attributesOfItemAtPath:newFileName error:nil];
	int size = [[attributes valueForKey:NSFileSize] intValue];
	totalSize += size;
	
	[sizeList setObject:[NSNumber numberWithInt: size] forKey: newFileName];
	
	[fileNames addObject:someFileInfo];
	
	NSLog(@"Queued: %@", newFileName);
	
	if (!submitting) {
		[self uploadNextFileName];
	} else {
		[delegate uploadsRemaining:[fileNames count] + 1 total: total];
	}
}

- (void) cancelFileName:(NSString *)existingFileName {
	BOOL deletedSomething = NO;
	
	total--;
	
	if ([existingFileName isEqualToString:[fileInfo objectForKey:@"filename"]]) {
		[connection cancel]; // Abort the ongoing upload
		
		submitting = NO;
		totalSize -= currentSize;
		
		[self uploadNextFileName];
		
		deletedSomething = YES;
	}
	
	NSEnumerator *enumerator = [fileNames objectEnumerator];
	NSString *enumFileName;
	
	BOOL deletedSomethingFromQueue = NO;
	
	while (enumFileName = [[enumerator nextObject] objectForKey:@"filename"]) {
		if ([enumFileName isEqualToString:existingFileName]) {
			totalSize -= [[sizeList objectForKey: existingFileName] intValue];
			
			deletedSomethingFromQueue = YES;
			deletedSomething = YES;
			break;
		}
	}
	
	if (deletedSomethingFromQueue) {
		[fileNames removeObject:existingFileName];
	}
	
	NSLog(@"Cancelled: %@", existingFileName);
	
	if (deletedSomething) {
		if (submitting) {
			[delegate uploadsRemaining:[fileNames count] + 1 total:total];
		} else {
			[delegate uploadsRemaining:[fileNames count] total:total];
		}
	}
}

- (BOOL) isLoggedIn {
	return ([client accessToken] != nil);
}

- (void) logout {
	[client setAccessToken:NO];
	
	NSMutableURLRequest *logoutRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"http://www.deviantart.com/users/logout-from-useragent"]];
	[logoutRequest setHTTPMethod:@"POST"];
	
	[[NSURLConnection alloc] initWithRequest:logoutRequest delegate:nil];
}

- (void) submitToStash {
	[delegate uploadsRemaining:[fileNames count] + 1 total: total];
	
	NXOAuth2AccessToken	*accessToken = [client accessToken];
	NSString *token = [accessToken accessToken];
	
	NSLog(@"Token used: %@", token);
	
	NSString *path = [NSString stringWithFormat:@"%@?", dAStashAPIURL];
	if ([token length] > 0) {
		path = [NSString stringWithFormat:@"%@token=%@&", path, token];
	}
	
	if (folderid > 0 && ![fileInfo objectForKey:@"folder"]) {
		path = [NSString stringWithFormat:@"%@folderid=%d&", path, folderid];
	}
	
	if ([fileInfo objectForKey:@"folder"]) {
		NSString *cleanFolder = [[[fileInfo objectForKey:@"folder"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		path = [NSString stringWithFormat:@"%@folder=%@&", path, cleanFolder];
	}
	
	if ([fileInfo objectForKey:@"title"]) {
		NSString *cleanTitle = [[[fileInfo objectForKey:@"title"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		path = [NSString stringWithFormat:@"%@title=%@&", path, cleanTitle];
	}
	
	if ([fileInfo objectForKey:@"artist_comments"]) {
		NSString *cleanArtistComments = [[[fileInfo objectForKey:@"artist_comments"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
		path = [NSString stringWithFormat:@"%@artist_comments=%@&", path, cleanArtistComments];
	}
	
	if (lastRequest) {
		[lastRequest release];
	}
	
	lastRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path]];
	[lastRequest retain];
	
	if ([fileInfo count] > 0 && [fileInfo objectForKey:@"filename"]) {
		NSString* fileNameOnly = [[fileInfo objectForKey:@"filename"] lastPathComponent];
		NSLog(@"Sending: %@", fileNameOnly);
		NSData *data = [NSData dataWithContentsOfFile:[fileInfo objectForKey:@"filename"]];
		
		if (!data) {
			NSLog(@"No data!");
			return;
		}
		
		if ([data length] == 0) {
			NSLog(@"Empty data!");
			return;
		}
		
		NSString * boundry = @"0xKhTmLbOuNdArY";
		
		[lastRequest setHTTPMethod:@"POST"];
		[lastRequest addValue: [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundry] forHTTPHeaderField:@"Content-Type"];
		
		NSMutableData *postData = [[NSMutableData alloc] initWithCapacity:100];
		[postData appendData: [[NSString stringWithFormat:@"--%@\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
		[postData appendData: [[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\n\n", fileNameOnly] dataUsingEncoding:NSUTF8StringEncoding]];
		[postData appendData:data];
		[postData appendData: [[NSString stringWithFormat:@"\n--%@--\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
		
		[lastRequest setHTTPBody:postData];
		
		[postData autorelease];
	}
	
	if (connection) {
		[connection release];
	}
	
	connection = [[NSURLConnection alloc] initWithRequest:lastRequest delegate:self];
	if (!connection) {
		NSLog(@"Connection failed");
	}
	
	if ([fileInfo count] > 0 && [fileInfo objectForKey:@"filename"]) {
		[delegate uploadStarted: [fileInfo objectForKey:@"filename"]];
	}
}

@end
