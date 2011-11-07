// Copyright © 1999-2011 deviantART Inc.

#import "DAUtils.h"
#import "NSString+Base36.h"


@implementation DAUtils

+ (NSString *) deviationURL:(NSInteger)stashId {
	return [NSString stringWithFormat: @"http://sta.sh/0%@", [NSString base36StringFromInteger:stashId]];
}

@end
