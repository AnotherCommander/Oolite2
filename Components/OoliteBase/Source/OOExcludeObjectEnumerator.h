/*

OOExcludeObjectEnumerator.h

Simple filter to exclude one object from an NSEnumerator.


Oolite
Copyright (C) 2004-2011 Giles C Williams and contributors

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


@interface OOExcludeObjectEnumerator: NSEnumerator
{
@private
	NSEnumerator			*_enumerator;
	id						_excludeObject;
}

+ (id) enumeratorWithEnumerator:(NSEnumerator *)enumerator
				excludingObject:(id)object;

@end


@interface NSEnumerator (OOExcludingObject)

- (id) ooExcludingObject:(id)object;

@end
