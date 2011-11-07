// Copyright © 1999-2011 deviantART Inc.

#import "NSString+Base36.h"


@implementation NSString (Base36)

+ (NSString *) base36StringFromInteger: (NSInteger)number {
	static char table[] = "0123456789abcdefghijklmnopqrstuvwxyz";
	
	NSString *result = [NSString stringWithFormat:@""];
	
	NSInteger dividend = number;
	
	do {
		NSInteger modulo = dividend % 36;
		result = [NSString stringWithFormat:@"%c%@", table[modulo], result];
		
		dividend = dividend / 36;
	} while (dividend > 0);
	
	return result;
}

@end