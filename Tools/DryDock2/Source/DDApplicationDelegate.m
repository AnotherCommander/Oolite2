//
//  DDApplicationDelegate.m
//  DryDock2
//
//  Created by Jens Ayton on 2010-08-29.
//  Copyright 2010 Jens Ayton. All rights reserved.
//

#import "DDApplicationDelegate.h"
#include <asl.h>


@implementation DDApplicationDelegate

- (void) awakeFromNib
{
	OOLoggingInit(self);
}


- (BOOL) shouldShowMessageInClass:(NSString *)messageClass
{
	if ([messageClass hasPrefix:@"rendering.opengl"])  return NO;
//	if ([messageClass hasPrefix:@"texture.load"])  return NO;
	
	return YES;
}


- (BOOL) showMessageClass
{
	return NO;//YES;
}

@end
