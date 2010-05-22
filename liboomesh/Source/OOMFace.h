/*	
	OOMFace.h
	liboomesh
	
	A face is simply a collection of three vertices. All other attributes
	depend on context.
	
	
	Copyright © 2010 Jens Ayton.
	
	Permission is hereby granted, free of charge, to any person obtaining a
	copy of this software and associated documentation files (the “Software”),
	to deal in the Software without restriction, including without limitation
	the rights to use, copy, modify, merge, publish, distribute, sublicense,
	and/or sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following conditions:
	
	The above copyright notice and this permission notice shall be included in
	all copies or substantial portions of the Software.
	
	THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
	THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
	DEALINGS IN THE SOFTWARE.
*/

#import "liboomeshbase.h"

@class OOMVertex;


@interface OOMFace: NSObject
{
@private
	OOMVertex			*_vertices[3];
}

+ (id) faceWithVertex0:(OOMVertex *)vertex0 vertex1:(OOMVertex *)vertex1 vertex2:(OOMVertex *)vertex2;
+ (id) faceWithVertices:(OOMVertex *[3])vertices;

- (id) initWithVertex0:(OOMVertex *)vertex0 vertex1:(OOMVertex *)vertex1 vertex2:(OOMVertex *)vertex2;
- (id) initWithVertices:(OOMVertex *[3])vertices;

- (OOMVertex *) vertexAtIndex:(OOUInteger)index;

@end
