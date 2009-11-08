/*

ResourceManager.h

Singleton class responsible for loading various data files.

Oolite
Copyright (C) 2004-2008 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#import "OOCocoa.h"
#import "OOOpenGL.h"


#define OOLITE_EXCEPTION_FATAL					@"OoliteFatalException"

@class OOSound, OOMusic;


typedef enum
{
	MERGE_NONE,		// Just use the last file in search order.
	MERGE_BASIC,	// Merge files by adding the top-level items of each file.
	MERGE_SMART		// Merge files by merging the top-level elements of each file (second-order merge, but not recursive)
} OOResourceMergeMode;


@interface ResourceManager : NSObject

+ (NSArray *)rootPaths;			// Places add-ons are searched for, not including add-on paths.
+ (NSString *)builtInPath;		// Path for built-in data only.
+ (NSArray *)pathsWithAddOns;	// Root paths + add-on paths.
+ (NSArray *)paths;				// builtInPath or pathsWithAddOns, depending on useAddOns state.
+ (BOOL)useAddOns;
+ (NSArray *)OXPsWithMessagesFound;
+ (void)setUseAddOns:(BOOL)useAddOns;
+ (void)addExternalPath:(NSString *)fileName;
+ (NSEnumerator *)pathEnumerator;
+ (NSEnumerator *)reversePathEnumerator;

+ (void)handleEquipmentListMerging: (NSMutableArray *)arrayToProcess forLookupIndex:(unsigned)lookupIndex;

+ (NSString *)errors;			// Errors which occured during path scanning - essentially a list of OXPs whose requires.plist is bad.

+ (NSString *) pathForFileNamed:(NSString *)fileName inFolder:(NSString *)folderName;
+ (NSString *) pathForFileNamed:(NSString *)fileName inFolder:(NSString *)folderName cache:(BOOL)useCache;

+ (NSDictionary *)dictionaryFromFilesNamed:(NSString *)fileName
								  inFolder:(NSString *)folderName
								  andMerge:(BOOL) mergeFiles;
+ (NSDictionary *)dictionaryFromFilesNamed:(NSString *)fileName
								  inFolder:(NSString *)folderName
								 mergeMode:(OOResourceMergeMode)mergeMode
									 cache:(BOOL)useCache;

+ (NSArray *)arrayFromFilesNamed:(NSString *)fileName
						inFolder:(NSString *)folderName
						andMerge:(BOOL) mergeFiles;
+ (NSArray *)arrayFromFilesNamed:(NSString *)fileName
						inFolder:(NSString *)folderName
						andMerge:(BOOL) mergeFiles
						   cache:(BOOL)useCache;

+ (NSDictionary *) whitelistDictionary;	// method-whitelist.plist, explicitly not merged like normal plists.

+ (OOSound *)ooSoundNamed:(NSString *)fileName inFolder:(NSString *)folderName;
+ (OOMusic *)ooMusicNamed:(NSString *)fileName inFolder:(NSString *)folderName;

+ (NSString *) stringFromFilesNamed:(NSString *)fileName inFolder:(NSString *)folderName;
+ (NSString *) stringFromFilesNamed:(NSString *)fileName inFolder:(NSString *)folderName cache:(BOOL)useCache;

+ (NSDictionary *)loadScripts;

+ (BOOL) writeDiagnosticData:(NSData *)data toFileNamed:(NSString *)name;

// Clear ResourceManager-internal caches (not those handled by OOCacheManager)
+ (void) clearCaches;

@end
